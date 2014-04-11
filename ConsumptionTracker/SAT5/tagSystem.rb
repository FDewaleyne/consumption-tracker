#
#            Automate Method
#
$evm.log("info", "Tagging one system - automation started")
#
#            Method Code Goes here
#

# Values in CF #
SAT_URL = $evm.object['url']
SAT_LOGIN = $evm.object['username']
SAT_PWD = $evm.object['password']
SATORG = $evm.object['orgid']
vm = $evm.root['vm']
#format the uuid so that we may use it
vm_uuid = vm.attributes['uid_ems'].tr('-','')
#making sure the basic tags & categories exist for the other scripts
if not $evm.execute('category_exists?','registration') then
	$evm.execute('category_create', :name => 'registration', :single_value => false, :description => 'Registration information')
	$evm.execute('tag_create', 'registration', :name => 'unregistered', :description => 'not registered')
	$evm.execute('tag_create', 'registration', :name => 'duplicated', :description => 'duplicated on management system')
end
if not $evm.execute('category_exists?','channel') then
	$evm.execute('category_create',:name => 'channel', :single_value => false, :description => 'Channel usage information')
end
if not $evm.execute('category_exists?','satellite5') then
	$evm.execute('category_create',:name => 'satellite5', :single_value => false, :description => 'Satellite 5 details')
end
if not $evm.execute('category_exists?','sat5organization')
	$evm.execute('category_create',:name => 'sat5organization', :single_value => true, :description => 'Satellite 5 Organization')
end
if not $evm.execute('category_exists?','sat5entitlements')
	$evm.execute('category_create',:name => 'sat5entitlements', :single_value => false, :description => 'Satellite 5 entitlements')
	$evm.execute('tag_create', 'sat5entitlements', :name => 'enterprise_entitled', :description => 'Management (Base)')
	$evm.execute('tag_create', 'sat5entitlements', :name => 'monitoring_entitled', :description => 'Monitoring (Add-On)')
	$evm.execute('tag_create', 'sat5entitlements', :name => 'provisioning_entitled', :description => 'Provisioning (Add-On)')
	$evm.execute('tag_create', 'sat5entitlements', :name => 'virtualization_host', :description => 'Virtualization (Add-On)')
	$evm.execute('tag_create', 'sat5entitlements', :name => 'virtualization_host_platform', :description => 'Virtualization Platform (Add-On)')
end


# before we continue make sure that this is a RHEL system
if /rhel/.match(vm.operating_system['product_name']).nil? then
	$evm.log("info", "The system #{vm.name} is not a RHEL system, it will not be tagged")
	exit MIQ_OK
end

# init part #
require "xmlrpc/client"
begin
	@client = XMLRPC::Client.new2(SAT_URL)
	@key = @client.call('auth.login', SAT_LOGIN, SAT_PWD)
rescue
	$evm.log("error","unable to log into the satellite, aborting")
	exit MIQ_ABORT
end

#remove registration and satellite 5 tags
#we want to remove channels, any active registration tag that is sat5, unregistered or duplicated
vm.tags.keep_if { |tag| /satellite5|sat5|unregistered|duplicated|channel/.match(tag.to_s).nil? }

# lookup for UUID #
begin
	systems = @client.call('system.search.uuid',@key,vm_uuid)
rescue
	exit MIQ_STOP
end
if systems.size > 1 then
	# this system is duplicated!
	vm.tag_assign("registration/duplicated")
	$evm.log("info","the system #{vm.name} has multiple profiles on the satellite")
	# select the last checked in profile
	# also tag the system as over consuming entitlements since it is over-consuming management by having multiple profiles
	require "date"
	systems.each do |system|
		last_system = systems.first
		# queue in a hardware refresh in the satellite to help clean the profile and identify profiles in use in different systems
		@client.call('system.scheduleHardwareRefresh',@key, system['id'], Date.today)
		if last_system['last_checkin'].to_date < system['last_checkin'].to_date then
			#the other system is more recent
			last_system = system
		else
			#the date in the object is more recent than that of the others
			next;
		end
	end
elsif systems.size == 1 then
	last_system = systems.first
else
	# no system found. mark as unregistered
	vm.tag_assign("registration/unregistered")
	last_system = nil
	$evm.log("info","the system #{vm.name} is not registered to the satellite")
	exit MIQ_OK
end

#tagging with the informations since this system is registered
registration_tag = "sat5-id-#{last_system['id'].to_s}"
if not $evm.execute('tag_exists?', 'registration', registration_tag) then
	$evm.execute('tag_create', "registration", :name => registration_tag, :description => "satellite 5 registration tag for #{last_system['id'].to_s}")
end
vm.tag_assign("registration/#{registration_tag}")
# org_id info
org_tag = "org__#{SATORG.to_s}"
if not $evm.execute('tag_exists?', 'sat5organization', org_tag) then
	orgdetails = @client.call('org.getDetails', @key, SATORG)
	$evm.execute('tag_create', "sat5organization", :name => org_tag, :description => orgdetails['name'] )
end
vm.tag_assign("sat5organization/#{org_tag}")
#base channel
base = @client.call('system.getSubscribedBaseChannel',@key, last_system['id'])
if not $evm.execute('tag_exists?', 'channel', base['label'].tr('-','_')) then
	$evm.execute('tag_create', "channel", :name => base['label'].tr('-','_'), :description => base['label']+" (#{base['name']})")
end
$evm.log("info","#{vm.name} uses the channel #{base['label']}")
vm.tag_assign("channel/#{base['label'].tr('-','_')}")
#child channels
childs = @client.call('system.listSubscribedChildChannels',@key,last_system['id'])
childs.each do |channel|
	if not $evm.execute('tag_exists?', 'channel', channel['label'].tr('-','_')) then
		$evm.execute('tag_create', "channel", :name => channel['label'].tr('-','_'), :description => channel['label']+" (#{channel['name']})")
	end
	$evm.log("info","#{vm.name} uses the channel #{channel['label']}")
	vm.tag_assign("channel/#{channel['label'].tr('-','_')}")
end
#entitlements
entitlements = @client.call('system.getEntitlements', @key, last_system['id'])
entitlements.each do |entitlement|
	$evm.log("info","#{vm.name} uses the entitlement #{entitlement}")
	#the entitlements don't vary between the 5 existing ones
	vm.tag_assign("sat5entitlement/#{entitlement}")
end

# cleanup  #
@client.call('auth.logout', @key)


#
#
#
$evm.log("info", "Tagging one system - automation finished")
exit MIQ_OK
