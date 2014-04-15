#represents the schema to use for this namespace
#the values
url : a value, represents the satellite url (type string)
username : a value, represents the satellite username (type string)
password : a value, represents the satellite password (type string)
orgid : a value, represents the id of the org (type int)
active : true / false (indicates wether or not to use the org)

#the methods
tagSystem : executed on #onesystem, need to access the UUID of a machine
tagSystems : execyted on #onecluster, reads the UUID for each machine of the cluster

