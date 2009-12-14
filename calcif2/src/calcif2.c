#include <stdio.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <fcntl.h>
#include <rpc/rpc.h>
#include <glob.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include "config.h"
#include "difxcalc.h"
#include "CALCServer.h"

#define MAX_FILES	2048

const char program[] = "calcif2";
const char author[]  = "Walter Brisken <wbrisken@nrao.edu>";
const char version[] = "2.0";
const char verdate[] = "20091214";

typedef struct
{
	int verbose;
	int force;
	int doall;
	double delta;	/* derivative step size, radians. <0 for noaber */
	char calcServer[32];
	int calcProgram;
	int calcVersion;
	int nFile;
	int polyOrder;
	int polyInterval;	/* (sec) */
	int allowNegDelay;
	char *files[MAX_FILES];
	int overrideVersion;
} CommandLineOptions;

int usage()
{
	fprintf(stderr, "%s ver. %s  %s  %s\n\n", program, version, 
		author, verdate);
	fprintf(stderr, "A program to calculate a model for DiFX using a calc "
		"server.\n\n");
	fprintf(stderr, "Usage : %s [options] { <calc file> | -a }\n\n", 
		program);
	fprintf(stderr, "<calc file> should be a '.calc' file as generated by "
		"job2difx.\n\n");
	fprintf(stderr, "options can include:\n");
	fprintf(stderr, "  --help\n");
	fprintf(stderr, "  -h                      Print this help and quit\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --verbose\n");
	fprintf(stderr, "  -v                      Be more verbose in operation\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --quiet\n");
	fprintf(stderr, "  -q                      Be less verbose in operation\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --force\n");
	fprintf(stderr, "  -f                      Force recalc\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --noaber\n");
	fprintf(stderr, "  -n                      Don't do aberration, etc, corrections\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --all\n");
	fprintf(stderr, "  -a                      Do all calc files found\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --allow-neg-delay\n");
	fprintf(stderr, "  -z                      Don't zero negative delays\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --order <n>\n");
	fprintf(stderr, "  -o      <n>             Use <n>th order polynomial [5]\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --interval <int>\n");
	fprintf(stderr, "  -i         <int>        New delay poly every <int> sec. [120]\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --override-version      Ignore difx versions\n");
	fprintf(stderr, "\n");
	fprintf(stderr, "  --server <servername>\n");
	fprintf(stderr, "  -s       <servername>   Use <servername> as calcserver\n\n");
	fprintf(stderr, "      By default 'localhost' will be the calcserver.  An "
		"environment\n");
	fprintf(stderr, "      variable CALC_SERVER can be used to override that.  The "
		"command line\n");
	fprintf(stderr, "      overrides all.\n");
	fprintf(stderr, "\n");
	return 0;
}

void deleteCommandLineOptions(CommandLineOptions *opts)
{
	int i;

	if(!opts)
	{
		return;
	}

	for(i = 0; i < opts->nFile; i++)
	{
		free(opts->files[i]);
	}

	free(opts);
}

