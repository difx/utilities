#!/usr/bin/perl -w
#===========================================================================
# SVN properties (DO NOT CHANGE)
#
# $Id$
# $HeadURL: $
# $LastChangedRevision$
# $Author$
# $LastChangedDate$
#
#============================================================================

use strict;
use warnings;

use Getopt::Long;
use Term::ANSIColor;
use Time::Local;


my @vexScans = ();

my  $VEXFILE	=   "";                   #   VEX File 
my  $MATRIXFILE	=   "";			#   Jobmatrixfile 

my  $help           =   0;
my  $mode           =   "";
my  $i		    =   0;
my  @Anzahl_Stationen	=   ();
my  @Stations		=   ();
my  @SplitAnzahl 	=   ();
my  $st_text  		=   "";
my  @MatrixStationen	=   ();
my  @joblist	=   ();  
my  %vexStationSum = ();
my  %stationSum = ();
my  $maxScanName = 0;
my  $maxSourceName = 0;
my  $maxModeName = 0;
my  $vexScanCount = 0;
#----------------------------------------------------------------------

&GetOptions("help" => \$help, "mode=s" => \$mode, "vexfile=s" => \$VEXFILE, "jobmatrix=s" => \$MATRIXFILE) or &printUsage(); 

if ($help || $VEXFILE eq "" || $MATRIXFILE eq "")
{
	&printUsage();
}

&main();

exit(0);

################
#                                                                                   
# MAIN
#                                                                                   
################
sub main
{      
	my %stationSums = ();


    open(MATRIXFILE,$MATRIXFILE)    || die "Jobmatrix file named \"$MATRIXFILE\" not found\n";
    @joblist = <MATRIXFILE>;

    #lese erste Zeile (enthält stationen)
    foreach $_ (@joblist)                       
        {
        chomp($_);                                
	@MatrixStationen = split(/ /,$_);
	last;				#   Array verlassen		
	}
    close   (MATRIXFILE);

	open(MATRIXFILE,$MATRIXFILE)    || die "Jobmatrix file named \"$MATRIXFILE\" not found\n";
	open(VEXFILE,   $VEXFILE)	    || die "Vex file named \"$VEXFILE\" not found\n";
	open(FILOUT,">$VEXFILE.pclist")  || die "cannot create \"$VEXFILE.pclist\" \n";

	&getStationsFromVex();
	&parseVex();
	&compare();

	close   (VEXFILE);
	close   (MATRIXFILE);
	close   (FILOUT);

}

###################################
#
# getStationsFromVex
#
###################################
      
sub getStationsFromVex
{
    my $station = "";

    push (@Anzahl_Stationen, `grep 'site_ID' $VEXFILE`);

    foreach $st_text (@Anzahl_Stationen)
    {
        $st_text	=~  y/[ ]//d;
	@SplitAnzahl    =   split   (/[=;]/, $st_text);
        push	(@Stations, uc($SplitAnzahl[1]));
    }

}

########################
#
# parseVex
#                                                                                   
########################
      
sub parseVex
{
	my $scanCount = 0;
	my $vexLine = "";
	my $isScanBlock = 0;
	my %scan = ();
	my $scanName = "";


	# loop over vex file
	foreach $vexLine (<VEXFILE>)
	{
		$vexScanCount += 1;
		chomp ($vexLine);
		
		# remove leading whitespaces
		$vexLine =~ s/^\s+//;
		

		# look for scan start
		if ($vexLine =~ /^scan\s+(.+);/)
		{
			$scanName = $1;

			$vexScans[$scanCount]{"NAME"} = $1;
			#print "$1 \n";

			if (length($scanName) > $maxScanName)
			{	
				$maxScanName = length($scanName)
			}

			
			$vexScans[$scanCount]{"MAX_DURATION"} = 0;
			$vexScans[$scanCount]{"MODE"} = "";
			$vexScans[$scanCount]{"SOURCE"} = "";

			$isScanBlock = 1;
			next;
		}
		# end of scan section
		elsif ($vexLine =~ /endscan;/) 
		{
			if ($isScanBlock)
			{
				$scanCount++;
				$isScanBlock = 0;
				next;
			}
			else
			{
				die ("endscan found without previous scan statement. Aborting");
			}
		}
		if ($isScanBlock)
		{


			# start statement in scan block
			if ($vexLine =~ /start\s*=\s*(\d{4})y(\d{1,3})d(\d{1,2})h(\d{1,2})m(\d{1,2})s;/)
			{
				$vexScans[$scanCount]{"YEAR"} = $1;
				$vexScans[$scanCount]{"DAY"} = $2;
				$vexScans[$scanCount]{"HOUR"} = $3;
				$vexScans[$scanCount]{"MINUTE"} = $4;
				$vexScans[$scanCount]{"SECOND"} = $5;
			}	
			# extract mode (if present)
			elsif ($vexLine =~ /mode\s*=\s*(.*?);/)
			{
				$vexScans[$scanCount]{"MODE"} = $1;
				if (length($1) > $maxModeName)
                                {
                                        $maxModeName = length($1)
                                }

				#print "$1\n";
			}
			# extract source name (if present)
			elsif ($vexLine =~ /source\s*=\s*(.*);/)
			{
				$vexScans[$scanCount]{"SOURCE"} = $1;
				if (length($1) > $maxSourceName)
				{
					$maxSourceName = length($1)
				}
			}
			# station statement in scan block
			elsif ($vexLine =~ /^station\s*=\s*(\w+)\s*:\s*(\d+)\s+sec\s*:\s*(\d+)\s+sec/)
			{
				my $station = uc($1);
				$vexScans[$scanCount]{"STATION_OFFSET"}{$station} = $2;
				$vexScans[$scanCount]{"STATION_DURATION"}{$station} = $3;

				# remeber longest duration that occurs in this scan
				if ($3 > $vexScans[$scanCount]{"MAX_DURATION"})
				{
					$vexScans[$scanCount]{"MAX_DURATION"} = $3;
				}
				# print "$station $2 $3\n";

			}

		}

	}
}


