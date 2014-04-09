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
	$evm.execute('tag_create', "registration", :name => registration_tag, :description => "registrationtag for satellite 5")
end
vm.tag_assign("registration/#{registration_tag}")
# org_id info
org_tag = "org-#{SATORG.to_s}"
vm.tag_assign("satellite5/#{org_tag}")
#base channel
base = @client.call('system.getSubscribedBaseChannel',@key, last_system['id'])
if not $evm.execute('tag_exists?', 'channel', base['label']) then
	$evm.execute('tag_create', "channel", :name => base['label'], :description => base['name'])
end
$evm.log("info","#{vm.name} uses the channel #{base['label']}")
vm.tag_assign("channel/#{base['label']}")
#child channels
childs = @client.call('system.listSubscribedChildChannels',@key,last_system['id'])
childs.each do |channel|
	if not $evm.execute('tag_exists?', 'channel', channel['label']) then
		$evm.execute('tag_create', "channel", :name => channel['label'], :description => channel['name'])
	end
	$evm.log("info","#{vm.name} uses the channel #{channel['label']}")
	vm.tag_assign("channel/#{channel['label']}")
end
#entitlements
entitlements = @client.call('system.getEntitlements', @key, last_system['id'])
entitlements.each do |entitlement|
	if not $evm.execute('tag_exists?', 'satellite5', entitlement) then
		$evm.execute('tag_create', "satellite5", :name => entitlement, :description => entitlement)
	end
	$evm.log("info","#{vm.name} uses the entitlement #{entitlement}")
	vm.tag_assign("satellite5/#{entitlement}")
end

# cleanup  #
@client.call('auth.logout', @key)


#
#
#
$evm.log("info", "Tagging one system - automation finished")
exit MIQ_OK
