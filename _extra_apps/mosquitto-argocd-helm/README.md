# Eclipse Mosquitto lightweight MQTT Message Broker

[Return to Application List](../)

* Helm based ArgoCD application deployment
* Much simpler to configure than the Kustomize version
* Uses 100 MiB Persistent Volume Storage

Review file `mosquitto-argocd-helm/applications/mosquitto.yaml`

* Define the ArgoCD project to assign this application to
* ArgoCD uses `default` project by default

  ```yaml
  spec:
    project: default
  ```

* Service type is `LoadBalancer` and specific IP Address can be defined:

  ```yaml
    service:
      main:
        enabled: true
        ports:
          http:
            enabled: false
          mqtt:
            enabled: true
            port: 1883
        type: LoadBalancer
        loadBalancerIP: 192.168.10.222
  ```

* Define each username and password needed to authenticate with the broker
* Mosquitto uses `htpasswd` to only store a hash of the password, not the actual password
  * Password hashes are stored in a configMap as secret is not required
* Add one user per line as `userid`:`hashed password`

  ```yaml
  configmap:
    ...

    mosquitto-passwords:
      enabled: true
      data:
        passwd.txt: |
          mqtt-user:$6$ZLO-[EXAMPLE]-Qeow==
  ```

* Define Persistent Storage for MQTT Data

  ```yaml
  persistence:
    data:
      enabled: true
      mountPath: /mosquitto/data
      type: pvc
      accessMode: ReadWriteOnce
      size: 100Mi
      retain: true
      # existingClaim:
      # volumeName:
  ```

  * `existingClaim` and `volumeName` can be used to reused an existing PVC claim you may already have.

[Return to Application List](../)
