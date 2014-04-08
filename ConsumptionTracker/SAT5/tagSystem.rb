#
#            Automate Method
#
$evm.log("info", "Tagging one system - automation started")
#
#            Method Code Goes here
#

# Values in CF #
SAT_URL = $evm.root['url']
SAT_LOGIN = $evm.root['username']
SAT_PWD = $evm.root['password']
SATORG = $evm.root['orgid']
vm = $evm.root['vm']


# before we continue make sure that this is a RHEL system
if /rhel/.match(vm.operating_system['product_name']).nil? then
	$evm.log("info", "The system #{vm.name} is not a RHEL system, it will not be tagged")
	exit MIQ_OK
end

# init part #
require "xmlrpc/client"
@client = XMLRPC::Client.new2(SAT_URL)
@key = @client.call('auth.login', SAT_LOGIN, SAT_PWD)

#remove registration and satellite 5 tags
#we want to remove channels, any active registration tag that is sat5, unregistered or duplicated
vm.tags.keep_if { |tag| /satellite5|sat5|unregistered|duplicated|channel/.match(tag.to_s).nil? }

# lookup for UUID #
systems = @client.call('system.search.uuid',@key,vm.attributes['uid_ems'])
if systems.size > 1 then
	# this system is duplicated!
	vm.tag_assign("registration", "duplicated")
	$evm.log("info","the system #{vm.name} has been registered several times")
	# select the last checked in profile
	# also tag the system as over consuming entitlements since it is over-consuming management by having multiple profiles
	require "date"
	systems.each do |system|
		#debug
		puts system
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
	vm.tag_assign("registration","unregistered")
	last_system = nil
	$evm.log("info","the system #{vm.name} is not registered to the satellite")
	exit MIQ_OK
end

#tagging with the informations since this system is registered
registration_tag = 'sat5-id-'+vm.attributes.uid_ems.to_s()
if not $evm.execute('tag_exists?', 'registration', registration_tag) then
	$emv.execute ('tag_create', "registration", :name => registration_tag, :description => "registrationtag for satellite 5")
end
vm.tag_assign('organization', registration_tag)
# org_id info
org_tag = 'org-'+SATORG.to_s()
vm.tag_assign('satellite5', org_tag)
#base channel
base = @client.call('system.getSubscribedBaseChannel',@key, vm.attributes['uid_ems'])
if not $evm.execute('tag_exists?', 'channel', base['label']) then
	$emv.execute ('tag_create', "channel", :name => base['label'], :description => base['name'])
end
vm.tag_assign('channel', base['label'])
#child channels
childs = @client.call('system.listSubscribedChildChannels',@key,vm.attributes['uid_ems'])
childs.each do |channel|
	if not $evm.execute('tag_exists?', 'channel', channel['label']) then
		$emv.execute ('tag_create', "channel", :name => channel['label'], :description => channel['name'])
	end
	vm.tag_assign('channel', channel['label'])
end
#entitlements
entitlements = @client.call('system.getEntitlements', @key, vm.attributes['uid_ems'])
entitlements.each do |entitlement|
	if not $evm.execute('tag_exists?', 'satellite5', entitlement) then
		$emv.execute ('tag_create', "satellite5", :name => entitlement, :description => entitlement)
	end
	vm.tag_assign('satellite5', entitlement)
end

# cleanup  #
@client.call('auth.logout', @key)


#
#
#
$evm.log("info", "Tagging one system - automation finished")
exit MIQ_OK
