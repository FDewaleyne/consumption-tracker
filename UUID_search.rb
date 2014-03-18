#!/usr/bin/env ruby
#concept script to search the UUID of a system in the lab
#testing only with satellite 5.6

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

#tag the vm with that system id tag here


#tag the vm with all the channels used



# cleanup  #
@client.call('auth.logout', @key)
#return MIQ_SUCCESS

