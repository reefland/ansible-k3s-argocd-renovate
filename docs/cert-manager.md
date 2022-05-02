# Cert Manager Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* `Cert-manager` is installed since Traefik's Let's Encrypt support retrieves certificates and stores them in files.
  * Cert-manager retrieves certificates and stores them in Kubernetes secrets.
  * Secrets are more secured, but secrets can not span multiple namespaces
  * Certificates shared across namespaces can be a challenge.
* `Cert-manager` processing certificates, removes a Traefik ACME handshake issue which normally requires it to run as a single instance.
  * This allows Traefik to be run as a DaemonSet which removes a single point of failure.
* **Let's Encrypt** is configured for **Staging** certificates, but you can default it to **Prod** or use provided CLI parameter `--extra-vars 'le_staging=false'` to generate **Prod** certificates once you have a working configuration.

---

## Review `defaults/main.yml` for Cert Manager Settings

There should not be a need to update any settings for Cert Manager. The Cert-manager settings are in variable namespace `install.cert_manager`.

### Define Cert-manager Version to Install

 Available version number can be found [here](https://artifacthub.io/packages/helm/cert-manager/cert-manager).

```yaml
install:
  cert_manager:
    # Select release to use:  https://github.com/cert-manager/cert-manager/releases
    install_version: "{{cert_manager_install_version|default('v1.7.1')}}"

    namespace: "cert-manager"
```

### Staging or Production Certificates

```yaml
install:
  cert_manager:
    ...

    # to create prod certificates --extra-vars "le_staging=false"
    le_staging: "{{le_staging|default(true)}}"
```

* The `le_staging` defaults to `true`. This means generate Staging certificates to test the installation.
  * Don't change this value.

#### Switch to Production Certificates

Once the default staging certificates are verified to be working, the playbook can be run to switch to production certificates.

* On Kubernetes delete the staging secret and certificates:

```shell
$ kubectl delete secret wildcard-cert -n traefik
secret "wildcard-cert" deleted

$ kubectl delete certificate wildcard-cert -n traefik
certificate.cert-manager.io "wildcard-cert" deleted
```

* Apply playbook to regenerate certificates:

```shell
ansible-playbook -i inventory kubernetes.yml --tags="config_ls_certificates,config_traefik" --extra-vars="le_staging=false"
```

#### Review Production Certificate Created

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

### Certificate Domain Names

```yaml
install:
  cert_manager:
    ...

    # List of Domain Names for LetsEncrypt Certificates stored in   var/secret/letsencrypt_secrets.yml
    domains: "{{LE_DOMAINS}}"
```

* The `domains` defines which wildcard certificates to create.  The variable `"{{LE_DOMAINS}}"` is defined in `var/secret/letsencrypt_secrets.yml`

---

## Review `vars/secrets/letsencrypt_secrets.yml` for Let's Encrypt Settings

### Configure CloudFlare DNS Challenge

* `CF_DNS_API_TOKEN` - CloudFlare API token value
* `CF_AUTH_EMAIL` - CloudFlare Email address associated with the API token
* `LE_AUTH_EMAIL` - Letsencrypt Email Address for expiration Notifications
* `LE_DOMAINS` - List of domain names for Wildcard Certificates

```yml
# Cloudflare API token used by Traefik
# Requires Zone / Zone / Read
# Requires Zone / DNS / Edit Permissions
CF_DNS_API_TOKEN: abs123 ... 456xyz

# Email address associated to DNS API key
CF_AUTH_EMAIL: you@domain.com

# Email address associated to Let's Encrypt
LE_AUTH_EMAIL: you@domain.com

# List of Domains to Create Certificates
LE_DOMAINS:
  - "example.com"
  - "*.example.com"
```

**Be sure to encrypt all the secrets above when completed:**

```shell
ansible-vault encrypt vars/k3s_traefik_api_secrets.yml
```

---

## Commands to review / troubleshoot certificate

### List Certificates Generated

```shell
$ kubectl get certificates -A

NAMESPACE   NAME            READY   SECRET          AGE
traefik     wildcard-cert   True    wildcard-cert   5h6m
```

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
  uid: ffdfbf39-5ed4-4b4d-a76e-176c67631d47
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
  uid: 263d012c-c3d0-436a-a582-f066a95ba66e
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
