# Keycloak Utils

## [import-users.sh](./import-users.sh) - Administer Keycloak accounts from the command-line
See [users.csv](./users.csv) for example format.
### Prerequisites in the Keycloak realm:
1. Create client (eg. keycloak_acct_admin) for this script. Access Type: public.
1. Add the realm admin user (eg. realm_admin) to the realm
1. In the realm admin user's settings > Client Role > "realm-management", assign it all available roles
1. In client, enable Direct Grant API at Settings > Login

Note:
- csv file must be in unix format - dos2unix.
- KeyCloak API: https://www.keycloak.org/docs-api/4.0/rest-api/index.html#_overview

### Import users found in csv
```sh
$ ./import-users.sh --import users.csv
```

### Delete users found in csv
```sh
$ ./import-users.sh --delete users.csv
```
