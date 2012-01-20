#! /usr/bin/python

#===========================================================================
# SVN properties (DO NOT CHANGE)
#
# $Id$
# $HeadURL$
# $LastChangedRevision$
# $Author$
# $LastChangedDate$
#
#============================================================================

import os
import sys
from difxdb.difxdbconfig import DifxDbConfig
from difxdb.model.dbConnection import Schema, Connection
from difxdb.business.experimentaction import *
from difxdb.business.moduleaction import *

from difxdb.model import model
from operator import  attrgetter
from optparse import OptionParser


__author__="Helge Rottmann <rottmann@mpifr-bonn.mpg.de>"
__prog__ = os.path.basename(__file__)
__build__= "$Revision$"
__date__ ="$Date$"
__lastAuthor__="$Author$"

def getUsage():

	usage = "%prog [options] [<experiment1> [<experiment2>] ...]\n\n"
	usage += '\nA program to list all releasable modules.'
	usage += '\nOptionally one or more experiment codes can be given in order'
        usage += '\nto limit output to modules associated with these experiment(s).'
        usage += '\nFor possibilties to further filter the results please consult the options below.\n\n'
        usage += 'NOTE: The program requires the DIFXROOT environment to be defined.\n'
        usage += "The program reads the database configuration from difxdb.ini located under $DIFXROOT/conf.\n"
        usage += "If the configuration is not found a sample one will be created for you at this location.\n"
        return usage
    

if __name__ == "__main__":
    
    usage = getUsage()
    version = "%s\nSVN  %s\nOriginal author: %s\nLast changes by: %s\nLast changes on: %s" % (__prog__, __build__, __author__, __lastAuthor__, __date__)
    #usage = "usage: %prog [options] arg1 arg2"

    parser = OptionParser(version=version, usage=usage)
    parser.add_option("-s", "--slot", dest="slot", default="", 
                  help="show only modules that are located in slots matching the given expression")
    parser.add_option("-e", "--extended", action="store_true", help="print extended information")
   
    (options, args) = parser.parse_args()
    
    
    try:
        if (os.getenv("DIFXROOT") == None):
            sys.exit("Error: DIFXROOT environment must be defined.")

        configPath = os.getenv("DIFXROOT") + "/conf/difxdb.ini"


        config = DifxDbConfig(configPath, create=True)

        # try to open the database connection
        connection = Connection()
        connection.type = config.get("Database", "type")
        connection.server = config.get("Database", "server")
        connection.port = config.get("Database", "port")
        connection.user = config.get("Database", "user")
        connection.password = config.get("Database", "password")
        connection.database = config.get("Database", "database")
        connection.echo = False

        dbConn = Schema(connection)
        session = dbConn.session()
        
        experiments = []
        
        if (len(args) == 0):
            experiments = getExperiments(session)
        else:
            for code in args:
                try:
                    experiment = getExperimentByCode(session, code)
                except:
                    print "Unknown experiment %s" % code
                    continue
                    
                experiments.append(experiment)
        
        totalCapacity = 0
        moduleCount = 0
        
        # loop over all experiments
        for experiment in experiments:
            
            sortedModules = sorted(experiment.modules, key=attrgetter('slot.location'))
            
            # skip experiment if it contains no modules
            if (len(sortedModules) == 0):
                continue
            
            # skip experiment if it is not released
            if (not isExperimentReleased(session, experiment.code)):
                continue
            
                        
            printHeader = 0
            tempCapacity = 0
            
            # loop over all modules of this experiment
            for module in  experiment.modules:
                # check for slot filter
                if (options.slot != ""):
                    if (not module.slot.location.startswith(options.slot)):
                        continue
                
                if printHeader == 0 and options.extended == True:
                    print "\n------"
                    print experiment.code
                    print "------"
                    printHeader = 1
                    
                # check if this module is releasable
                if (isCheckOutAllowed(session, module.vsn)):
                    print "%4s %8s %4s %5s %5s" % (module.slot.location, module.vsn, module.stationCode, module.datarate, module.capacity)

                    tempCapacity += module.capacity
                    totalCapacity += module.capacity
                    moduleCount += 1
                elif options.extended == True:
                    print "%s (%s) contains unreleased experiments" % (module.vsn, module.slot.location)
            
            if (tempCapacity > 0 and options.extended == True):
                print "Summed capacity for %s: %d" % (experiment.code, tempCapacity)
     
        if (moduleCount == 0):
            print "No releasable modules found matching the filter criteria.\n"
            sys.exit(0)
        print "\n-------"
        print "Summary"
        print "-------"
        print "Number of modules: %d" % (moduleCount)
        print "Total capacity: %d" % (totalCapacity)
        sys.exit(1)
	
    
    except Exception as e:
       
        sys.exit(e)
    
   
    
