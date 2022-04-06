# Prometheus Operator Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* Prometheus will use persistent storage. By default it is configured to use the democratic CSI TrueNAS iSCSI persistent storage.  This can be configured to use Longhorn persistent storage.
* To prevent Traefik metrics from being exposed on the LoadBalancer IP address, an internal ClusterIP service is created for the service monitor to reach Traefik metrics.

## Review `defaults/main.yml` for Prometheus Operator Settings

The Prometheus Operator Settings are in variable namespace `install.prometheus_operator`.

* Enable or disable installation of Longhorn Distributed storage:

  ```yml
    prometheus_operator:
      install_this: true              # Install Prometheus Operator
  ```

* The name space and release name Helm will use to install Longhorn:

  ```yml
      namespace: "monitoring"
      release: "kube-stack-prometheus"
  ```

* Define the version of Kube Promethus Stack to install. Available releases to use:  [https://github.com/prometheus-community/helm-charts/releases](https://github.com/prometheus-community/helm-charts/releases)

  ```yml
      install_version: "34.7.1"
  ```

---

## Review `defaults/main.yml` for Prometheus Settings

Prometheus Specific Settings are in variable namespace `install.prometheus_operator.prometheus`.

* Define how long data should be retained.

  ```yml
      prometheus:
        retention: "7d"                 # How long to retain data
  ```

* Define the type of Persistent Volume Storage Claim to use and its size.  The `class_name` can be `freenas-iscsi-csi`, `freenas-nfs-csi`, or `longhorn` to use the provided storage classes.

  ```yml
        storage_claim:                  # Define where and how data is stored
          access_mode: "ReadWriteOnce"
          class_name: "freenas-iscsi-csi"
          claim_size: 20Gi
  ```

* Settings for the Prometheus Web Interface. The `create_route` will create a Traefik Ingress route to expose the web interface on the URI defined in `path`.

  ```yml
        # Prometheus Web Interface
        dashboard:
          create_route: true           # Create Ingress Route to make accessible 
          enable_basic_auth: true      # Require Authentication to access dashboard

          # Default Dashboard URL:  https://k3s.{{ansible_domain}}/prometheus/
          hostname: "k3s.{{ansible_domain}}"    # Domain for ingress route
          path: "/prometheus"            # URI Path for Ingress Route

          # Encoded users and passwords for basic authentication
          allowed_users: "{{prometheus_operator.prometheus.dashboard_users}}"
  ```

* The `hostname` should reference the DNS which points to the Traefik Load Balancer IP address used for all Traefik ingress routes.
* The `allowed_users` maps to which users are allowed to access the Prometheus Web Interface.

The Prometheus Web Interface URL path will resemble: `https://k3s.example.com/prometheus/`

![Prometheus Web Interface](../images/prometheus_web_interface.png)

* By default basic authentication for the Prometheus Web Interface is enabled.  Individual users allowed to access the dashboard are defined in `var/secrets/prometheus_dashboard_secrets.yml` as follows:

```yaml
# Define encoded Prometheus Operator users allowed to use the Prometheus Web Interface (if enabled)
# Multiple users can be listed below, one per line (indented by 2 spaces)
# Created with "htpasswd" utility and then base64 encode that output such as:
# $ htpasswd -nb [user] [password] | base64

# Example of unique users from other dashboards:
# PROMETHEUS_DASHBOARD_USERS: |
#  dHJhZWZpa2FkbTokMnkkMTAkbHl3NWdYcXpvbFJCOUY4M0RHa2dMZW52YWJTcmpxUk9XbXNGUmZKa2ZQSlhBbzNDSmJHY08K

# Use same users currently defined by Traefik dashboard:
# NOTE: They do not share a common K8s secret. This will place the same information in two different
#       secrets.
PROMETHEUS_DASHBOARD_USERS: "{{TRAEFIK_DASHBOARD_USERS}}"
```

NOTE: by default, any users defined in the Traefik Dashboard allowed user list is allowed to log into the Prometheus Web Interface.

* If you need to restrict access to the Prometheus Web Interface to different set of users or require different passwords, then update the file as needed.
* As stated in the comments this is not a shared Kubernetes secrets with Traefik. Once deployed a change in one will not be reflected in the other.  This is just to make initial setup easier.

---

## Review `defaults/main.yml` for Grafana Settings

* Define the type of Persistent Volume Storage Claim to use and its size.  The `class_name` can be `freenas-iscsi-csi`, `freenas-nfs-csi`, or `longhorn` to use the provided storage classes.

  ```yml
        storage_claim:                  # Define where and how data is stored
          access_mode: "ReadWriteOnce"
          class_name: "freenas-iscsi-csi"
          claim_size: 10Gi
  ```

* Settings for the Grafana Dashboard. The `create_route` will create a Traefik Ingress route to expose the Grafana Dashboard on the URI defined in `path`.

  ```yml
        # Grafana Dashboard
        dashboard:
          create_route: true           # Create Ingress Route to make accessible 
          enable_basic_auth: false      # Require Authentication to access dashboard

          # Default Dashboard URL:  https://k3s.{{ansible_domain}}/prometheus/
          hostname: "k3s.{{ansible_domain}}"    # Domain for ingress route
          path: "/prometheus"            # URI Path for Ingress Route

  ```

* The `hostname` should reference the DNS which points to the Traefik Load Balancer IP address used for all Traefik ingress routes.
* The `enable_basic_auth` is set to false as Grafana already requires its own authentication by default.

To extract the default ID & Password for Grafana Dashboard from the secrets:

```shell
$ kubectl get secret --namespace monitoring kube-stack-prometheus-grafana -o jsonpath='{.data.admin-user}' | base64 -d ;echo
admin

$ kubectl get secret --namespace monitoring kube-stack-prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
prom-operator
```

* Above shows the default may be ID: `admin` and Password: `prom-operator`.

The Grafana Dashboard URL path will resemble: `https://k3s.example.com/grafana/`

![Grafana Dashboard](../images/grafana_dashboard.png)

[Back to README.md](../README.md)