CommandLineOptions *newCommandLineOptions(int argc, char **argv)
{
	CommandLineOptions *opts;
	glob_t globbuf;
	int i;
	char *cs;
	int die = 0;

	opts = (CommandLineOptions *)calloc(1, sizeof(CommandLineOptions));
	opts->delta = 0.0001;
	opts->polyOrder = 5;
	opts->polyInterval = 120;

	for(i = 1; i < argc; i++)
	{
		if(argv[i][0] == '-')
		{
			if(strcmp(argv[i], "-v") == 0 ||
			   strcmp(argv[i], "--verbose") == 0)
			{
				opts->verbose++;
			}
			else if(strcmp(argv[i], "-q") == 0 ||
			   strcmp(argv[i], "--quiet") == 0)
			{
				opts->verbose--;
			}
			else if(strcmp(argv[i], "-f") == 0 ||
				strcmp(argv[i], "--force") == 0)
			{
				opts->force++;
			}
			else if(strcmp(argv[i], "-a") == 0 ||
			        strcmp(argv[i], "--all") == 0)
			{
				opts->doall = 1;
			}
			else if(strcmp(argv[i], "-z") == 0 ||
			        strcmp(argv[i], "--allow-neg-delay") == 0)
			{
				opts->allowNegDelay = 1;
			}
			else if(strcmp(argv[i], "-n") == 0 ||
				strcmp(argv[i], "--noaber") == 0)
			{
				opts->delta = -1.0;
			}
			else if(strcmp(argv[i], "-h") == 0 ||
				strcmp(argv[i], "--help") == 0)
			{
				usage();
				deleteCommandLineOptions(opts);
				return 0;
			}
			else if(strcmp(argv[i], "--override-version") == 0)
			{
				opts->overrideVersion = 1;
			}
			else if(i+1 < argc)
			{
				if(strcmp(argv[i], "--server") == 0 ||
				   strcmp(argv[i], "-s") == 0)
				{
					i++;
					strncpy(opts->calcServer, argv[i], 31);
					opts->calcServer[31] = 0;
				}
				else if(strcmp(argv[i], "--order") == 0 ||
					strcmp(argv[i], "-o") == 0)
				{
					i++;
					opts->polyOrder = atoi(argv[i]);
				}
				else if(strcmp(argv[i], "--interval") == 0 ||
					strcmp(argv[i], "-i") == 0)
				{
					i++;
					opts->polyInterval = atoi(argv[i]);
				}
				else if(argv[i][0] == '-')
				{
					printf("Error: Illegal option : %s\n", 
						argv[i]);
					die++;
				}
			}
			else if(argv[i][0] == '-')
			{
				printf("Error: Illegal option : %s\n", argv[i]);
				die++;
			}
		}
		else
		{
			opts->files[opts->nFile] = strdup(argv[i]);
			opts->nFile++;
			if(opts->nFile >= MAX_FILES)
			{
				fprintf(stderr, "Error: Too many files (%d max)\n", 
					MAX_FILES);
				die++;
			}
		}
	}

	if(opts->doall == 0 && opts->nFile == 0 && !die)
	{
		fprintf(stderr, "Error: No input files!\n");
		die++;
	}

	if(opts->polyOrder < 2 || opts->polyOrder > 5)
	{
		fprintf(stderr, "Error: Order must be in range [2, 5]\n");
		die++;
	}

	if(opts->polyInterval < 10 || opts->polyInterval > 600)
	{
		fprintf(stderr, "Error: Interval must be in range [10, 600] sec\n");
		die++;
	}

	if(opts->nFile > 0 && opts->doall)
	{
		fprintf(stderr, "--all and files!\n");
		die++;
	}
	else if(opts->doall > 0)
	{
		glob("*.calc", 0, 0, &globbuf);
		opts->nFile = globbuf.gl_pathc;
		if(opts->nFile >= MAX_FILES)
		{
			fprintf(stderr, "Error: Too many files (%d max)\n", MAX_FILES);
			die++;
		}
		else if(opts->nFile <= 0)
		{
			fprintf(stderr, "Error: No .calc files found.  ");
			fprintf(stderr, "Hint: Did you run job2difx yet???\n");
			die++;
		}
		for(i = 0; i < opts->nFile; i++)
		{
			opts->files[i] = strdup(globbuf.gl_pathv[i]);
		}
		globfree(&globbuf);
	}

	if(opts->calcServer[0] == 0)
	{
		cs = getenv("CALC_SERVER");
		if(cs)
		{
			strncpy(opts->calcServer, cs, 31);
			opts->calcServer[31] = 0;
		}
		else
		{
			strcpy(opts->calcServer, "localhost");
		}
	}

	opts->calcVersion = CALCVERS;
	opts->calcProgram = CALCPROG;

	if(die)
	{
		if(die > 1)
		{
			fprintf(stderr, "Quitting. (%d errors)\n", die);
		}
		else
		{
			fprintf(stderr, "Quitting.\n");
		}
		fprintf(stderr, "Use -h option for help.\n");
		deleteCommandLineOptions(opts);
		return 0;
	}

	return opts;
}

/* return 1 if f2 exists and is older than f1 */
int skipFile(const char *f1, const char *f2)
{
	struct stat s1, s2;
	int r1, r2;

	r2 = stat(f2, &s2);
	if(r2 != 0)
	{
		return 0;
	}
	r1 = stat(f1, &s1);
	if(r1 != 0)
	{
		return 0;
	}

	if(s2.st_mtime > s1.st_mtime)
	{
		return 1;
	}

	return 0;
}

