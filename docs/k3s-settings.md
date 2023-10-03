# K3S Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* The `containerd` included within `k3s` does not have native support for ZFS file system. Attempting to use `k3s` wih ZFS will produce `overlayfs` error message in the system logs and not function correctly.
  * See: [https://github.com/k3s-io/k3s/discussions/3980](https://github.com/k3s-io/k3s/discussions/3980)
* To get around this ZFS compatibility issue, this process will create a ZFS ZVOL mounted at `/var/lib/racher` formatted for XFS (ext4 could be used).
  * Being backed by ZFS, this mount still enjoys the benefits of ZFS (mirrors, compression, encryption, etc) while not being formatted as ZFS to allow compatibility with K3s embedded containerd.

## Review `defaults/main.yml` for K3S Settings

There should not be a need to update any settings for K3S. The K3s Settings are in variable namespace `install.k3s`.

### CLI Installation Options

CLI parameters passed to the K3s installation script can be customized by updating the section below.

```yml
install:
  k3s:
    # CLI options passed directly to install script "as-is":
    cli_options:
      # Do not start service after installation as it will have issues with ZFS
      - "INSTALL_K3S_SKIP_START=true"
      
      # This is to pin a specific version of k3s for initial installation
      - "INSTALL_K3S_VERSION=v1.25.6+k3s1"
      
      # Select installation channel to use (stable, latest, testing)
      #- "INSTALL_K3S_CHANNEL=stable"

    k3s_cli_var:
      - "--disable traefik"                   # Install a stable Traefik via helm instead
      - "--kube-apiserver-arg=feature-gates=MixedProtocolLBService=true"  # Allow Load Balancer to use TCP & UDP Ports
```

| Variable Name | Default   | Description |
|---            |---        |---          |
|`INSTALL_K3S_SKIP_START` |`true`  |Prevents K3s from starting after installation. It can not be started until the new containerd with ZFS support configuration is completed.|
|`INSTALL_K3S_VERSION`    |`v1.25.6+k3s1`  | Lets you pin a specific version to use.  This will make sure a standardized version is used even with different installs over time.  Only you determine which version to use.|
|`INSTALL_K3S_CHANNEL`    |Not set | Sets the installation channel to use. It can be set to `stable`, `latest` or `testing`. You probably do not want this as it will result in different versions being installed over time. |
|`k3s_cli_var`            |Multiple values |Allows additional configuration variables to be set.|
| |`--disable traefik`  | Disable the K3s embedded Traefik installation, instead a dedicated Traefik will be installed via ArgoCD as a DaemonSet.|
| |`--kube-apiserver-arg=feature-gates=MixedProtocolLBService=true` |Enabled a Kubernetes feature disabled by default to allow LoadBalancers to support TCP and UDP ports on the Service.|
  
* You can add more entries to the `k3s_cli_var` list needed.  See [Installation Options for Scripts](https://rancher.com/docs/k3s/latest/en/installation/install-options/) in Rancher documentation for details.

---

### ZFS ZVOL for K3s Installation

This sections defines how the ZFS ZVOL to be mounted at `/var/lib/rancher` will be created:

```yaml
install:
  k3s:

    zfs:
      pool: "{{ k3s_pool | default('rpool') }}"
      zvol:
        format: "xfs"
        options:
          volsize: "{{ k3s_vol_size | default('35G') }}"
          compression: "lz4"       # "" (inherit), lz4, gzip-9, etc
          volblocksize: "16k"
          sync: "always"
```

| Variable Name | Default   | Description |
|---            |---        |---          |
|`zfs.pool` |'rpool'  |Defines the name of the **existing** pool where the ZVOL should be created.|
|`zfs.zvol.format`  |`xfs`  |Defines the filesystem format to use for the ZVOL.

* XFS has been tested and works well (easy to expand volume if needed).
* XFS is set to use 4KB block-size and 4KB sector-size
* This can be changed to `ext4` or some other K3s compatible filesystem if needed.

| Variable Name | Default   | Description |
|---            |---        |---          |
|`zfs.zvol.options.volsize` |`35G`  | Defines how large the ZVOL should be.

* 35GB is a reasonable starting point. Clusters with a high-density of containers will likely need to increase this.
* This ZVOL is not thin-provisioned. ZFS will take a minimum of this amount of space immediately from the ZFS pool (plus whatever overhead ZFS needs).

| Variable Name | Default   | Description |
|---            |---        |---          |
|`zfs.zvol.options.compression` |  `lz4` |Defines the underlying ZFS compression method to be applied.|
|`zfs.zvol.options.volblocksize`  |`16k`  |Defines the block size the ZVOL should use.|

* A value of `16k` has proved effective in testing for the types of files that K3s will store.
* Do not go smaller than `16K`, but a larger value such as `32K` could be worth testing in your environment.

| Variable Name | Default   | Description |
|---            |---        |---          |
|`zfs.zvol.options.sync`  |`always` |Defines how synchronous writes will be handled by ZFS.|

* ZVOLs should be set to `sync` `always` to reduce chances of filesystem corruption of the embedded XFS filesystem. Otherwise up to the last 5 seconds of writes can be lost should the system hang/freeze.

| Variable Name | Default   | Description |
|---            |---        |---          |
|`zfs.zvol.encryption`  |`false`  |Is a boolean value to determine if the ZVOL should be created with ZFS native encryption enabled.|
|`zfs.zvol.encryption_options.encryption` |`aes-256-gcm`  | Encryption algorithm to use|
|`zfs.zvol.encryption_options.keyformat`  |`passphrase` | Can be `passphrase`, `hex`, or `raw`. |
|`zfs.zvol.encryption_options.keylocation`|`file:///etc/zfs/zroot.key`  | Can be `prompt` or a path to an existing key file. |

* When `keylocation` is a path to an existing key file, the file should be `chown root:root` with `chmod 000` and stored on an encrypted dataset.

---

### Kubernetes Command Aliases

It can be annoying typing `kubectl` all day.  An alias lets you assign an alternate name to a command.  

```yaml
install:
  k3s:

     # Define handy alias names for commands
    alias:
      enabled: true
     entries:
        # alias for kubectl  ($ k get all -A)
        - { alias_name: "k", command: "kubectl" }   
        # alias for a pod to run curl against other pods
        - { alias_name: "kcurl", command: "kubectl run curl --image=radial/busyboxplus:curl --rm=true --stdin=true --tty=true --restart=Never" }
        # Alias for Kubeseal to include controller name by default
        - { alias_name: "kubeseal", command: "kubeseal --controller-name {{ sealed_secrets.controller_name }}" }

```

By default `k` will be setup as an alias for `kubectl`:

```shell
$ k version --short

Client Version: v1.25.3+k3s1
Kustomize Version: v4.5.7
Server Version: v1.25.3+k3s1
```

The `kcurl` will create a pod to run the `curl`, `ping`, `wget`, etc. commands against other pods.  Handy for troubleshooting pod networking.

```shell
$ nslookup cert-manager.cert-manager
Server:    10.43.0.10
Address 1: 10.43.0.10 kube-dns.kube-system.svc.cluster.local

Name:      cert-manager.cert-manager
Address 1: 10.43.48.136 cert-manager.cert-manager.svc.cluster.local

$ curl http://cert-manager.cert-manager:9402/metrics
# HELP certmanager_certificate_expiration_timestamp_seconds The date after which the certificate expires. Expressed as a Unix Epoch Time.
# TYPE certmanager_certificate_expiration_timestamp_seconds gauge
certmanager_certificate_expiration_timestamp_seconds{name="wildcard-cert",namespace="traefik"} 1.66074062e+09
...
certmanager_controller_sync_call_count{controller="certificates-trigger"} 1
certmanager_controller_sync_call_count{controller="clusterissuers"} 2
certmanager_controller_sync_call_count{controller="orders"} 1
```

* If you want something like `kga` to be an alias for `kubectl get all --all-namespaces` this is where you can define that. Be as creative as you want.
* To apply new aliases to cluster nodes, just run the K3S Validation Step documented below to push out changes.

---

### K3S Validation Step

This Ansible script will confirm k3s is up and running at end of its installation. If any configuration issues exist between k3s, ZVOL mount, etc. then k3s will not be able to deploy properly to reach a "Ready" state. This script will check if `kubectl get node` returns `No resources found` indicating a configuration issue.  If this is detected, the install will fail at this point to allow troubleshooting.

It can be run independently on its own:

```shell
$ ansible-playbook -i inventory kubernetes.yml --tags="validate_k3s"

  MSG:

  NAME        STATUS   ROLES                       AGE   VERSION
  testlinux   Ready    control-plane,etcd,master   18h   v1.25.6+k3s1
```

---

[Back to README.md](../README.md)
