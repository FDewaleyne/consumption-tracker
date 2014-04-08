#
#            Automate Method
#
$evm.log("info", "Tagging all systems of one cluster - automation started")
#
#            This script goes through the list of systems on the satellite and on the cluster selected, refreshing entirely the tag of the systems that are matching a system in satellite.
#

# Values in CF #
#SAT_URL = $evm.root['SAT_URL']
#SAT_LOGIN = $evm.root['SAT_LOG']

# initialization
@SAT_URL = $ems.root['url']
@SAT_LOGIN = $ems.root['username']
@SAT_PWD = $ems.root['password']
@SATORG = $ems.root['orgid']

#no need to do anything if the clust er is empty
cluster = $evms.root['ems_cluster']
if cluster.vms.nil? then
	ems.log("info","the cluster is empty, nothing to do")
	exit MIQ_OK
end

#making sure the categories required exist
if not $evm.execute('category_exists?','registration') then
	$evm.execute('category_create', :name => 'registration', :single_value => false, :description => 'Category holding the registration information for a machine')
	$evm.execute('tag_create', :name => 'unregistered', :description => 'indicates a system not registered with a registration system')
end
if not $evm.execute('category_exists?','channel') then
	$evm.execute('category_create',:name => 'channel', :single_value => false, :description => 'Category holding the channels systems are registered to')
end
if not $evm.execute('category_exists?','satellite5') then
	$evm.execute('category_create',:name => 'satellite5', :single_value => false, :description => 'Information relative to satellite 5 registration')
end

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
		#check if the uuid for that entry is newer than what we already have
		if uuidcollection[system.uuid]['last_checkin'].to_date < satsystem.last_checkin.to_date then
			#then the uuid for the system stored is older and is a duplicate
			uuidcollection[system.uuid]['systemid'] = satsystem.id
			uuidcollection[system.uuid]['last_checkin'] = satsystem.last_checkin
		end
	else
		#new entry!
		uuidcollection[system.uuid] = { "count" => 0, "systemid" => satsystem.id, "last_checkin" => satsystem.last_checkin }
	end
end
# now go through the list of systems in the cluster
cluster.vms.each do |vm|
	#TODO : tag removal of any registration and any channel tag - only if the system has an org tag of the org we are working on!
	# for each vm that matches add the satellite tags, otherwise tag as unregistered if the os has "red hat" in it
	if uuidcollection.has_key?(vm.attributes['uid_ems']) then
		#TODO : implement checks for systems that previously had the tag - those should be removed the registration tag and tagged as duplicate (futureversion)
		#TODO : investigate alternative to tagging like this that still allows to see systems sharing the same registration ID
		registration_tag = 'sat5-id-'+uuidcollection[vm.attributes['uid_ems']].to_s()
		if $evm.execute('tag_exists?', 'registration', registration_tag) then
			$emv.execute ('tag_create', "registration", :name => registration_tag, :description => "registrationtag for satellite 5")
		end
		vm.tag_assign('organization', registration_tag)
		# org_id info
		org_tag = 'org-'+@SATORG.to_s()
		if $evm.execute('tag_exists?', 'satellite5', org_tag) then
			orgdetails = @client.call('org.getDetails', @key, @SATORG)
			$emv.execute ('tag_create', "satellite5", :name => org_tag, :description => orgdetails['name'] )
		end
		vm.tag_assign('satellite5', org_tag)
		#base channel
		base = @client.call('system.getSubscribedBaseChannel',@key,uuidcollection[vm.attributes['uid_ems']])
		if $evm.execute('tag_exists?', 'channel', base['label']) then
			$emv.execute ('tag_create', "channel", :name => base['label'], :description => base['name'])
		end
		vm.tag_assign('channel', base['label'])
		#child channels
		childs = @client.call('system.listSubscribedChildChannels',@key,uuidcollection[vm.attributes['uid_ems']])
		childs.each do |channel|
			if $evm.execute('tag_exists?', 'channel', channel['label']) then
				$emv.execute ('tag_create', "channel", :name => channel['label'], :description => channel['name'])
			end
			vm.tag_assign('channel', channel['label'])
		end
		#entitlements
		entitlements = @client.call('system.getEntitlements', @key, uuidcollection[vm.attributes['uid_ems']])
		entitlements.each do |entitlement|
			if $evm.execute('tag_exists?', 'satellite5', entitlement) then
				$emv.execute ('tag_create', "satellite5", :name => entitlement, :description => entitlement)
			end
			vm.tag_assign('satellite5', entitlement)
		end
	elsif /Red Hat/i.match(vm.operating_system).nil? then
		#this is a red hat system that isn't registered on the satellite - tag is as unregistered
		vm.tag_assign('registration', 'unregistered')
	end
end

#
#
$evm.log("info", "Tagging all systems of one cluster - automation finished")
exit MIQ_OK