int runfile(const char *prefix, const CommandLineOptions *opts,
	CalcParams *p)
{
	DifxInput *D;
	int v;
	char imfile[256];
	char calcfile[256];
	const char *difxVersion;

	sprintf(imfile,    "%s.im",    prefix);
	sprintf(calcfile,  "%s.calc",  prefix);

	difxVersion = getenv("DIFX_VERSION");

	if(opts->force == 0 &&
	   skipFile(calcfile, imfile))
	{
		printf("skipping %s due to file ages\n", prefix);
		return 0;
	}

	D = loadDifxCalc(prefix);
	D = updateDifxInput(D);
        printf("Finished updating difxinput\n");
	
	if(D)
	{
		if(difxVersion && D->job->difxVersion[0])
		{
			if(strncmp(difxVersion, D->job->difxVersion, 63))
			{
				printf("Attempting to run calcif2 from version %s on a job make for version %s\n", difxVersion, D->job->difxVersion);
				if(opts->overrideVersion)
				{
					fprintf(stderr, "Continuing because of --override-version\n");
				}
				else
				{
					fprintf(stderr, "Won't run without --override-version.\n");
					deleteDifxInput(D);
					return -1;
				}
			}
		}
		else if(!D->job->difxVersion[0])
		{
			printf("Warning -- working on unversioned job\n");
		}

		strncpy(D->job->calcServer, opts->calcServer, 31);
		D->job->calcServer[31] = 0;
		D->job->calcProgram = opts->calcProgram;
		D->job->calcVersion = opts->calcVersion;

		if(opts->verbose > 1)
		{
			printDifxInput(D);
		}

		v = difxCalcInit(D, p);
		if(v < 0)
		{
			deleteDifxInput(D);
			fprintf(stderr, "difxCalcInit returned %d\n", v);
			return -1;
		}
		v = difxCalc(D, p);
		if(v < 0)
		{
			deleteDifxInput(D);
			fprintf(stderr, "difxCalc returned %d\n", v);
			return -1;
		}
		printf("About to write IM file\n");
		writeDifxIM(D,    imfile);
		printf("Wrote IM file\n");
		deleteDifxInput(D);

		return 0;
	}
	else
	{
		return -1;
	}
}

void deleteCalcParams(CalcParams *p)
{
	free(p);
}

CalcParams *newCalcParams(const CommandLineOptions *opts)
{
	CalcParams *p;

	p = (CalcParams *)calloc(1, sizeof(CalcParams));

	p->increment = opts->polyInterval;
	p->order = opts->polyOrder;
	p->delta = opts->delta;

	strncpy(p->calcServer, opts->calcServer, 31);
	p->calcServer[31] = 0;
	p->calcProgram = opts->calcProgram;
	p->calcVersion = opts->calcVersion;
	p->allowNegDelay = opts->allowNegDelay;

	p->clnt = clnt_create(p->calcServer, p->calcProgram, p->calcVersion, 
		"tcp");
	if(!p->clnt)
	{
		clnt_pcreateerror(p->calcServer);
		printf("ERROR: rpc clnt_create fails for host : %-s\n",
			p->calcServer);
		deleteCalcParams(p);
		return 0;
	}
	if(opts->verbose > 1)
	{
		printf("RPC client created\n");
	}

	return p;
}

int run(const CommandLineOptions *opts)
{
	CalcParams *p;
	int i, l;

	if(getenv("DIFX_GROUP_ID"))
	{
		umask(2);
	}

	if(opts == 0)
	{
		return -1;
	}
		
	p = newCalcParams(opts);
	if(!p)
	{
		fprintf(stderr, "Cannot initialize CalcParams\n");
		return -1;
	}

	for(i = 0; i < opts->nFile; i++)
	{
		l = strlen(opts->files[i]);
		if(l > 6)
		{
			if(strcmp(opts->files[i]+l-6, ".input") == 0)
			{
				opts->files[i][l-6] = 0;
			}
			else if(strcmp(opts->files[i]+l-5, ".calc") == 0)
			{
				opts->files[i][l-5] = 0;
			}
		}
		if(opts->verbose >= 0)
		{
			printf("Processing file %d/%d = %s\n",
				i+1, opts->nFile, opts->files[i]);
		}
		runfile(opts->files[i], opts, p);
	}
	deleteCalcParams(p);

	return 0;
}

int main(int argc, char **argv)
{
	CommandLineOptions *opts;

	opts = newCommandLineOptions(argc, argv);

	run(opts);

	deleteCommandLineOptions(opts);

	return 0;
}
