# Cert Manager Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* `Cert-manager` is installed since Traefik's Let's Encrypt support retrieves certificates and stores them in files.
  * Cert-manager retrieves certificates and stores them in Kubernetes secrets.
  * Secrets are more secured, but secrets can not span multiple namespaces
  * Certificates shared across namespaces can be a challenge.
* `Cert-manager` processing certificates, removes a Traefik ACME handshake issue which normally requires it to run as a single instance.
  * This allows Traefik to be run as a DaemonSet which removes a single point of failure.

---

## Review `defaults/main.yml` for Cert Manager Settings

There should not be a need to update any settings for Cert Manager. The Cert-manager settings are in variable namespace `install.cert_manager`.

### Define Cert-manager Version to Install

 Available version number can be found [here](https://artifacthub.io/packages/helm/cert-manager/cert-manager).

* Pin which version of democratic-csi to install. This value should be defined in the inventory file or group_vars file or can be updated directly here:

  ```yaml
  install:
    cert_manager:
      # Select release to use:  https://github.com/cert-manager/cert-manager/releases
      install_version: "{{cert_manager_install_version|default('v1.10.0')}}"
  ```

* Define the namespace to install Cert Manager into:

  ```yaml
      namespace: "cert-manager"      # Add resources to this namespace
  ```

* Define ArgoCD Project to associate Cert Manager with:

  ```yaml
      argocd_project: "security"     # ArgoCD Project to associate this with
  ```

[Back to README.md](../README.md)
