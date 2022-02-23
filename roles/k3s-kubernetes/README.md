# K3s Kubernetes with ContainerD for ZFS

Automated 'K3s Lightweight Distribution of Kubernetes' deployment with many enhancements:

* non-root user account for Kubernetes, passwordless access to `kubectl` by default.
* condainerd to provide zfs snapshotter support
* Helm Client
* Cert Manager

## Notes

* `k3s` does not have native support for ZFS file system, it will produce `overlayfs` error message. 
  * See: https://github.com/k3s-io/k3s/discussions/3980
* To get around this ZFS issue, this will also install `containerd` and `container network plugins` packages and configure them to support ZFS. The k3s configuration is then updated to use containerd. 
  * Based on: https://blog.nobugware.com/post/2019/k3s-containterd-zfs/

## Environments Tested

* Ubuntu 20.04 based [ZFS on Root](https://gitea.rich-durso.us/reefland/ansible/src/branch/master/roles/zfs_on_root) installation.

---

## Packages Installed

* python3-pip (required for Ansible managed nodes)
* pip packages - openshift, pyyaml, kubernetes (required for Ansible to execute K8s module)
* k3s (Runs official script https://get.k3s.io)
* containerd, containernetworking-plugins, iptables
* helm, apt-transport-https (required for helm client install)

---

## Edit `kubernetes.yml` to define the defaults

1. Review the non-root user account that will be created for Kubernetes with optional passwordless access to `kubectl` command.

    ```yml
    os:
      non_root_user:
        name: "kube"
        shell: "/bin/bash"
        groups: "sudo"

      allow_passwordless_sudo: true
    ```

2. CLI parameters passed to the K3s installation script can be customized by updating the section below. By default it will install whatever is considered `latest`. You can pin a specific version using the variable below.  See [Installation Options for Scripts](https://rancher.com/docs/k3s/latest/en/installation/install-options/) in Rancher documentation for details.

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

3. Confirm k3s is up and running at end of its installation. If any configuration issues exist between k3s, containerd and container network plugs then k3s will not be able to deploy properly to reach a "Ready" state. This script by default will check if `kubectl get node` returns `No resources found` indicating a configuration issue.  If this is detected, the install will fail at this point to allow troubleshooting.

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

4. Define the ZFS dataset to be created for containerd ZFS snapshotter support.  NOTE that Ubuntu's `zsys` system snapshot creator does _not_ play nicely with containerd. The ZFS dataset should be created outside of `zsys` monitoring view. The following is a reasonable ZFS dataset configuration:

    ```yml
    containerd:
      zfs:
        detect_uuid: false
        pool: "rpool"
        dataset_prefix: "containerd"
        uuid: ""
        dataset_postfix: ""
    ```

    For future reference when Ubuntu's `zsys` system snapshot creator supports disabling snapshots for specific datasets (this one) then the following would be designed for Ubuntu 20.04 based [ZFS on Root](https://gitea.rich-durso.us/reefland/ansible/src/branch/master/roles/zfs_on_root) installation where UUIDs are used in the dataset name.

    ```yml
    zfs:
      detect_uuid: true
      pool: "rpool"
      dataset_prefix: "ROOT/ubuntu"
      uuid: "_"
      dataset_postfix: "/var/lib/containerd"
    ```

    * `detect_uuid: true` will determine the UUID name used for the dataset name and append it to the end of `uuid: "_"`.  
      * The ZFS on Root guide uses a random set of six characters (UUID) in the naming convention of zfs datasets such as: `rpool/ROOT/ubuntu_3wgs2q` where `3wgs2q` is the UUID to detect.
      * You can set `detect_uuid: false` and set your own `uuid: "_"` value or set `uuid: ""` to not use anything.
      * Expected result would be a dataset name such as: `rpool/ROOT/ubuntu_3wgs2q/var/lib/containerd` being created.
        * The mountpoint of the dataset does not need to be changed, but is defined in `vars/containerd.yml`.

5. Some containerd configuration locations can be adjusted if needed, but the default values should be fine.

    ```yml
    containerd:
      # Location generate config.toml file
      config_path: "/etc/containerd"

      # Location to place flannel.conflist
      flannel_conflist_path: "/etc/cni/net.d"
    ```

6. Define the version of Cert Manager to be installed. Available version number can be found [here](https://artifacthub.io/packages/helm/cert-manager/cert-manager).

    ```yml
    cert_manager:
      install_version: "v1.7.1"

    ```

---

## How do I Run it

### Edit your inventory document

K3s Kubernetes with ContainerD playbook uses the following group:

```ini
[k8s_group:vars]
ansible_user=ansible
ansible_ssh_private_key_file=/home/rich/.ssh/ansible
ansible_python_interpreter=/usr/bin/python3

[k8s_group]
testlinux.example.com
```

### Fire-up the Ansible Playbook

The most basic way to deploy K3s Kubernetes with ContainerD:

```bash
ansible-playbook -i inventory kubernetes.yml
```

To limit execution to a single machine:

```bash
ansible-playbook -i inventory kubernetes.yml -l testlinux.example.com
```

---
