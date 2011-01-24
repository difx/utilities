#!/usr/bin/perl -w

use Getopt::Long;
use IO::Socket;
use Carp;
use Astro::Time;
use POSIX;

use strict;

use constant RECORDER_SERVER => 50080;

my $recorder_hosts = undef;
$recorder_hosts = $ENV{RECORDER_HOSTS} if ($ENV{RECORDER_HOSTS});

sub checkfile($$);
sub send_data($$);
sub send_cmd($$);

my $machinefile;
my $numproc;
my $evlbi = 0;
my $monitor = undef;
my $offset = 20; # Offset in seconds for start time
my $debug = 0;

GetOptions('-machinefile=s'=>\$machinefile, 
           'np=i'=>\$numproc, 'evlbi'=>\$evlbi, 'offset=i'=>\$offset,
	   'monitor=s'=>\$monitor, 'debug'=>\$debug, 'hosts=s'=>\$recorder_hosts);

# Check passed files exist etc

if (!(defined $machinefile && defined $numproc)) {
  die "Must specify machinefile and np\n";
}

die "Offset must be positive\n" if ($offset<0);

die "Usage: startcorr.pl [options] <mpifxcorr> <inputfile>\n" if (@ARGV!=2);

my $mpifxcorr = shift @ARGV;
my $input = shift @ARGV;

checkfile('Input file', $input);
checkfile('machine', $machinefile);

my ($calc, $threads, $duration, $mjd, $seconds, $outfile);

my @active_datastreams = ();
my @telescopes = ();
my @format = ();
my @telport = ();
my @tcpwin = ();
my @bits = ();
my $bandwidth = undef;

# Grab the values we need from the input file
open(INPUT, $input) || die "Could not open $input: $!\n";
while (<INPUT>) {
  if (/CALC FILENAME:      (\S+)/) {
    $calc = $1;
  } elsif (/CORE CONF FILENAME: (\S+)/) {
    $threads = $1;
  } elsif (/EXECUTE TIME \(SEC\): (\S+)/) {
    $duration = $1;
  } elsif (/START MJD:          (\d+)/) {
    $mjd = $1;
  } elsif (/START SECONDS:      (\d+)/) {
    $seconds = $1;
  } elsif (/OUTPUT FILENAME:    (\S+)/) {
    $outfile = $1;
  } elsif (/DATASTREAM \d INDEX: (\d+)/) {
    $active_datastreams[$1] = 1;
  } elsif (/BW \(MHZ\) \d+:\s+(\S+)/) {
    if (!defined $bandwidth) {
      $bandwidth = $1;
    } else {
      if ($bandwidth != $1) {
	die "Do not support mixed bandwidth ($bandwidth/$1)\n";
      }
    }
  } elsif (/TELESCOPE NAME \d+:\s+(\S+)/) {
    push @telescopes, $1;
  } elsif (/DATA FORMAT:\s+(\S+)/) {
    push @format, $1;
  } elsif (/QUANTISATION BITS:\s+(\S+)/) {
    push @bits, $1;
  } elsif (/PORT NUM \d+:\s+(\d+)/) {
    push @telport, $1;
  } elsif (/TCP WINDOW \(KB\) \d+:\s*(-?\d+)/) {
    push @tcpwin, $1;
  }
}
close(INPUT);

# Check the input file is vaguely sane
die "CALC FILENAME not found\n" if (!defined $calc);
die "CORE CONF FILENAME not found\n" if (!defined $threads);
die "EXECUTE TIME not found\n" if (!defined $duration);
die "START MJD not found\n" if (!defined $mjd);
die "START SECONDS not found\n" if (!defined $seconds);
die "OUTPUT FILENAME not found\n" if (!defined $outfile);

checkfile('Calc file', $calc);
checkfile('Thread file', $threads);

