# Unifi Controller Wireless Network Management Software from Ubiquiti

* Be sure to export a backup from your existing installation.  You will be able to import that backup into this installation.

[Return to Application List](../)

* Kustomize based ArgoCD application deployment
* Deployed as a Statefulset with a 5Gi Longhorn Persistent Storage Volume for data

Review `unifi-controller/kustomization.yaml`

* Set the initial image version
* Service type is `LoadBalancer` and specific IP Address can be defined

```yaml
images:
  - name: linuxserver/unifi-controller
    newTag: 7.1.65

patches:
  # Set Service to LoadBalancer and Specify IP Address to use
  - patch: |-
      - op: add
        path: /spec/type
        value: LoadBalancer
      - op: add
        path: /spec/loadBalancerIP
        value: 192.168.10.242
    target:
      kind: Service
```

* Set Fully Qualified Domain Name for Traefik Ingress Route.

```yaml
  # Set IngressRoute Match Value for Traefik
  # Remember to use ` (backtick) not ' (single quote) around Host
  - patch: |-
      - op: replace
        path: /spec/routes/0/match
        value: Host(`unifi.example.com`)
    target:
      kind: IngressRoute
```

* Set Longhorn Persistent Volume Claim storage size
  * Storage needs to be large enough to hold Unifi Controller own internal database, backups and historical data

```yaml
  # Set Longhorn Persistent Volume Claim Size
  - patch: |-
      - op: replace
        path: /spec/resources/requests/storage
        value: 5Gi
    target:
      kind: PersistentVolumeClaim
```

Review `unifi-controller/applications/unifi-controller.yaml`

* Set `repoURL` source to the path of your dedicated ArgoCD repository

```yaml
  source:
    repoURL:  https://github.com/<USER_NAME>/<REPO_NAME>.git
    targetRevision: HEAD
    path: workloads/unifi-controller
```

---

Note the Unifi Controller application can take several minutes to become ready.  Getting a `Bad Gateway` message after installation or upgrade is normal.  Monitor the container logs to see when it is ready, or just try again in a few minutes.

---
First time connecting should show this screen:
![Unifi Controller Initial Installation Wizard](unifi-controller-initial-install.png)

From here you can restore your configuration from a backup or start building your network from scratch.  

* NOTE if you had to change the name or IP Address of your controller to get it working on Kubernetes, then will need to use your existing (old) UniFi Controller to push a configuration change to all your devices to tell them to start reporting to your new controller.

One all the kinks are worked out, your network devices will start reporting in:

![Unifi Controller Console Screen Shot](unifi-controller-screenshot.png)

[Return to Application List](../)
