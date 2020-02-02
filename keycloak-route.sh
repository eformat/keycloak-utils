#!/bin/bash

DOMAIN=foo.sandbox1459.opentlc.com

oc replace -n keycloak -f - <<EOF
apiVersion: v1
kind: Route
metadata:
  annotations:
    haproxy.router.openshift.io/balance: source
  labels:
    app: keycloak
  name: keycloak
  namespace: keycloak
spec:
  host: keycloak-keycloak.apps.${DOMAIN}
  to:
    kind: Service
    name: keycloak
  tls:
    termination: reencrypt
    key: |-
$(sed 's/^/      /' /home/mike/.acme.sh/api.${DOMAIN}/api.${DOMAIN}.key)
    certificate: |-
$(sed 's/^/      /' /home/mike/.acme.sh/api.${DOMAIN}/api.${DOMAIN}.cer)
    caCertificate: |-
$(sed 's/^/      /' /home/mike/.acme.sh/api.${DOMAIN}/fullchain.cer)
EOF