if ($evlbi) {
  my $startmjd = now2mjd();
  {
      my ($day, $month, $year, $ut) = mjd2cal($startmjd);
      my $hms = turn2str($ut,'H',0);
      print "Current time $hms\n";
  }

  $startmjd = ceil(($startmjd*24*60*60+$offset)/10)/(24*60*6);

  $mjd += $seconds/(60*60*24);

  if ($mjd>$startmjd) {
    print "Exeriment has not yet started\n";
    $startmjd = $mjd;
  } else {

    my $finishmjd = $mjd+$duration/(60*60*24);

    $duration = sprintf "%.0f", ($finishmjd-$startmjd)*60*60*24;

    die "Experiment has finished already!\n" if ($duration<0);
  }

  $mjd = floor($startmjd);
  $seconds = sprintf "%.0f", ($startmjd - $mjd)*60*60*24;

  my ($day, $month, $year, $ut) = mjd2cal($mjd);
  my $sec = $seconds%60;
  my $hour = int $seconds/3600;
  my $min = int ($seconds-$hour*3600)/60;
  my $filetime = sprintf("%04d-%02d-%02d-%02d%02d%02d",
			 $year, $month, $day, $hour, $min, $sec);
  if ($outfile =~ /^(.*)\.([^.]+)$/) {
    $outfile = "$1-${filetime}.$2";
  } else {
    $outfile .= "-$filetime";
  }
  printf "Will start at %02d:%02d:%02d\n", $hour, $min, $sec;

  # Rewrite the output file
  my $output;
  if ($input =~ /^(.*)\.([^.]+)$/) {
    $output = "$1-${filetime}.$2";
  } else {
    $output = "$input-${filetime}";
  }

  open(INPUT, $input) || die "Could not reopen $input: $!\n";
  open(OUTPUT, '>', $output) || die "Could not open $output: $!\n";

  while (<INPUT>) {
    if (/EXECUTE TIME \(SEC\):/) {
      print OUTPUT "EXECUTE TIME \(SEC\): $duration\n";
    } elsif (/START MJD:/) {
      print OUTPUT "START MJD:          $mjd\n";
    } elsif (/START SECONDS:/) {
      print OUTPUT "START SECONDS:      $seconds\n";
    } elsif (/OUTPUT FILENAME:/) {
      print OUTPUT "OUTPUT FILENAME:    $outfile\n";
    } else {
      print OUTPUT;
    }
  }
  close(INPUT);
  close(OUTPUT);

  $input = $output;
}

die "Rpfits file $outfile already exists!\n" if (-e $outfile);

##########
# Launch LBA evlbi clients
my $status;
my $pid = 0;

my %rec_hosts = ();
if (defined $recorder_hosts && $evlbi) {
    
  print "Launching recorders\n";

  open(HOSTS, $recorder_hosts) || die "Could not open $recorder_hosts: $!\n";
  while (<HOSTS>) {
    s/^\s+//;
    s/\s+$//;
    next if ($_ eq '');
    my @vals = split;
    
    my $tel = shift @vals;
    die "Wrong hosts file format: $_ " if (@vals < 4);
    $rec_hosts{$tel} = [@vals];
  }
  close HOSTS;

  
  if ($pid = fork) { # Parent

  } else { # Child

    if (!$debug) {
      print "Waiting for DiFX to start\n";
      sleep($offset*0.5);
    }

    for (my $i=0; $i<@telescopes; $i++) {
      next if (!$active_datastreams[$i]);
      my $ant = $telescopes[$i];


      my ($recorder, $playback, $compression, $vsib_mode, $ipd);
      $recorder = $rec_hosts{$ant}->[0];
      $playback = $rec_hosts{$ant}->[1];
      $compression = $rec_hosts{$ant}->[2];
      $vsib_mode = $rec_hosts{$ant}->[3];
      $ipd = $rec_hosts{$ant}->[4];
      my $tcpwin = $tcpwin[$i];
      my $udp = 0;
      if ($tcpwin<0) {
	$udp = -$tcpwin;
	$tcpwin = 0;
      }

      if ($recorder) {
	$status = send_data("add_host=evlbi_$ant,$playback,$telport[$i],$tcpwin,1", $recorder);
	die "Failed to set add_host on $recorder\n" if (!defined $status);

	#$status = send_data("remote_host=$playback", $recorder);
	#die "Failed to set remote_host on $recorder\n" if (!defined $status);
	
	#$status = send_data("remote_port=$telport[$i]", $recorder);
	#die "Failed to set port on $recorder\n" if (!defined $status);

	# UDP
	if ($udp) {

 	  #$status = send_data("udp=$udp", $recorder);
 	  #die "Failed to set UDP on $recorder\n" if (!defined $status);

	  $ipd = 0 if (!defined $ipd);
	  $status = send_data("modify_host=evlbi_$ant,$udp,$ipd", $recorder);
	  die "Failed to enable udp on $recorder\n" if (!defined $status);
	}

	$status = send_data("recordingdisk=evlbi_$ant:",$recorder);

	$duration+=5;
	$status = send_data("record_time=${duration}s", $recorder);
	die "Failed to set recording time on $recorder\n" if (!defined $status);
	
	$status = send_data("filesize=2s", $recorder);
	die "Failed to set filesize on $recorder\n" if (!defined $status);
	
	$status = send_data("round_start=off", $recorder);
	die "Failed to set round start off, on $recorder\n" if (!defined $status);
	
	$status = send_data("bandwidth=$bandwidth", $recorder);
	die "Failed to set bandwidth on $recorder\n" if (!defined $status);

	$status = send_data("compression=$compression", $recorder);
	die "Failed to set compression on $recorder\n" if (!defined $status);

	$status = send_data("vsib_mode=$vsib_mode", $recorder);
	die "Failed to set vsib_mode on $recorder\n" if (!defined $status);

	$status = send_data("filename_prefix=$ant", $recorder);
	die "Failed to set filename_prefix on $recorder\n" if (!defined $status);
	
	if ($format[$i] eq 'MARK5B') {
	  $status = send_data("mark5b=on", $recorder);
	  die "Failed to set mark5b on $recorder\n" if (!defined $status);
	} elsif ($format[$i] eq 'LBAVSOP' || $format[$i] eq 'LBASTD') {
	  $status = send_data("mark5b=off", $recorder);
	  die "Failed to turn off mark5b on $recorder\n" if (!defined $status);
	} else {
	  die "Unsupported data format $format[$i]\n";
	}
	if ($bits[$i]==1) {
	  $status = send_data("onebit=on", $recorder);
	  die "Failed to set mark5b on $recorder\n" if (!defined $status);
	} else {
	  $status = send_data("onebit=off", $recorder);
	  die "Failed to set mark5b on $recorder\n" if (!defined $status);
	}

	$status = send_cmd("record-start", $recorder);
	die "Failed to launch recorder on $recorder\n" if (!defined $status);

	# Turn off evlbi
	$status = send_data("filesize=10s", $recorder);
	die "Failed to set filesize on $recorder\n" if (!defined $status);
	$status = send_data("round_start=on", $recorder);
	die "Failed to set round start on, on $recorder\n" if (!defined $status);
	$status = send_data("onebit=off", $recorder);
	die "Failed to set mark5b on $recorder\n" if (!defined $status);
 
	print "Launched $ant on $recorder\n" if ($recorder);
      } else {
	print "***************************Not launching recorder for $ant\n";
      }
    }
    exit;
  }
}

