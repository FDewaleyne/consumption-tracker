#
#            Automate Method
#
$evm.log("info", "Tagging all systems of one cluster - automation started")
#
#            This script goes through the list of systems on the satellite and on the cluster selected, refreshing entirely the tag of the systems that are matching a system in satellite.
#

# initialization
@UUID = "6fd52f34d57b4f808fa13474514ffe51"
@SAT_URL = "http://rhns56-6.gsslab.fab.redhat.com/rpc/api"
@SAT_LOGIN = "orgadmin"
@SAT_PWD = "redhat"

#connect
require "xmlrpc/client"
@client = XMLRPC::Client.new2(@SAT_URL)
@key = @client.call('auth.login', @SAT_LOGIN, @SAT_PWD)

#fetch the list of all systems on the satellite
satsystems = @client.call('system.listSystems',@key)
#collect the count for the number of uuids, along with which is the oldest
uuidcollection = Hash.new
#update the list of systems to include the UUID for each system
satsystems.each do |satsystem| 
	satsystem.uuid = @client.call('system.getUUID',@key,satsystem.id)
	if uuidcollection.has_key?(satsystem.uuid) then
		#we have a duplicate, increase count by one
		uuidcollection[system.uuid].counter += 1
		#schedule a hardware refresh so that the next call to any tagger is accurate
		@client.call('system.scheduleHardwareRefresh',@key, system['id'], Date.today)
		if uuidcollection[system.uuid].last_checkin.to_date < satsystem.last_checkin.to_date then
			#then the uuid for the system stored is older and is a duplicate
			uuidcollection[system.uuid].systemid = satsystem.id
			uuidcollection[system.uuid].last_checkin = satsystem.last_checkin
		end
	else
		#new entry!
		uuidcollection[system.uuid] = { "count" => 0, "systemid" => satsystem.id, "last_checkin" => satsystem.last_checkin }
	end
end
# now go through the list of systems in the cluster
# for each vm remove any satellite tag
# for each vm that matches add the satellite tags, otherwise tag as unregistered


#
#
#
$evm.log("info", "Tagging all systems of one cluster - automation finished")
exit MIQ_OK
