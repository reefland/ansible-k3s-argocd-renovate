# Cert Manager Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* `Cert-manager` is installed since Traefik's Let's Encrypt support retrieves certificates and stores them in files. Cert Manager retrieves certificates and stores them in Kubernetes secrets.

## Review `defaults/main.yml` for Cert Manager Settings

There should not be a need to update any settings for Cert Manager. The Cert Manager settings are in variable namespace `install.cert_manager`.

### Define Cert Manager Version to Install

 Available version number can be found [here](https://artifacthub.io/packages/helm/cert-manager/cert-manager).

```yml
cert_manager:
  install_version: "v1.7.1"
```

[Back to README.md](../README.md)
