# Cert Manager Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* `Cert-manager` is installed since Traefik's Let's Encrypt support retrieves certificates and stores them in files. Cert-manager retrieves certificates and stores them in Kubernetes secrets.

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

[Back to README.md](../README.md)