# mpifxcorr options

my  $mpioptions = "-machinefile $machinefile -np $numproc";

my $difx_options = '';
if ($monitor) {
  $difx_options .= " -M${monitor}:9999";
}

my $exec = "mpirun $mpioptions $mpifxcorr $input $difx_options";
print "$exec\n";
system $exec if (!$debug);

wait if ($pid);

if (%rec_hosts) {
  for (my $i=0; $i<@telescopes; $i++) {
    next if (!$active_datastreams[$i]);
    my $ant = $telescopes[$i];
    
    my $recorder = $rec_hosts{$ant}->[0];
    if ($recorder) {
      $status = send_cmd("record-stop", $recorder);
      warn "Failed to stop recorder on $recorder\n" if (!defined $status);

      $status = send_data("recordingdisk=2", $recorder);
      warn "Failed to reset recording disk on $recorder\n" if (!defined $status);

      $status = send_data("rem_host=evlbi_$ant", $recorder);
      warn "Failed to remove remote host on $recorder\n" if (!defined $status);
    }
  }
}

sub checkfile ($$) {
  my ($type, $file) = @_;
  
  die "$type $file does not exist\n" if (!-e $file);
  die "$type $file has zero size\n" if (-z $file);
  die "$type $file is not a plain file\n" if (!-f $file);
  die "$type $file is not readable\n" if (!-r $file);
  die "$type $file is a directory\n" if (-d $file);

}

sub server_comm {
  my ($type, $message, $recorder) = @_;

  if ($debug) {
    print "SEND: <$type>$message</$type> to $recorder\n";
  }

  {

    # Connect to the recorder server
    my $socket = IO::Socket::INET->new(PeerAddr => $recorder,
				       PeerPort => RECORDER_SERVER,
				      )
      || die "Could not connect to $recorder\n";

    print $socket "<$type>$message</$type>";

    # Get response
    my $ret = "";
    while(<$socket>){
      $ret .= $_;
    }
    close($socket);
    
    if ($ret =~ /<fail>(.*)<\/fail>/s) {
      carp "$1";
      return undef;
    } elsif ($ret =~ /<succ \/>/s) {
      return "";
    } elsif ($ret =~ /<status>.*<\/status>/s) {
      return $1;
    } else {
      warn "Did not understand server reponse ($ret): $!\n";
      return undef;
    }
  }
}

sub send_data($$) {
  return server_comm('data', shift, shift);
}

sub send_cmd($$) {
  return server_comm('cmnd', shift, shift);
}
