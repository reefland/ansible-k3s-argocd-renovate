# K3S Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* `k3s` does not have native support for ZFS file system, it will produce `overlayfs` error message.
  * See: [https://github.com/k3s-io/k3s/discussions/3980](https://github.com/k3s-io/k3s/discussions/3980)
* To get around this ZFS issue, this will also install `containerd` and `container network plugins` packages and configure them to support ZFS. The k3s configuration is then updated to use containerd.
  * Based on: [https://blog.nobugware.com/post/2019/k3s-containterd-zfs/](https://blog.nobugware.com/post/2019/k3s-containterd-zfs/)

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
      - "INSTALL_K3S_VERSION=v1.23.4+k3s1"
      
      # Select installation channel to use (stable, latest, testing)
      #- "INSTALL_K3S_CHANNEL=stable"

    k3s_cli_var:
      - "--disable traefik"                   # Install a stable Traefik via helm instead
      - "--kube-apiserver-arg=feature-gates=MixedProtocolLBService=true"  # Allow Load Balancer to use TCP & UDP Ports
```

* The `INSTALL_K3S_SKIP_START` prevents K3s from starting after installation. It can not be started until contrainerd configuration is completed.

* The `INSTALL_K3S_VERSION` lets you pin a specific version to use.  This will make sure a standardized version is used even with different installs over time.  Only you determine which version to use.

* The `INSTALL_K3S_CHANNEL` sets the installation channel to use. It can be set to `stable`, `latest` or `testing`. You probably do not want this as it will result in different versions being installed over time.

* The `k3s_cli_var` allows additional configuration variables to be set.
  * `--disable traefik` disabled the K3s embedded Traefik installation, as a dedicated Traefik is installed via Helm Chart as a DaemonSet.
  * `--kube-apiserver-arg=feature-gates=MixedProtocolLBService=true` enabled a Kubernetes feature disabled by default to allow LoadBalancers to support TCP and UDP ports on the Service.
  
You can add to this CLI last as needed.  See [Installation Options for Scripts](https://rancher.com/docs/k3s/latest/en/installation/install-options/) in Rancher documentation for details.

---

### Kubernetes Command Aliases

It can be annoying typing `kubectl` all day.  And alias lets you assign an alternate name to a command.  

```yaml
install:
  k3s:

     # Define handy alias names for commands
    alias:
      enabled: true
      entries:
        - { alias_name: "k", command: "kubectl" }   # alias for kubectl  ($ k get all -A)


```

By default `k` will be setup as an alias for `kubectl`:

```shell
$ k version

Client Version: version.Info{Major:"1", Minor:"23", GitVersion:"v1.23.5+k3s1", GitCommit:"313aaca547f030752788dce696fdf8c9568bc035", GitTreeState:"clean", BuildDate:"2022-03-31T01:02:40Z", GoVersion:"go1.17.5", Compiler:"gc", Platform:"linux/amd64"}
Server Version: version.Info{Major:"1", Minor:"23", GitVersion:"v1.23.5+k3s1", GitCommit:"313aaca547f030752788dce696fdf8c9568bc035", GitTreeState:"clean", BuildDate:"2022-03-31T01:02:40Z", GoVersion:"go1.17.5", Compiler:"gc", Platform:"linux/amd64"}
```

* If you want something like `kga` to be an alias for `kubectl get all --all-namespaces` this is where you can define that. Be as creative as you want.

---

### K3S Validation Step

This Ansible script will confirm k3s is up and running at end of its installation. If any configuration issues exist between k3s, containerd and container network plugs then k3s will not be able to deploy properly to reach a "Ready" state. This script will check if `kubectl get node` returns `No resources found` indicating a configuration issue.  If this is detected, the install will fail at this point to allow troubleshooting.

It can be run independently on its own:

```shell
$ ansible-playbook -i inventory kubernetes.yml --tags="validate_k3s"

  MSG:

  NAME        STATUS   ROLES                       AGE   VERSION
  testlinux   Ready    control-plane,etcd,master   18h   v1.23.5+k3s1
```

---

[Back to README.md](../README.md)
