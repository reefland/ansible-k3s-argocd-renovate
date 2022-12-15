# Let's Encrypt Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* **Let's Encrypt** is configured for **Staging** certificates, but you can default it to **Prod** or use provided CLI parameter `--extra-vars='le_staging=false'` to generate **Prod** certificates if you have a known working configuration.
* Let's Encrypt is configured to use CloudFlare DNS ACME Challenge
  * (other methods may be added in the future)

---

## Review `vars/secrets/main.yml` for Let's Encrypt Secrets

You need to define information required for Let's Encrypt ACME challenge.

### CloudFlare DNS Challenge

Requires the following permissions:

* Requires Zone / Zone / Read
* Requires Zone / DNS / Edit Permissions

```yaml
###[ Let's Encrypt: CloudFlare DNS Authentication ]################################################
# API Token for ACME DNS Challenge
# Cloudflare API token used by Cert-manager
# Requires Zone / Zone / Read
# Requires Zone / DNS / Edit Permissions
DNS_API_TOKEN_SECRET: "<token-value>"

# Email address associated to DNS API key
AUTH_EMAIL_SECRET: "email@example.com"

# Email address associated to Let's Encrypt
LE_AUTH_EMAIL_SECRET: "email@example.com"

# List of Domains to Create Certificates
LE_DOMAINS_SECRET:
  - "example.com"
  - "*.example.com"
```

* `DNS_API_TOKEN_SECRET` is the value of the API token issued by CloudFlare.
* `AUTH_EMAIL_SECRET` is the email address associated with the API Token.
* `LE_AUTH_EMAIL_SECRET` is the email address associated with Let's Encrypt.
* `LE_DOMAINS_SECRET` is a list of domains names to create LE certificates for.
  * The `*` indicates a Wildcard Certificate and will automatically cover any sub-domains. No need to list any sub-domains.

**Be sure to encrypt all the secrets above when completed:**

```shell
ansible-vault encrypt vars/secrets/main.yml
```

---

## Review `defaults/main.yml` for Let's Encrypt Settings

The Let's Encrypt Settings are in variable namespace `install.lets_encrypt`.

### Define CloudFlare DNS Token Authentication

The values of `DNS_API_TOKEN_SECRET` and `AUTH_EMAIL_SECRET` are defined in `vars/secrets/main.yaml`.

```yaml
install:
  ###[ Let's Encrypt Certificate Configuration ]###################################################
  lets_encrypt:
    # Define secrets in vars/secrets/main.yml
    le_api_token_name: "{{DNS_API_TOKEN_SECRET}}"  # Define the name of the API token key                                           #
    le_api_token_email: "{{AUTH_EMAIL_SECRET}}"    # Define the name of the email authorization key
```

* Nothing to change here, unless you want to use a different variable name for Token or Email address.

### Define Let's Encrypt Email and Domains for Certificates

The values of `LE_AUTH_EMAIL_SECRET` and `LE_DOMAINS_SECRET` are defined in `vars/secrets/main.yaml`.

```yaml
    le_email_auth: "{{LE_AUTH_EMAIL_SECRET}}"      # Define the name of the Let's Encrypt Email Address
    domains: "{{LE_DOMAINS_SECRET}}"               # List of Domain Names for LetsEncrypt Certificates
```

* Nothing to change here, unless you want to use a different variable name for Email or Domain names.

### Staging or Production Certificates

```yaml
    # to create prod certificates --extra-vars="le_staging=false"
    le_staging: "{{le_staging|default(true)}}"
```

* The `le_staging` defaults to `true`. This means generate Staging certificates to test the installation.
  * Don't change this value.

This creates a `ClusterIssuer` kubernetes object.  You can see which are available using:

```shell
$ kubectl get clusterissuers

NAME                  READY   AGE
letsencrypt-staging   True    14m
```

Review the status to see confirm that Cert-manager has registered the provider correctly:

```shell
$ kubectl get clusterissuers letsencrypt-staging -o yaml

apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:

...

status:
  acme:
    lastRegisteredEmail: email@example.com
    uri: https://acme-staging-v02.api.letsencrypt.org/acme/acct/0x0x0x0x
  conditions:
  - lastTransitionTime: "2022-05-12T14:58:02Z"
    message: The ACME account was registered with the ACME server
    observedGeneration: 1
    reason: ACMEAccountRegistered
    status: "True"
    type: Ready
```

---

## Switch to Production Certificates

Once the default staging certificates are verified to be working, the playbook can be run to switch to production certificates.

* Apply playbook to create Production ClusterIssuer:

```shell
ansible-playbook -i inventory k3s-argocd.yml --tags="config_le_certificates" --extra-vars="le_staging=false"
```

This will clone the ArgoCD repository and replace the staging wildcard certificate and Cert-Manager ClusterIssuer with the production equivalent and commit the change back to ArgoCD. Within a ArgoCD sync cycle or two you should have the production certificate ready for use.

### Review Production Certificate Created

```shell
$ kubectl get certificate wildcard-cert -n traefik -o yaml

apiVersion: cert-manager.io/v1
kind: Certificate
...
spec:
  dnsNames:
  - example.com
  - '*.example.com'
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-prod
  secretName: wildcard-cert
status:
  conditions:
  - lastTransitionTime: "2022-05-02T16:21:34Z"
    message: Certificate is up to date and has not expired
    observedGeneration: 1
    reason: Ready
    status: "True"
    type: Ready
```

