_represents the schema to use for this namespace ; this version applied to 1.1 and previous_
### The values
_all values are to be executed on all filters_
- `url` : a value, represents the satellite url (type string)
- `username` : a value, represents the satellite username (type string)
- `password` : a value, represents the satellite password (type string)
- `orgid` : a value, represents the id of the org (type int)

### The methods
- `tagSystem` : executed on message `onesystem` only, need to access the UUID of a machine
- `tagSystems` : execyted on  message `onecluster`only, reads the UUID for each machine of the cluster

