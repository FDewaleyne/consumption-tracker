#
#            Automate Method
#
$evm.log("info", "Tagging all systems of one cluster - automation started")
#
#            This script goes through the list of systems on the satellite and on the cluster selected, refreshing entirely the tag of the systems that are matching a system in satellite.
#


# initialization
SAT_URL = $evm.object['url']
SAT_LOGIN = $evm.object['username']
SAT_PWD = $evm.object['password']
SATORG = $evm.object['orgid']

#no need to do anything if the clust er is empty
cluster = $evm.root['ems_cluster']
if cluster.vms.nil? then
	ems.log("info","the cluster is empty, nothing to do")
	exit MIQ_OK
end

#making sure the categories required exist
if not $evm.execute('category_exists?','registration') then
	$evm.execute('category_create', :name => 'registration', :single_value => false, :description => 'Category holding the registration information for a machine')
	$evm.execute('tag_create', 'registration', :name => 'unregistered', :description => 'indicates a system not registered with a registration system')
	$evm.execute('tag_create', 'registration', :name => 'duplicated', :description => 'indicates a system which has 2 profiles at least on the satellite')
end
if not $evm.execute('category_exists?','channel') then
	$evm.execute('category_create',:name => 'channel', :single_value => false, :description => 'Category holding the channels systems are registered to')
end
if not $evm.execute('category_exists?','satellite5') then
	$evm.execute('category_create',:name => 'satellite5', :single_value => false, :description => 'Information relative to satellite 5 registration')
end

#connect
require "xmlrpc/client"
#if connection fails, fail.
begin
	@client = XMLRPC::Client.new2(SAT_URL)
	@key = @client.call('auth.login', SAT_LOGIN, SAT_PWD)
rescue
	exit MIQ_ABORT
end
#if the call fails, retry later
begin
	#fetch the list of all systems on the satellite ; retry on error
	satsystems = @client.call('system.listSystems',@key)
rescue
	exit MIQ_STOP
end
#collect the count for the number of uuids, along with which is the oldest
uuidcollection = Hash.new
#update the list of systems to include the UUID for each system
satsystems.each do |satsystem| 
	#ignore objects with no uuid
	begin
		# remove any - when they are present for better comparisons
		uuid = @client.call('system.getUUID',@key,satsystem['id']).tr('-','')
	rescue
		next
	end
	if uuidcollection.has_key?(uuid) then
		#we have a duplicate, increase count by one
		uuidcollection[uuid]['count'] += 1
		#schedule a hardware refresh so that the next call to any tagger is accurate
		@client.call('system.scheduleHardwareRefresh',@key, satsystem['id'], Date.today)
		#check if the uuid for that entry is newer than what we already have
		if uuidcollection[uuid]['last_checkin'].to_date < satsystem['last_checkin'].to_date then
			#then the uuid for the system stored is older and is a duplicate
			uuidcollection[uuid]['systemid'] = satsystem['id']
			uuidcollection[uuid]['last_checkin'] = satsystem['last_checkin']
		end
	else
		#new entry!
		uuidcollection[uuid] = { "count" => 1, "systemid" => satsystem['id'], "last_checkin" => satsystem['last_checkin'] }
	end
end
# now go through the list of systems in the cluster
cluster.vms.each do |vm|
	#TODO v2 : add here a condition to stop if a tag from another registration system is present.
	#remove registration and satellite 5 tags
	#we want to remove channels, any active registration tag that is sat5, unregistered or duplicated
	vm.tags.keep_if { |tag| /satellite5|sat5|unregistered|duplicated|channel/.match(tag.to_s).nil? }
	# remove - for better comparisons
	vm_uuid = vm.attributes['uid_ems'].tr('-','')

	# for each vm that matches add the satellite tags, otherwise tag as unregistered if the os has "red hat" in it
	if uuidcollection.has_key?(vm_uuid) then
		registration_tag = 'sat5-id-'+uuidcollection[vm_uuid]['systemid']
		if not $evm.execute('tag_exists?', 'registration', registration_tag) then
			$emv.execute('tag_create', "registration", :name => registration_tag, :description => "registrationtag for satellite 5")
		end
		vm.tag_assign('organization', registration_tag)
		# org_id info
		org_tag = 'org-'+SATORG.to_s()
		if not $evm.execute('tag_exists?', 'satellite5', org_tag) then
			orgdetails = @client.call('org.getDetails', @key, SATORG)
			$emv.execute('tag_create', "satellite5", :name => org_tag, :description => orgdetails['name'] )
		end
		vm.tag_assign('satellite5', org_tag)
		#base channel
		base = @client.call('system.getSubscribedBaseChannel',@key,uuidcollection[vm_uuid]['systemid'])
		if not $evm.execute('tag_exists?', 'channel', base['label']) then
			$emv.execute('tag_create', "channel", :name => base['label'], :description => base['name'])
		end
		vm.tag_assign('channel', base['label'])
		#child channels
		childs = @client.call('system.listSubscribedChildChannels',@key,uuidcollection[vm_uuid]['systemid'])
		childs.each do |channel|
			if $evm.execute('tag_exists?', 'channel', channel['label']) then
				$emv.execute('tag_create', "channel", :name => channel['label'], :description => channel['name'])
			end
			vm.tag_assign('channel', channel['label'])
		end
		#entitlements
		entitlements = @client.call('system.getEntitlements', @key, uuidcollection[vm_uuid]['systemid'])
		entitlements.each do |entitlement|
			if not $evm.execute('tag_exists?', 'satellite5', entitlement) then
				$emv.execute('tag_create', "satellite5", :name => entitlement, :description => entitlement)
			end
			vm.tag_assign('satellite5', entitlement)
		end
		#duplicate indication
		if uuidcollection[vm_uuid]['count'] > 1 then
			vm.tag_assign('registration','duplicated')
			$evm.log("info","the machine #{vm.name} has multiple profiles on the satellite")
		end
	elsif not /rhel/.match(vm.operating_system['product_name']).nil? then
		#this is a red hat system that isn't registered on the satellite - tag is as unregistered
		vm.tag_assign('registration', 'unregistered')
		$emv.log("info","the machine #{vm.name} is not registered to the satellite")
	else
		$evm.log("info","the machine #{vm.name} is not a RHEL system - ignoring it")
	end
end

#cleanup
@client.call("auth.logout",@key)

#
#
$evm.log("info", "Tagging all systems of one cluster - automation finished")


exit MIQ_OK
