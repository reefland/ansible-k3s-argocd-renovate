# Extra Applications

Applications listed here are NOT deployed via Ansible.  These are extra applications that I use or have used in the past.  

## To deploy with ArgoCD

1. Simply copy the directory structure of the application into your ArgoCD repository
2. Update the `.spec.source.repoURL` in `applications` directory to use your ArgoCD repository
3. Review `README.md` for the specific application changes to make (secrets, config, etc)
4. Commit the change

Within minutes ArgoCD will detect and deploy the application (and Renovate will monitor it for updates.)

---

## Directory Structure for ArgoCD

Each Application uses this directory structure:

* `applications` - Contains the ArgoCD application definition
  * Defines location and type (Helm, Kustomize, etc).
* `namespaces` - Contains a Namespace create manifest file
  * Name it after the actual namespace
  * If multiple applications use the same namespace only one file will actually exist (be overwritten on copy)
* `workloads` - This contains the application deployment files
  * Could be the Helm `Chart.yaml` and `values.yaml` files or Kustomize directory structure and files, or just standard Kubernetes manifest files.

---

## Application List

* [Custom-Alerts](./custom-alerts/) - Alerts for Prometheus Operator Alertmanager for:
  * Node Hardware, ArgoCD Sync Issues, Traefik Ingress Error codes
* [Goldilocks](./goldilocks/) - Uses [Vertical Pod Autoscaler (VPA)](./vpa/) to make recommendations on container limit and request recommendations, includes a dashboard.
* [Mosquitto](./mosquitto/) - Eclipse Mosquitto is a lightweight MQTT Message Broker
* [Mosquitto-Exporter](./mosquitto-exporter/) - Exposes Mosquitto MQTT Broker Metrics as Prometheus Service Monitor
* [Unifi Controller](./unifi-controller/) - Wireless Network Management Software from Ubiquiti
* [Unpoller-Exporter](./unpoller-exporter/) - Exposes [Unifi Controller](./unifi-controller/) Management Software Metrics as Prometheus Pod Monitor
* [Vertical Pod Autoscaler (VPA)](./vpa/) - Enables ability to make container resource limit and request recommendations, used with [Goldilocks](./goldilocks/)
