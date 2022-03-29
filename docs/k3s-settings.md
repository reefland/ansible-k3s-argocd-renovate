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
k3s:
  # CLI options passed directly to install script "as-is":
  cli_options:
      # Define it below or in the inventory file or group vars file.
      - "K3S_TOKEN={{K3S_TOKEN}}|default('top_secret')"

      # Do not start service after installation as it will have issues with ZFS
      - "INSTALL_K3S_SKIP_START=true"
      
      # This is to pin a specific version of k3s for initial installation
      - "INSTALL_K3S_VERSION=v1.23.4+k3s1"
      
      # Select installation channel to use (stable, latest, testing)
      #- "INSTALL_K3S_CHANNEL=stable"
```

* The `K3S_TOKEN=` is a secret required for nodes to be able to join the cluster.  The value of the secret can be anything you like.  The variable needs to be scoped to the installation group.  
  * While it can be defined directly within the `defaults/mains.yml` is better to create a variable named `K3S_TOKEN`in using Ansible's secrets file, or group vars file or an inventory file.
  * If you do not define this variable then the default `top_secret` which is lame will be used.
  * If you need inspiration for an easy to create a secret value:

  ```shell
  $ date | md5sum

  0097661c0c55ccc8921617e0997d2e73
  ```

* The `INSTALL_K3S_VERSION=` lets you pin a specific version to use.  This will make sure a standardized version is used even with different installs over time.  Only you determine which version to use.

* The `INSTALL_K3S_CHANNEL=` sets the installation channel to use. It can be set to `stable`, `latest` or `testing`. You probably do not want this as it will result in different versions being installed over time.

You can add to this CLI last as needed.  See [Installation Options for Scripts](https://rancher.com/docs/k3s/latest/en/installation/install-options/) in Rancher documentation for details.

### K3s Exec Options

These are CLI parameters which will be merged together to become the `INSTALL_K3S_EXEC=` installation parameter.  This list of values are used to configure the `k3s` systemd service. Depending on which products are enabled items will be added or removed from the final list.  You can add additional values to the `k3s_exec_options` list directly or just define a variable named `k3s_cli_var` scoped to the individual host using Ansible's host vars or inventory file.

```yml
    # Becomes the "INSTALL_K3S_EXEC=" parameter
    k3s_exec_options:  
      - "{{k3s_cli_var|default('')}}"         # Options set in inventory or hosts vars
      - "--container-runtime-endpoint unix:///run/containerd/containerd.sock"

    cli_disable_storage_options:              # If disable_local_path_as_default_storage_class = true
      - "--disable local-storage"   

    cli_disable_loadbalancer_options:         # If metallb.enabled = true
      - "--disable servicelb"
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