###################################
#
# compare
#
###################################
sub compare
{
	my $scan = "";
	my $vexStart = 0;
	my $vexStop = 0;
	my %stationSums = ();
	my $station = "";
	my $time = "";
	my $value = "";


	print"$maxScanName $maxSourceName $maxModeName\n";
	my $headerLen = length($vexScanCount) + $maxScanName + $maxSourceName + $maxModeName + 4;
	my $headerBlank = "";
	for ($i=0; $i < $headerLen; $i++)
	{
		$headerBlank .= " ";
	}

	print FILOUT $headerBlank;
	print $headerBlank;

	foreach $station (@Stations)
	{
		print FILOUT "$station ";
		print "$station ";
	}

	print FILOUT "\n";
	print "\n";

	# loop over all vex scans
	for $i ( 0 .. $#vexScans -1 )
	{

		# check if this scan has the selected mode, skip otherwise
		if ($mode ne "")
		{
			if ($vexScans[$i]{'MODE'} ne $mode)
			{
				next;
			}
		}

		#if ($vexScans[$i]{'NAME'} ne "No0176")
		#{
		#	next;
		#}

		# convert the vex time to time in seconds
		$vexStart = &vexTime2Seconds($vexScans[$i]{"YEAR"}, $vexScans[$i]{"DAY"},  $vexScans[$i]{"HOUR"},  $vexScans[$i]{"MINUTE"},  $vexScans[$i]{"SECOND"});

		$vexStop = $vexStart + $vexScans[$i]{"MAX_DURATION"};

		#print "$vexScans[$i]{'NAME'} $vexScans[$i]{'MODE'} $vexScans[$i]{'SOURCE'} $vexScans[$i]{'MODE'} $vexStart $vexStop\n" ;
		%stationSums = &parseJobmatrix ( $vexStart, $vexStop);

		# matrix output
		my $format = "%" . length($vexScanCount) . "s %" . $maxScanName . "s %" . $maxSourceName . "s %" . $maxModeName . "s " ;
		printf FILOUT  $format, $i+1, $vexScans[$i]{'NAME'}, $vexScans[$i]{'SOURCE'}, $vexScans[$i]{'MODE'} ;
		printf $format, $i+1, $vexScans[$i]{'NAME'}, $vexScans[$i]{'SOURCE'}, $vexScans[$i]{'MODE'} ;

		# loop over all stations
		foreach $station (@Stations)
		{
			#check if this station takes part in this vex scan
			if (exists $vexScans[$i]{"STATION_DURATION"}{$station})
			{
				my $targetTime = $vexScans[$i]{"STATION_DURATION"}{$station};

				# now check if this station was in the jobmatrix
				if (exists $stationSums{$station} )
				{
					#print "$key: $value $stationSum{$key}";
					if ($targetTime > $stationSums{$station})
					{
					    #print "Station $station should have $vexScans[$i]{'STATION_DURATION'}{$station} sec. Has  $stationSums{$station} sec\n";
						my $percentage = sprintf ("%#.2d", $stationSums{$station} / $targetTime * 100);
					    print FILOUT "$percentage ";
					    print color("red"), "$percentage ";
					}
					else
					{
						print FILOUT "o  ";
						print color("green"), "o  ";
					}
				}
				else
				{
					print FILOUT "x  ";
					print color("red"), "x  ";
					#print "$VexScan Station $key not found\n";
				}


			}
			else
			{
				print FILOUT ".  ";
				print "   ";
			}
		}
		print FILOUT "\n";
		print color("black"), "\n";
		#print " $value";
	}
}


###########################
#
# vexTime2Seconds
#
###########################
#
# Converts the vex time (year, doy, hour, minute, seconds)
# to time in seconds since 1990
#
###########################

sub vexTime2Seconds
{
	my $seconds = 0;

	$seconds = timegm($_[4], $_[3],$_[2], 1, 0, $_[0]);
	$seconds += ( 86400.0 * ($_[1] -1.0));

	#print "vextime convert: $_[4], $_[3],$_[2], 1, 0, $_[0] $_[1] => $seconds\n";

	return ($seconds);

}

###########################
#
# jobmatrixTime2Seconds
#
###########################
#
# Converts the time (year, month, day, hour, minute, seconds)
# found in the jobmatrix file 
# to time in seconds since 1990
#
###########################
sub jobmatrixTime2Seconds
{

	#print "year: $_[0] month: $_[1] day: $_[2] hour: $_[3] min: $_[4] sec: $_[5]\n";
	my $seconds = 0;	
	my $month = 0;
	my  %monthIndex = ( JAN=>0, FEB=>1, MAR=>2, APR=> 3, MAY=> 4, JUN=> 5,
				 JUL=>6, AUG=>7, SEP=>8, OCT=>9, NOV=>10, DEC=>11 );

	# convert text representation of month to number
	if (exists $monthIndex{$_[1]})
	{
		$month = $monthIndex{$_[1]};
	}
	else
	{
		die "Cannot parse jobmatrix date: $_[1]";
	}
		
	$seconds = timegm($_[5], $_[4],$_[3], $_[2], $month, $_[0]);

	return($seconds);
}


######################
#
# parseJobmatrix
#
######################
sub parseJobmatrix
{
	my ($vexStart, $vexStop ) = @_;

	my $line = "";
	my $year = 0;
	my $month = "";
	my $day = 0;
	my $seconds = 0;
    	my %stationSum = ();
    	my $scanOpenFlag = 0;

    	foreach $line (@joblist)                       
        {
        	chomp($line);                                
		my @stations = ();

		if  ($line  =~	/(\d{4})(\w{3})(\d{1,2})\s+(\d{1,2})h(\d{1,2})m(\d{1,2})\.\d{2}s/)
		{
 	    		#print "new day: $1 $2 $3 $4 $5 $6";    

			# remember the date until the next entry is found
			$year = $1;
			$month = $2;
			$day = $3;
	
	    
			# convert calendar date to seconds
			$seconds = &jobmatrixTime2Seconds ($1, $2, $3, $4, $5, $6);

			#print "time convert: $1 $2 $3 $4 $5 $6 => $seconds\n";

			# extract the station participating in this time interval
			@stations = &readStations ($line);

		}
		elsif ($line =~ /\s+(\d{1,2})h(\d{1,2})m(\d{1,2})\.\d{2}s/)
		{
			$seconds = &jobmatrixTime2Seconds ($year, $month, $day, $1, $2, $3);


			#print "time: $1 $2 $3 ";
			@stations = &readStations ($line);
			#print "$seconds\n";

		}
	
		#print "Compare: $seconds  $vexStart  $vexStop \n";
		
		# check if jobmatrix time is in the vex scan time interval
		if ($seconds >=  ($vexStart - 20) &&   $seconds <  $vexStop )
		{ 


			$scanOpenFlag = 1;
	 		#print "In scan; $seconds  $vexStart  $vexStop $line\n";

			# Stations
			my $stationNum = 0;
			my $station = "";
			foreach $station (@stations)
			{
				if ($station ne "  ")
				{
					my $stationName = $MatrixStationen[$stationNum];		
					#print "$stationName $station\n";
					$stationSum{$stationName} += 20;
				}

				#print "SUM :" . $stationSum{$station} ."\n";
				$stationNum++;
			}

		}
		else
		{
			# if start time of jobmatrix is larger than the vex scan time
			if ($seconds > $vexStart)
			{
				return (%stationSum);
			}
			# this must be the end of the scan block
			if ($scanOpenFlag)
			{
				return (%stationSum);
			}
			
			next;
		}
	}

	return(%stationSum);
}

sub printMatrix
{
                                return;

}
sub readStations
{ 
    my $inputLine = $_[0];
    my $stationStr = "";
    my $station = "";
    my $stationCount = 0;
    my @stationFlags = ();

    # Stationen auswerten
    foreach $station (@MatrixStationen)
    {
	$stationStr = substr($inputLine, $stationCount*3, 2);
	push ( @stationFlags,  $stationStr);
        $stationCount++;
    }
    
    return (@stationFlags);
}


#####################
#
# printUsage 
#
#####################

sub printUsage 
    {
    print "---------------------------------------------------------------------------- \n";    
    print "PURPOSE\n";
    print "---------------------------------------------------------------------------- \n";    
    print "Script to compare the contents of a FITS-file created by vex2difx\n";
    print "to what has been specified in the vexfile.\n";
    print "\n";
    print "---------------------------------------------------------------------------- \n";    
    print "USAGE\n";
    print "---------------------------------------------------------------------------- \n";    
    print " pcList.pl -v vexfile -j jobmatrixfile [-m mode]\n";    
    print "\n";    
    print "if option -m is used only scans having the selected mode will be processed.\n";    
    print "\n";    
    print "\n";    
    print "---------------------------------------------------------------------------- \n";    
    print "OUTPUT\n";
    print "---------------------------------------------------------------------------- \n";    
    print " Output-File :   vexfilename.pclist\n";    
    print "\n";    
    print "Legend:\n";    
    print "o:		station is included in the FITS-file (data is complete)\n";    
    print "x:		expected station is missing in the FITS-file\n";    
    print "number:		percentage of job time in the FITS-file compared to expected time.\n";    
    print "\n";    

    exit;
    }
