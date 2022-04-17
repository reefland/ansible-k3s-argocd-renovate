# K3s Kubernetes with ContainerD for ZFS

An Ansible playbook to provide automated 'K3s Lightweight Distribution of Kubernetes' deployment with many enhancements:

* **non-root** user account for Kubernetes, passwordless access to `kubectl` by default.
* [condainerd](https://containerd.io/) to provide [ZFS snapshotter](https://github.com/containerd/zfs) support
* **Centralized cluster system logging** via [rsyslog](https://www.rsyslog.com/) with real-time viewing with [lnav](https://lnav.org/) utility.
* [Helm Client](https://helm.sh/docs/intro/using_helm/)
* [Cert-manager](https://cert-manager.io/)
* [kube-vip](https://kube-vip.chipzoller.dev/) for Kubernetes API Load Balancer (point kubectl to this instead of a specific host)
* [MetalLB](https://metallb.universe.tf/) OR [kube-vip](https://kube-vip.chipzoller.dev/) Load Balancer to replace [K3s Klipper](https://github.com/k3s-io/klipper-lb) Load Balancer for ingress traffic.
* [Traefik](https://traefik.io/) ingress with [Let's Encrypt](https://letsencrypt.org/) **wildcard certificates** for domains against Let's Encrypt staging or prod (Cloudflare DNS validator)
* [democratic-csi](https://github.com/democratic-csi/democratic-csi) to provide [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) storage via **iSCSI** and **NFS** from [TrueNAS](https://www.truenas.com/)
* [Longhorn](https://longhorn.io/) distributed [Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/) as default storage class
* Optional [Kube Prometheus Stack](https://github.com/prometheus-operator/kube-prometheus) provides [Prometheus](https://prometheus.io/), [Alertmanager](https://github.com/prometheus/alertmanager), [node-exporter](https://github.com/prometheus/node_exporter), [Kubernetes API Adapter](https://github.com/DirectXMan12/k8s-prometheus-adapter), [Kube State Metrics](https://github.com/kubernetes/kube-state-metrics) and [Grafana](https://grafana.com/) Dashboards can be deployed with customized persistent storage claims.

---

## TL;DR

* You should read it. :)
* The **democratic-csi** section will require configuration steps on your TrueNAS installation in addition to setting values in Ansible.
* **Kube-vip** and/or **MetalLB** Load Balancer section will require you to specify a range of IP addresses available for use
* **Traefik** configuration for Lets Encrypt will require you to define your challenge credentials.
* **Longhorn** Distributed storage is intended to be the default storage class, the `local-path` StorageClass is not installed.

---

## Environments Tested

* Ubuntu 20.04.4 based [ZFS on Root](https://github.com/reefland/ansible-zfs_on_root) installation
* TrueNAS Core 12-U8
* K3s v1.23.3 / v1.23.4+k3s1 / v1.23.5+k3s1

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
I provide a lot of documentation notes below for my own use.  If you find it overwhelming, keep in mind most of it you do not need.  Also note that towards the bottom is a section which shows how to use Ansible to run this in stages (step by step) to built it up in layers using `tags`.

---

## Review `defaults/main.yml` for initial settings

* Review [Linux OS Settings](docs/os-settings.md)
* Review [Centralized Cluster System Logs Settings](docs/rsyslog-settings.md)
* Review [K3S Configuration Settings](docs/k3s-settings.md)
* Review [Containerd Configuration Settings](docs/containerd-settings.md)
* Review [Longhorn Distributed Storage Settings](docs/longhorn-settings.md)
* Review [Kube-vip API Load Balancer Settings](docs/kube-vip-settings.md)
* Review [MetalLB Load Balancer Settings](docs/metallb-settings.md)
* Review [CertManager Configuration Settings](docs/cert-manager.md)
* Review [Traefik LetsEncrypt and Dashboard Settings](docs/traefik-settings.md)
* Review [democratic-csi for TrueNAS Settings](docs/democratic-csi-settings.md)
* Review [Prometheus Operator with Grafana Settings](docs/prometheus-op-settings.md)

---

## How do I Run it

### Edit your inventory document

Define a group for this playbook to use in your inventory, I like to use YAML format:

```yaml
  k3s_control:
    hosts:
      k3s01.example.com:                        # Master #1
        vip_interface: "enp0s3"
        vip_endpoint_ip: "192.168.10.220"
        vip_lb_ip_range: "cidr-global: 192.168.10.221/30"   # 4 Addresses
        longhorn_zfs_pool: "tank"
        longhorn_vol_size: "10G"
      k3s02.example.com:                        # Master #2
        vip_interface: "enp01sf0"
        longhorn_zfs_pool: "tank"             
      k3s03.example.com:
        vip_interface: "enp01sf0"
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
      k3s_install_version: "v1.23.5+k3s1"
      kube_vip_install_version: "v0.4.2"
      metallb_install_version: "v0.12.1"
      longhorn_install_version: "v1.2.4"
      cert_manager_install_version: "v1.7.1"
      prometheus_op_install_version: "34.7.1"
      k3s_cluster_ingress_name: "k3s-test.{{ansible_domain}}"

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

---

#### Inventory Variables for IP & Load Balancers

For simplicity I show the variables within the inventory file.  You can place these in respective group vars and host vars files.  

* `vip_interface` specifies which network interface will be used for the Kubernetes API Load Balancer provided by kube-vip.  This can be specified for each individual host.
* `vip_endpoint_ip` specifies the IP address to be used for the Kubernetes API Load Balancer provided by Kube-vip
* `vip_lb_ip_range` defines the IP address range kube-vip can use to provide IP addresses for LoadBalancer services.
* `metallb_ip_range` does the equivalent of `vip_lb_ip_range` but for Metallb Load Balancer if you choose to use that instead.

---

#### Inventory Variables for Longhorn Distributed Storage

* `longhorn_zfs_pool` lets you define the ZFS pool to create Longhorn cluster storage with. It will use the ZFS pool `rpool` if not defined. This can be host specific or group scoped.

* `longhorn_vol_size` specifies how much storage space you wish to dedicate to Longhorn distributed storage. This can be host specific or group scoped.

---

#### Inventory Variables for K3s Installation

* `k3s_cluster_ingress_name` is the Fully Qualified Domain Name (FQDN) you plan to use for the cluster.  This will point to the Traefik Ingress controller's Load Balancer IP Address.  
  * If not provided it will default to `k3s` and the domain name of the Kubernetes Primary Master server... something like `k3s.localdomain` or `k3s.example.com`
  * All of the respective dashboards (Traefik, Longhorn, Prometheus, Grafana, etc) will be available from this FQDN.
* `k3s_cli_var` passes host specific variables to the K3s installation script.
* `k3s_labels` can be used to set labels on the cluster members.  This can be host specific or group scoped.
* `K3S_TOKEN` is a secret required for nodes to be able to join the cluster.  The value of the secret can be anything you like.  The variable needs to be scoped to the installation group.  
  * While it can be defined directly within the inventory file or group_var it better to create a variable named `K3S_TOKEN`in using Ansible's vault.
  * If you do not define this variable then the default `top_secret` which is lame will be used.
  * If you need inspiration for an easy to create a secret value:

  ```shell
  $ date | md5sum

  0097661c0c55ccc8921617e0997d2e73
  ```

---

#### Inventory Variables for Installed Versions

The idea behind pinning specific versions of software is so that an installation done on Monday can be identical when installed on Tuesday or Friday, or sometime next month.  Without pinning specific versions you have no way of knowing what random combination of versions you will get.

* `k3s_install_version` pins the K3s [Release](https://github.com/k3s-io/k3s/releases) version.
* `kube_vip_install_version` pins the kube-vip [Release](https://github.com/kube-vip/kube-vip/releases) version.
* `metallb_install_version` pins the Metallb [Release](https://github.com/metallb/metallb/releases) version.
* `longhorn_install_version` pins the Longhorn [Release](https://github.com/longhorn/longhorn/releases) version.
* `cert_manager_install_version` pins the Cert-manager [Release](https://github.com/cert-manager/cert-manager/releases) version.
* `prometheus_op_install_version` pins the Prometheus Operator [Chart](https://github.com/prometheus-community/helm-charts/releases) version.

---

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
* `create_non_root_user`
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
