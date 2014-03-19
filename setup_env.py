#!/usr/bin/python
# this script is aimed at creating the elements in cloudforms required to connect to the satellite and populate the tags.
# this content can probably be split into multiple libraries at a later time.
# requires at least python 2.6

__author__ = "Felix Dewaleyne"
__credits__ = ["Felix Dewaleyne"]
__license__ = "GPL v2"
__version__ = "0.1"
__maintainer__ = "Felix Dewaleyne"
__email__ = "fdewaley@redhat.com"
__status__ = "beta"

import sys, re

def sat_connect(options):
    """connects to the satellite,uses a dictionary to handle options"""
    import xmlrpc
    SAT_URL = options.get("url",None)
    SAT_USER = options.get("user",None)
    SAT_PWD = options.get("password",None)
    if SAT_URL == None :
        sys.stderr.write("Url of the Satellite API (or hostname):")
        SAT_URL = raw_input().strip()
    if re.match('^http(s)?://[\w\-.]+/rpc/api',SAT_URL) == None:
        #this isn't the url of the api, treat that as a hostname or a partial url
        if re.search('^http(s)?://', SAT_URL) == None:
            SAT_URL = "https://"+SAT_URL
        if re.search('/rpc/api$', SAT_URL) == None:
            SAT_URL = SAT_URL+"/rpc/api"
    if SAT_USER == None:
        sys.stderr.write("Satadmin Login:")
        SAT_USER = raw_input().strip()
    if SAT_PWD == None:
        import getpass
        SAT_PWD = getpass.getpass(prompt="Password: ")
        sys.stderr.write("\n")
    client = xmlrpc.Server(URL)
    key = client.auth.login(SAT_USER,SAT_PWD)
    del SAT_PWD
    print "connected to %s using %s" % (SAT_URL, SAT_USER)
    return (client,key)

def cf_connect(options):
    """connects to the cloudform instsance, uses a dictionary to handle options"""
    # read https://fedorahosted.org/suds/wiki/Documentation to continue
    from suds.client import Client
    from suds.transport.http import HttpAuthenticated
    CF_WSDL = options.get("wsdl",None)
    CF_USER = options.get("user",None)
    if CF_WSDL == None :
        sys.stderr.write("Url of Cloudforms WSDL file (or hostname):")
        CF_WSDL = raw_input().strip()
    if re.match('^http(s)?://[\w\-.]+/rpc/api',CF_WSDL) == None:
        #this isn't the url of the api, treat that as a hostname or a partial url
        #TODO: fix this depending on the URL
        if re.search('^http(s)?://', CF_WSDL) == None:
            CF_WSDL = "https://"+CF_WSDL
        if re.search('/rpc/api$', CF_WSDL) == None:
            CF_WSDL = CF_WSDL+"/rpc/api"
    if SAT_USER == None:
        sys.stderr.write("Satadmin Login:")
        SAT_USER = raw_input().strip()
    if SAT_PWD == None:
        import getpass
        SAT_PWD = getpass.getpass(prompt="Password: ")
        sys.stderr.write("\n")
   CF_PWD = options.get("pwd",None)

    #connect
    t = HttpAuthenticated(username=CF_USER,password=CF_PWD)
    client = Client(CF_WSDL, transport=t)
    return client
    
# step 1 : create one script user per org

# step 2 : create the instances to add to cloudforms

# step 3 : run for each instance the tag population ruby script (if I do that here, I might take forever doing the api)

main function
def main(version):
    """main function"""
    global verbose;
    import optparse
    parser = optparse.OptionParser("%prog action_option [connection_options] [global_options]\n    creates users on the satellite or reuses them, then populates cloudforms with all the instances required to connect to the organizations of the satellite and create all the tags.", version=version)
    # connection options
    connect_group = optparse.OptionGroup(parser, "Connection options","Not required unless you want to bypass the details of ~/.satellite, .satellite or /etc/sysconfig/rhn/satellite or simply don't want to be asked the settings at run time")
    connect_group.add_option("--url", dest="saturl", help="URL of the satellite api, e.g. https://satellite.example.com/rpc/api or http://127.0.0.1/rpc/api ; can also be just the hostname or ip of the satellite. Facultative.")
    connect_group.add_option("--username", dest="satuser", help="username to use with the satellite. Should be admin of the organization owning the channels. Faculative.")
    connect_group.add_option("--password", dest="satpwd", help="password of the user. Will be asked if not given and not in the configuration file.")
    connect_group.add_option("--orgname", dest="orgname", default="baseorg", help="the name of the organization to use as per your configuration file - defaults to baseorg")
    # action options
    action_group = optparse.OptionGroup(parser, "Action options", "use -c for each channel you wish to try in one run or no option to try all the configuration channels.")
    action_group.add_option("-l","--list",dest='list', action='store_true', default=False, help="List all the channels and quit")
    action_group.add_option("-c","--configchannel", dest='channellabels', action='append', help="Each call of this option indicates a configuration channel to use - identified by its label. If none is specified all will be used")
    action_group.add_option("--noosad", dest='noosad', action='store_true', default=False, help="Indicate that the osad check should be bypassed.\nWarning : machines without osad running can delay considerably the execution of the script")
    # global options
    global_group = optparse.OptionGroup(parser, "Global options", "Option that affect the display of information")
    global_group.add_option("-v", "--verbose",dest='verbose', action='store_true', default=False, help="Increase the verbosity of the script")
    global_group.add_option("-d", "--delay", dest='delay', default=5, type='int', help="Delay between each check on the execution of a systemid in minutes. defaults to 5")
    #integrate the groups
    parser.add_option_group(action_group)
    parser.add_option_group(connect_group)
    parser.add_option_group(global_group)
    (options, args) = parser.parse_args()
    verbose = options.verbose
    if options.list:
        conn = RHNSConnection(options.satuser,options.satpwd,options.saturl,options.orgname)
        print "%30s | %5s | %s" % ("Label","OrgID","Name")
        for configchannel in conn.client.configchannel.listGlobals(conn.key):
            print "%30s | %5s | %s" % (configchannel['label'],str(configchannel['orgId']),configchannel['name'])
        conn.client.auth.logout(conn.key)
    elif options.channellabels == None:
        #run agains all channel
        print "running against all channels - this can take a long time."
        conn = RHNSConnection(options.satuser,options.satpwd,options.saturl,options.orgname)
        for configchannel in conn.client.configchannel.listGlobals(conn.key):
            run_channel(conn,configchannel['label'],options.noosad,options.delay)
        conn.client.auth.logout(conn.key)
    else:
        #normal run against a set list of channels
        conn = RHNSConnection(options.satuser,options.satpwd,options.saturl,options.orgname)
        for channellabel in options.channellabels:
            if conn.client.configchannel.channelExists(conn.key,channellabel) == 1:
                run_channel(conn,channellabel,options.noosad,options.delay)
            else:
                sys.stderr.write("channel %s does not exist\n" % (channellabel))
        conn.client.auth.logout(conn.key)
    pass

#calls start here
if __name__=="__main__":
    main(__version__)
 