* The `.spec.issuerRef.name` should reflect `letsencrypt-prod`
* The status condition message should reflect `Certificate is up to date and has not expired`

---

## Commands to Review / Troubleshoot Certificates

### List Certificates Generated

```shell
$ kubectl get certificates -A

NAMESPACE   NAME            READY   SECRET          AGE
traefik     wildcard-cert   True    wildcard-cert   5h6m
```

* If no `wildcard-cert` is listed ("No resources found" message), then see help for [missing wildcard certificate](./lets-encrypt-missing-wildcard-cert.md).

### Show Certificate Metadata

```shell
$ kubectl  get certificate wildcard-cert -n traefik -o yaml

apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  creationTimestamp: "2022-05-01T19:46:09Z"
  generation: 1
  name: wildcard-cert
  namespace: traefik
  resourceVersion: "2575"
  uid: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
spec:
  dnsNames:
  - [redacted]
  - '*.[redacted]'
  issuerRef:
    kind: ClusterIssuer
    name: letsencrypt-staging
  secretName: wildcard-cert
status:
  conditions:
  - lastTransitionTime: "2022-05-01T19:48:50Z"
    message: Certificate is up to date and has not expired
    observedGeneration: 1
    reason: Ready
    status: "True"
    type: Ready
  notAfter: "2022-07-30T18:48:48Z"
  notBefore: "2022-05-01T18:48:49Z"
  renewalTime: "2022-06-30T18:48:48Z"
  revision: 1`
```

* The `.spec.issuerRef.name` shows this is a staging certificate.
* The `.status.conditions.message` shows the state of the certificate.
* The `.status.notAfter` shows the date of expiration.

### Show Certificate Secret Information

```shell
$ kubectl get secret wildcard-cert -n traefik -o yaml

apiVersion: v1
data:
  tls.crt: [redacted]
  tls.key: [redacted]
kind: Secret
metadata:
  annotations:
    cert-manager.io/alt-names: '*.example.com,example.com'
    cert-manager.io/certificate-name: wildcard-cert
    cert-manager.io/common-name: example.com
    cert-manager.io/ip-sans: ""
    cert-manager.io/issuer-group: ""
    cert-manager.io/issuer-kind: ClusterIssuer
    cert-manager.io/issuer-name: letsencrypt-staging
    cert-manager.io/uri-sans: ""
  creationTimestamp: "2022-05-01T19:48:50Z"
  name: wildcard-cert
  namespace: traefik
  resourceVersion: "2569"
  uid: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
type: kubernetes.io/tls
```

---

## Example App Deployment with Certificates

To test generated certificates, a deployment using `whoami` is provided

### Install Test Application

```shell
sudo su - kube
cd ~/traefik

# Deploy apps & create ingress rules
kubectl apply -f traefik_test_apps.yaml

```

### Confirm Application Installation

```shell
# Confirm pods are running:
kubectl get pods -n default

  NAME                      READY   STATUS    RESTARTS      AGE
  whoami-5b69cdcd49-2gfts   1/1     Running   2 (23m ago)   6h9m
  whoami-5b69cdcd49-bg5j4   1/1     Running   2 (23m ago)   6h9m
```

### Test Certificates

```shell
# Simple test without certificates (notice URI of "/notls")
curl http://$(hostname -f):80/notls

Hostname: whoami-5b69cdcd49-2gfts
IP: 127.0.0.1
IP: ::1
IP: 10.42.0.37
IP: fe80::c43:7ff:fe31:3b61
RemoteAddr: 10.42.0.34:52596
GET /notls HTTP/1.1
Host: testlinux.example.com
User-Agent: curl/7.68.0
Accept: */*
Accept-Encoding: gzip
X-Forwarded-For: 10.42.0.36
X-Forwarded-Host: testlinux.example.com
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: traefik-6bb96f9bd8-72cj8
X-Real-Ip: 10.42.0.36

# This will work ONLY with a production cert, it will FAIL with a staging cert:
curl https://$(hostname -f):/tls

# This will work with EITHER staging OR production cert:
curl -k https://$(hostname -f):/tls
```

### Show Certificate Information

```shell
kubectl describe certificates wildcard-cert -n kube-system

Spec:
  Dns Names:
    example.com
    *.example.com
  Issuer Ref:
    Kind:       ClusterIssuer
    Name:       letsencrypt-prod
  Secret Name:  wildcard-secret
Status:
  Conditions:
    Last Transition Time:  2022-02-24T18:09:47Z
    Message:               Certificate is up to date and has not expired
    Observed Generation:   1
    Reason:                Ready
    Status:                True
    Type:                  Ready
  Not After:               2022-05-25T17:09:46Z
  Not Before:              2022-02-24T17:09:47Z
  Renewal Time:            2022-04-25T17:09:46Z
```

### Uninstall & Cleanup Test Application

```shell
# To delete the "whoami" deployment and ingress rules:
kubectl delete -f traefik_test_apps.yaml

deployment.apps "whoami" deleted
service "whoami" deleted
ingressroute.traefik.containo.us "simpleingressroute" deleted
ingressroute.traefik.containo.us "ingressroutetls" deleted
```

[Back to README.md](../README.md)
