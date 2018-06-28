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
- When user logs in for the first time have set Required Action to be = updatePassword

### Import users found in csv
```sh
$ ./import-users.sh --import users.csv
```

### Delete users found in csv
```sh
$ ./import-users.sh --delete users.csv
```

# SSO for web console

- https://access.redhat.com/documentation/en-us/red_hat_single_sign-on/7.2/html-single/red_hat_single_sign-on_for_openshift/#configuring_rh_sso_credentials

Import templates

```sh
for resource in sso72-image-stream.json \
  sso72-https.json \
  sso72-mysql-persistent.json \
  sso72-mysql.json \
  sso72-postgresql-persistent.json \
  sso72-postgresql.json
do
  oc replace -n openshift --force -f \
  https://raw.githubusercontent.com/jboss-openshift/application-templates/ose-v1.4.14/sso/${resource}
done
```

This is the SSO image we want to use

```sh
oc -n openshift import-image redhat-sso72-openshift:1.1
```

Create certificates

```sh
openssl req -new -newkey rsa:4096 -x509 -keyout xpaas.key -out xpaas.crt -days 365 -subj "/CN=sso.apps.bar.com" -passout pass:xxxx
keytool -genkeypair -keyalg RSA -keysize 2048 -dname "CN=secure-sso-sso.apps.bar.com" -alias sso-https-key -keystore sso-https.jks -storepass pass:xxxx -keypass pass:xxxx -noprompt
keytool -certreq -keyalg rsa -alias sso-https-key -keystore sso-https.jks -file sso.csr -storepass pass:xxxx -noprompt
openssl x509 -req -CA xpaas.crt -CAkey xpaas.key -in sso.csr -out sso.crt -days 365 -CAcreateserial -passin pass:xxxx
keytool -import -file xpaas.crt -alias xpaas.ca -keystore sso-https.jks -storepass pass:xxxx -noprompt
keytool -import -file sso.crt -alias sso-https-key -keystore sso-https.jks -storepass pass:xxxx -noprompt
keytool -import -file xpaas.crt -alias xpaas.ca -keystore truststore.jks -storepass pass:xxxx -noprompt
keytool -genseckey -alias jgroups -storetype JCEKS -keystore jgroups.jceks -storepass pass:xxxx -keypass pass:xxxx -noprompt
```

Copy the cert for SSO for OpenShift master to use (e.g /etc/origin/master or similar)

```sh
cp xpaas.crt /etc/origin/master/
```

Create a project as admin user in OpenShift and load secrets

```sh
oc new-project sso --display-name="SSO" --description="SSO"
oc secret new sso-jgroup-secret jgroups.jceks
oc secret new sso-ssl-secret sso-https.jks truststore.jks
oc secrets link default sso-jgroup-secret sso-ssl-secret
```

Create a persistent SSO container

```
oc new-app sso72-postgresql-persistent \
  -p HTTPS_KEYSTORE=sso-https.jks \
  -p HTTPS_PASSWORD=pass:xxxx \
  -p HTTPS_SECRET=sso-ssl-secret \
  -p JGROUPS_ENCRYPT_KEYSTORE=jgroups.jceks \
  -p JGROUPS_ENCRYPT_PASSWORD=pass:xxxx \
  -p JGROUPS_ENCRYPT_SECRET=sso-jgroup-secret \
  -p SSO_REALM=ocprealm \
  -p SSO_SERVICE_USERNAME=sso-mgmtuser \
  -p SSO_SERVICE_PASSWORD=mgmt-password \
  -p SSO_ADMIN_USERNAME=admin \
  -p SSO_ADMIN_PASSWORD=lionred3 \
  -p SSO_TRUSTSTORE=truststore.jks \
  -p SSO_TRUSTSTORE_SECRET=sso-ssl-secret \
  -p SSO_TRUSTSTORE_PASSWORD=pass:xxxx \
  -p VOLUME_CAPACITY=1Gi
```

First time usage - create a realm `ocp-web` for using with OpenShift web console (or import realm file if you have exported one previously)

```sh
-- Go to web and
- Create a Realm
- Create a user (admin)
- Create and Configure an OpenID-Connect Client
```

Goto to the Realm and get the openid-connect endpoint configuration e.g.
- https://secure-sso-sso.apps.bar.com/auth/realms/ocprealm/.well-known/openid-configuration

We also need the Client secret.

Set up OpenShift `identityProvider` with these values.

```sh
-- vi /etc/origin/master/master-config.yaml

oauthConfig:
  assetPublicURL: https://ocp.hosts.bar.com:8443/console/
  grantConfig:
    method: auto
  identityProviders:
  - name: rh_sso
    challenge: false
    login: true
    mappingInfo: add
    provider:
      apiVersion: v1
      kind: OpenIDIdentityProvider
      clientID: ocp-web
      clientSecret: f236f3c1-ba00-4193-9944-5843c7267b87
      ca: xpaas.crt
      urls:
        authorize: https://secure-sso-sso.apps.bar.com/auth/realms/ocprealm/protocol/openid-connect/auth
        token: https://secure-sso-sso.apps.bar.com/auth/realms/ocprealm/protocol/openid-connect/token
        userInfo: https://secure-sso-sso.apps.bar.com/auth/realms/ocprealm/protocol/openid-connect/userinfo
      claims:
        id:
        - sub
        preferredUsername:
        - preferred_username
        name:
        - name
        email:
        - email
```

If you already have a local user called `admin`, and  you want to replace it with your newly created `admin` user from SSO:

```sh
-- delete local admin, so sso admin works
oc login -u system:admin
oc delete user admin
oc adm policy add-cluster-role-to-user cluster-admin admin --as=system:admin

$ oc get users
NAME      UID                                    FULL NAME   IDENTITIES
admin     bd926a14-7a5d-11e8-b583-a44cc8fb623b               rh_sso:818ddb85-5044-48ee-9e64-33fd269aacf3
```

Make Logout work in OCP-3.9

```sh
oc edit configmap/webconsole-config -n openshift-web-console
-- set the value
logoutPublicURL: https://secure-sso-sso.apps.bar.com/auth/realms/ocprealm/protocol/openid-connect/logout?redirect_uri=https://ocp.hosts.bar.com:8443/console/
-- kill the webconsole pod to reload configmap
```
