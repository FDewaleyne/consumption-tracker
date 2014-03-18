#!/usr/bin/env ruby
#concept script to search the UUID of a system in the lab
#testing only with satellite 5.6

#rememeber : this should be done if there is no subscribed tag. 

# Values in CF #
#UUID = $evm.root['UUID']
#SAT_URL = $evm.root['SAT_URL']
#SAT_LOGIN = $evm.root['SAT_LOG']
#SAT_PWD = $evm.root['SAT_PWD']

# test values
@UUID = "6fd52f34d57b4f808fa13474514ffe51"
@SAT_URL = "http://rhns56-6.gsslab.fab.redhat.com/rpc/api"
@SAT_LOGIN = "satadmin"
@SAT_PWD = "redhat"

# init part #
require "xmlrpc/client"
@client = XMLRPC::Client.new2(@SAT_URL)
@key = @client.call('auth.login', @SAT_LOGIN, @SAT_PWD)

# lookup for UUID #
systems = @client.call('system.search.uuid',@key,@UUID)

if systems.size > 1 then
	# select the last checked in profile
	# also tag the system as over consuming entitlements since it is over-consuming management by having multiple profiles
	last_system = nil
	require "date"
	systems.each do |system|
		# queue in a hardware refresh in the satellite to help clean the profile and identify profiles in use in different systems
		@client.call('system.scheduleHardwareRefresh',@key, system['id'], Date.today)
		if last_system == nil then
			last_system = system
		elsif last_system['last_checkin'].to_date < system['last_checkin'].to_date then
			#the other system is more recent
			last_system = system
		else
			#the date in the object is more recent than that of the others
			next;
		end
	end
end

# tag the vm with that system id tag here
# this code shouldn't be run on systems that already have a system ID ; if they already have it, then another script looking up the info and checking it is accurate should be used
#tag the vm with all the channels used
data = @client.call('system.getDetails',@key,last_system['id'])
data['addon_entitlements'].each do |addon|
	#tag with tle entitlement
	#debug
	puts addon
end
base_channel = @client.call('system.getSubscribedBaseChannel',@key,last_system['id'])
#tag with base_channel['label'] part
puts base_channel['label']
child_channels = @client.call('system.listSubscribedChildChannels',@key,last_system['id'])
child_channels.each do |channel|
	#tag with channel['label']
	puts channel['label']
end

# cleanup  #
@client.call('auth.logout', @key)
#return MIQ_SUCCESS

