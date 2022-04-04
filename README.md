# K3s Kubernetes with ContainerD for ZFS

Automated 'K3s Lightweight Distribution of Kubernetes' deployment with many enhancements:

* **non-root** user account for Kubernetes, passwordless access to `kubectl` by default.
* **condainerd** to provide ZFS snapshotter support
* [Helm Client](https://helm.sh/docs/intro/using_helm/)
* [Cert-manager](https://cert-manager.io/)
* [MetalLB](https://metallb.universe.tf/) Load Balancer to replace K3s Klipper Load Balancer.
* **Traefik** ingress with **Letsencrypt wildcard certificates** for domains against LE staging or prod (Cloudflare DNS validator)
* [democratic-csi](https://github.com/democratic-csi/democratic-csi) to provide **Persistent Volume Claim** storage via **iSCSI** and **NFS** from TrueNAS
* [Longhorn](https://longhorn.io/) distributed Persistent Volume Claims as default storage class
* Optionally **Prometheus Operator** and **Grafana** can be deployed with customized storage claims
* Centralized cluster system logging via `rsyslog` with real-time viewing with [lnav](https://lnav.org/) utility.

---

## TL;DR

* You should read it. :)
* The **democratic-csi** section will require steps completed on your TrueNAS installation in addition to setting values in Ansible.
* MetalLB Load Balancer section will require you to specify a range of IP addresses available for use
* Traefik configuration for Lets Encrypt will require you to define your challenge credentials.
* Longhorn Distributed storage is intended to be the default storage class, the `local-path` StorageClass is not installed.

---

## Environments Tested

* Ubuntu 20.04.4 based [ZFS on Root](https://gitea.rich-durso.us/reefland/ansible-zfs_on_root) installation
* TrueNAS Core 12-U8
* K3s v1.23.3 / v1.23.4+k3s1

---

## Packages Installed

* [python3-pip](https://pypi.org/project/pip/) (required for Ansible managed nodes)
* pip packages - [OpenShift](https://pypi.org/project/openshift/), [pyyaml](https://pypi.org/project/PyYAML/), [kubernetes](https://pypi.org/project/kubernetes/) (required for Ansible to execute K8s module)
* k3s (Runs official script [https://get.k3s.io](https://get.k3s.io))
* [containerd](https://containerd.io/), container networking-plugins, iptables
* [helm](https://helm.sh/), [apt-transport-https](http://manpages.ubuntu.com/manpages/focal/man1/apt-transport-https.1.html) (required for helm client install)
* [open-iscsi](https://github.com/open-iscsi/open-iscsi), [lsscsi](http://sg.danny.cz/scsi/lsscsi.html), [sg3-utils](https://sg.danny.cz/sg/sg3_utils.html), [multipath-tools](https://github.com/opensvc/multipath-tools), [scsitools](https://packages.ubuntu.com/focal/scsitools-gui) (required by democratic-csi [when iSCSI support is enabled] and by Longhorn)
* [libnfs-utils](https://packages.ubuntu.com/focal/libnfs-utils) (required by democratic-csi when NFS support is enabled)
* [democratic-csi](https://github.com/democratic-csi/democratic-csi) implements the csi (container storage interface) spec providing storage from TrueNAS
* [Longhorn](https://longhorn.io/) provides native distributed block storage for Kubernetes cluster
* [lnav](https://lnav.org/) for view centralized cluster system logging

## Packages Uninstalled

* snapd (we have no use for it on Kubernetes nodes, saves resources)
  * This can be disabled if you really want to keep it.

  ```yml
  install:
    os:
      remove_snapd:                             # Remove Snapd Demon, we don't need it.
        remove_it: true
  ```

---
I provide a lot of documentation notes below for my own use.  If you find it overwhelming, keep in mind most of it you do not need to change.  Also note that towards the bottom is a section which shows how to use Ansible to run this in stages to built it up in layers using `tags`.

---

## Review `defaults/main.yml` for initial settings

Review the non-root user account that will be created for Kubernetes with optional passwordless access to `kubectl` command.

  ```yml
  install:
    os:
      non_root_user:
        name: "kube"
        shell: "/bin/bash"
        groups: "sudo"

      allow_passwordless_sudo: true
  ```

* Review [K3S Configuration Settings](docs/k3s-settings.md)
* Review [Containerd Configuration Settings](docs/containerd-settings.md)
* Review [MetalLB Load Balancer Settings](docs/metallb-settings.md)
* Review [Traefik LetsEncrypt and Dashboard Settings](docs/traefik-settings.md)
* Review [CertManager Configuration Settings](docs/cert-manager.md)
* Review [democratic-csi for TrueNAS Settings](docs/democratic-csi-settings.md)
* Review [Longhorn Distributed Storage Settings](docs/longhorn-settings.md)
* Review [Centralized Cluster System Logs Settings](docs/rsyslog-settings.md)
* Review [Prometheus Operator with Grafana Settings](docs/prometheus-op-settings.md)

---

## How do I Run it

### Edit your inventory document

Define a group for this playbook to use in your inventory, I like to use YAML format:

```yaml
  k3s_control:
    hosts:
      k3s01.example.com:                        # Master #1
        vip_interface: "enp1s0"
        longhorn_zfs_pool: "tank"
      k3s02.example.com:
        longhorn_zfs_pool: "tank"               # Master #2
      k3s03.example.com:
        longhorn_zfs_pool: "tank"               # Master #3 (add more if needed)
  k3s_workers:
    hosts:
      k3s-worker01.example.com:                # Worker #1
        vip_interface: "enp0s3"
#        k3s_cli_var: "K3S_URL='https://{{primary_server}}:6443'"
        k3s_labels: "{'kubernetes.io/role=worker', 'node-type=worker'}"

  k3s:
    children:
      k3s_control:
      k3s_workers:

    vars:
      K3S_TOKEN: 'secret_here'                  # Set to any value you like
```

* This inventory file divides hosts into Control nodes and Worker nodes:
  * Easily defines High Availability (HA) distributed etcd configuration.
  * The cluster will work fine with just a single node but for HA you should have 3 (or even 5) control nodes:

    | master nodes | must maintain | can lose | comment |
    |:------------:|:-------------:|:--------:|---------|
    |       1      |      1        |    0     | Loss of 1 is headless cluster |
    |       2      |      2        |    0     | Loss of 1 is headless cluster |
    |       3      |      2        |    1     | Allows loss of 1 master only  |
    |       4      |      3        |    1     | No advantage over using 3     |
    |       5      |      3        |    2     | Allows loss of 2 masters      |
    |       6      |      4        |    2     | No advantage over using 5     |
    |       7      |      4        |    3     | Allows loss of 3 masters      |

  * Kubernetes uses the [RAFT consensus algorithm](https://kubernetes.io/blog/2019/08/30/announcing-etcd-3-4/) for quorum for HA.
  * More then 7 master nodes will result in a overhead for determining cluster membership and quorum, it is not recommended. Depending on your needs, you typically end up with 3 or 5 master nodes for HA.
  
#### Inventory Variables

For simplicity I show the variables within the inventory file.  You can place these in respective group vars and host vars files.

* The `longhorn_zfs_pool` lets you define the ZFS pool to create Longhorn cluster storage with. It will use the ZFS pool `rpool` if not defined. This can be host specific or group scoped.
* The `k3s_cli_var` passes host specific variables to the K3s installation script. 
* The `k3s_labels` can be used to set labels on the cluster members.  This can be host specific or group scoped.
* The `K3S_TOKEN` is a secret value required for a node to be added to the cluster.  Better to define this in an Ansible secrets file or groups var file.

### Create a Playbook

Simple playbook I'm using for testing, named `kubernetes.yml`:

```yml
- name: k3s Kubernetes Installation & Configuration
  hosts: k3s
  become: true
  gather_facts: true

  roles:
    - role: k3s-kubernetes
```

### Fire-up the Ansible Playbook

The most basic way to deploy K3s Kubernetes with ContainerD:

```bash
ansible-playbook -i inventory.yml kubernetes.yml
```

To limit execution to a single machine:

```bash
ansible-playbook -i inventory.yml kubernetes.yml -l k3s01.example.com
```

## Build in Stages

Instead of running the entire playbook, you can run smaller logical steps using tags. Or use a tag to re-run a specific step you are troubleshooting.

```bash
ansible-playbook -i inventory.yml kubernetes.yml -l k3s01.example.com --tags="<tag_goes_here>"
```

The following tags are supported and should be used in this order:

* `config_rsyslog`
* `install_k3s`
* `install_containerd`
* `install_helm_client`
* `install_longhorn`
* `validate_k3s`
* `validate_longhorn`
* `install_kube_vip`
* `install_metallb`
* `install_cert_manager`
* `config_traefik_dns_certs`
* `config_traefik_dashboard`
* `install_democratic_csi_iscsi`
* `install_democratic_csi_nfs`
* `validate_csi_iscsi`
* `validate_csi_nfs`
* `install_prometheus_operator`

---

## Prometheus Operator with Grafana

These products are not installed by default, but can easily be deployed once everything above is functional.  This will install [Kube Prometheus Stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) project.

* **Prometheus Operator** extends the Kubernetes API, so that when we create some of the yaml deployments it will looks as if we’re telling Kubernetes to deploy something, but it’s actually telling Prometheus Operator to do it for us.
* **Prometheus** is the collector of metrics, it uses something called service monitors that provide information Prometheus can come and scrape. Prometheus will use persistent storage with a specified duration for how long it will keep the data. You can have more than one instance of Prometheus in your cluster collecting separate data.
  * An ingress route can be created to expose the Prometheus Web Interface.
* **Service Monitors** - are other containers/deployments. They can be considered middle steps between the data and Prometheus. This will deploy several service monitors needed to collect Kubernetes, Traefik ingress and underlying OS information per node.
* **Grafana** takes data from one or more Prometheus instances to combine them into a single dashboard.  Dashboards can be customized as you wish.

* Review [Prometheus Operator with Grafana Settings](docs/prometheus-op-settings.md)

### Installation

Prometheus Operator with Grafana cane be installed using the Ansible Tag:

```text
--tags="install_prometheus_operator"
```
