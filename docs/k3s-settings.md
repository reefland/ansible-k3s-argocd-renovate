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

CLI parameters passed to the K3s installation script can be customized by updating the section below. By default it will install whatever is considered `latest`. You can pin a specific version using the variable below.  See [Installation Options for Scripts](https://rancher.com/docs/k3s/latest/en/installation/install-options/) in Rancher documentation for details.

```yml
k3s:
  # CLI options passed directly to install script "as-is":
  cli_options:
    # Do not start service after installation as it will have issues with ZFS
    - INSTALL_K3S_SKIP_START=true
    # This is to pin a specific version of k3s for initial installation
    # - INSTALL_K3S_VERSION=
    # Select installation channel to use (stable, latest, testing)
    - INSTALL_K3S_CHANNEL="latest"
    # Send Flags to K3s Service
    - INSTALL_K3S_EXEC="--container-runtime-endpoint unix:///run/containerd/containerd.sock"
```

### K3S Validation Step

Confirm k3s is up and running at end of its installation. If any configuration issues exist between k3s, containerd and container network plugs then k3s will not be able to deploy properly to reach a "Ready" state. This script by default will check if `kubectl get node` returns `No resources found` indicating a configuration issue.  If this is detected, the install will fail at this point to allow troubleshooting.

```yml
k3s:
  # If enabled, will fail ansible deployment when "kubectl get node" returns "No resources found"
  confirm_running: true
```

When enabled, it can be run independently on its own:

```shell
$ ansible-playbook -i inventory kubernetes.yml --tags="validate_k3s"

  MSG:

  NAME        STATUS   ROLES                  AGE   VERSION
  testlinux   Ready    control-plane,master   64m   v1.23.3+k3s1
```

[Back to README.md](../README.md)
