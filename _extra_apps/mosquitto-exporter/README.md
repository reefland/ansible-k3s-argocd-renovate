# Mosquitto-Exporter Mosquitto Prometheus Service Monitor

Mosquitto-Exporter exposes Mosquitto MQTT Broker Metrics as Prometheus Service Monitor.

[Return to Application List](../)

* Kustomize based ArgoCD application deployment
* Deployed as a Deployment with configMapGenerator and secretGenerator

Review `mosquitto-exporter/kustomization.yaml`

* Set the initial image version

```yaml
images:
  - name: sapcc/mosquitto-exporter
    newTag: 0.8.0
```

* Set MQTT Username and password (not base64 encoded)

  * OPTION 1 - You can uncomment and define the secrets within `mosquitto-exporter/kustomization.yaml` however, if you plan to add this file to ArgoCD or a code repository such as git this is not recommended instead see other options below.

    ```yaml
    # Don't base64 encode secret values here
    #secretGenerator:
    #- name: node-exporter-secret
    #  literals:
    #  - mqtt-user=<USERNAME_HERE>
    #  - mqtt-pass=<PASSWORD_HERE>
    ```

  * OPTION 2 - You can create a secrets file directly and apply this to the cluster to prevent your secret from being committed to the repository:

    ```shell
    $ kubectl -n mosquitto create secret generic node-exporter-secret \
      --from-literal=mqtt-user=<USERNAME_HERE> \
      --from-literal=mqtt-pass=<PASSWORD_HERE> \
      --dry-run=client -o yaml > node-exporter-secret.yaml

      # No output expected
    ```

    Manually apply secret to cluster:

    ```shell
    $ kubectl create -f node-exporter-secret.yaml 
    secret/node-exporter-secret created
    ```

  * OPTION 3 - Convert secret created above into a Sealed Secret which is safe for code repository and ArgoCD:

    ```shell
    $ kubeseal --controller-namespace=sealed-secrets --format=yaml < node-exporter-secret.yaml > node-exporter-secret-sealed.yaml

    # No output expected
    ```

    This sealed secret can be added to your code repository the way you handle your other sealed secrets or applied directly.

* Set namespace where Prometheus is located
* Set the Prometheus Auto-Discovery label used

```yaml
# Set namespace where Prometheus is located
# Set label Prometheus uses for ServiceMonitor auto-discovery
patches:
- patch: |-
    - op: replace
      path: /metadata/namespace
      value: monitoring
    - op: replace
      path: /metadata/labels/release
      value: kube-stack-prometheus
  target:
    kind: ServiceMonitor
```

Review `mosquitto-exporter/applications/mosquitto-exporter.yaml`

* Set `repoURL` source to the path of your dedicated ArgoCD repository

```yaml
  source:
    repoURL:  https://github.com/<USER_NAME>/<REPO_NAME>.git
    targetRevision: HEAD
    path: workloads/mosquitto-exporter
```

---

Grafana Dashboard for Mosquitto MQTT: `11542`

This will be automatically installed as a configMap Dashboard for Grafana as part of the Mosquitto Exporter deployment.

![Grafana Dashboard using exporter](grafana_dashboard_11542.png)

[Return to Application List](../)
