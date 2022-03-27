# K3s Kubernetes with ContainerD for ZFS

Automated 'K3s Lightweight Distribution of Kubernetes' deployment with many enhancements:

* **non-root** user account for Kubernetes, passwordless access to `kubectl` by default.
* **condainerd** to provide ZFS snapshotter support
* [Helm Client](https://helm.sh/docs/intro/using_helm/)
* [Cert-manager](https://cert-manager.io/)
* [MetalLB](https://metallb.universe.tf/) Load Balancer to replace K3s Klipper Load Balancer
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
* Longhorn Distributed storage is intended to be the default storage class, once installed the `local-path` StorageClass `default` flag will be removed.

---

## Environments Tested

* Ubuntu 20.04.4 based [ZFS on Root](https://gitea.rich-durso.us/reefland/ansible-zfs_on_root) installation
* TrueNAS Core 12-U8
* K3s v1.23.3

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

---

## How do I Run it

### Edit your inventory document

Define a group for this playbook to use in your inventory, I like to use YAML format:

```yaml
  k3s_control:
    hosts:
      testlinux01.example.com:
        longhorn_zfs_pool: "tank"
      testlinux02.example.com:
        longhorn_zfs_pool: "tank"

  k3s_workers:
    hosts:

  k3s:
    children:
      k3s_control:
      k3s_workers:

    vars:
      rsyslog_server: "testlinux01.example.com"
```

* NOTE: The playbook does not yet isolate or process tasks differently for Kubernetes control plane nodes and worker nodes.  This will be added in the future.
* The `rsyslog_server` variable defines the [centralized cluster system logging](docs/rsyslog-settings.md) host.

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
ansible-playbook -i inventory kubernetes.yml
```

To limit execution to a single machine:

```bash
ansible-playbook -i inventory kubernetes.yml -l testlinux.example.com
```

## Build in Stages

Instead of running the entire playbook, you can run smaller logical steps using tags. Or use a tag to re-run a specific step you are troubleshooting.

```bash
ansible-playbook -i inventory kubernetes.yml -l testlinux.example.com --tags="<tag_goes_here>"
```

The following tags are supported and should be used in this order:

* `install_k3s`
* `install_containerd`
* `validate_k3s`
* `install_helm_client`
* `install_cert_manager`
* `config_traefik_dns_certs`
* `config_traefik_dashboard`
* `install_democratic_csi_iscsi`
* `validate_csi_iscsi`
* `install_democratic_csi_nfs`
* `validate_csi_nfs`

---

## Troubleshooting CSI

### Shows pods deployed the the `democratic-csi` namespace

```shell
$ kubectl get pods -n democratic-csi -o wide

NAME                                                       READY   STATUS    RESTARTS   AGE   IP               NODE        NOMINATED NODE   READINESS GATES
truenas-iscsi-democratic-csi-controller-5fb94d4488-gglqt   4/4     Running   0          26h   10.42.0.99       testlinux   <none>           <none>
truenas-iscsi-democratic-csi-node-shwlb                    3/3     Running   0          26h   192.168.10.110   testlinux   <none>           <none>
truenas-nfs-democratic-csi-controller-5d8dc94bc-55wvs      4/4     Running   0          19h   10.42.0.112      testlinux   <none>           <none>
truenas-nfs-democratic-csi-node-794vb                      3/3     Running   0          19h   192.168.10.110   testlinux   <none>           <none>
```

### Show logs from the `csi-driver` container

Can be used to get detailed information during troubleshooting.  Adjust the pod for either the `nfs` or `iscsi` controller and adjust the random digits in the pod name to match your installation.

```shell
$ kubectl logs pod/truenas-nfs-democratic-csi-controller-5d8dc94bc-55wvs  csi-driver -n democratic-csi


{"level":"info","message":"new request - driver: FreeNASApiDriver method: CreateVolume call: {\"_events\":{},\"_eventsCount\":1,\"call\":{},\"cancelled\":false,\"metadata\":{\"_internal_repr\":{\"user-agent\":[\"grpc-go/1.40.0\"]},\"flags\":0},\"request\":{\"volume_capabilities\":[{\"access_mode\":{\"mode\":\"SINGLE_NODE_MULTI_WRITER\"},\"mount\":{\"mount_flags\":[\"noatime\",\"nfsvers=4\"],\"fs_type\":\"nfs\",\"volume_mount_group\":\"\"},\"access_type\":\"mount\"}],\"parameters\":{\"csi.storage.k8s.io/pv/name\":\"pvc-42688a22-3a62-4494-8488-ad6eeaeb4bc0\",\"fsType\":\"nfs\",\"csi.storage.k8s.io/pvc/name\":\"test-claim-nfs\",\"csi.storage.k8s.io/pvc/namespace\":\"democratic-csi\"},\"secrets\":\"redacted\",\"name\":\"pvc-42688a22-3a62-4494-8488-ad6eeaeb4bc0\",\"capacity_range\":{\"required_bytes\":\"1073741824\",\"limit_bytes\":\"0\"},\"volume_content_source\":null,\"accessibility_requirements\":null}}","service":"democratic-csi"}
{"level":"error","message":"handler error - driver: FreeNASApiDriver method: CreateVolume error: Error: {\"create_ancestors\":[{\"message\":\"Field was not expected\",\"errno\":22}]}","service":"democratic-csi"}
{
  code: 13,
  message: 'Error: {"create_ancestors":[{"message":"Field was not expected","errno":22}]}'
}
```

### Show Storage Claim Provisioners and Claim Policy

```shell
$ kubectl get sc

NAME                   PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path      Delete          WaitForFirstConsumer   false                  7d11h
freenas-iscsi-csi      org.democratic-csi.iscsi   Delete          Immediate              true                   40h
freenas-nfs-csi        org.democratic-csi.nfs     Delete          Immediate              true                   20h
```

---

### Experiment with Test Claims

Test claims for NFS and iSCSI are provided.  They can be used as-is or modified:

```shell
kube@testlinux:~/democratic-csi$ ls -l test*
-rw-rw---- 1 kube kube 287 Mar  1 16:50 test-claim-iscsi.yaml
-rw-rw---- 1 kube kube 280 Mar  2 10:52 test-claim-nfs.yaml

$ kubectl -n democratic-csi create -f test-claim-iscsi.yaml
persistentvolumeclaim/test-claim-iscsi created

```

Show claims:

```shell
$ kubectl -n democratic-csi get pvc

NAME               STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS        AGE
test-claim-iscsi   Bound    pvc-a20ebfac-2bd7-4e56-a0bc-c093ecadb117   1Gi        RWO            freenas-iscsi-csi   23s
```

Show detailed information of provisioning process:

```shell
$ kubectl describe pvc/test-claim-iscsi -n democratic-csi
Name:          test-claim-iscsi
Namespace:     democratic-csi
StorageClass:  freenas-iscsi-csi
Status:        Bound
Volume:        pvc-a20ebfac-2bd7-4e56-a0bc-c093ecadb117
Labels:        <none>
Annotations:   pv.kubernetes.io/bind-completed: yes
               pv.kubernetes.io/bound-by-controller: yes
               volume.beta.kubernetes.io/storage-class: freenas-iscsi-csi
               volume.beta.kubernetes.io/storage-provisioner: org.democratic-csi.iscsi
               volume.kubernetes.io/storage-provisioner: org.democratic-csi.iscsi
Finalizers:    [kubernetes.io/pvc-protection]
Capacity:      1Gi
Access Modes:  RWO
VolumeMode:    Filesystem
Used By:       <none>
Events:
  Type    Reason                 Age                From                                                                                                                    Message
  ----    ------                 ----               ----                                                                                                                    -------
  Normal  Provisioning           82s                org.democratic-csi.iscsi_truenas-iscsi-democratic-csi-controller-5fb94d4488-gglqt_282e5888-4faa-4b41-a386-3e90d6db2f51  External provisioner is provisioning volume for claim "democratic-csi/test-claim-iscsi"
  Normal  ExternalProvisioning   78s (x3 over 82s)  persistentvolume-controller                                                                                             waiting for a volume to be created, either by external provisioner "org.democratic-csi.iscsi" or manually created by system administrator
  Normal  ProvisioningSucceeded  78s                org.democratic-csi.iscsi_truenas-iscsi-democratic-csi-controller-5fb94d4488-gglqt_282e5888-4faa-4b41-a386-3e90d6db2f51  Successfully provisioned volume pvc-a20ebfac-2bd7-4e56-a0bc-c093ecadb117
```

Edit the Storage Claim to increase size.  Can apply a new claim file or it can be edited directly as shown below (loads in `vi`).

```yaml
$ kubectl edit pvc/test-claim-iscsi -n democratic-csi

...
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: freenas-iscsi-csi
...

```

Upon changing the `1Gi` to `2Gi` and saving the file:

```shell
$ kubectl edit pvc/test-claim-iscsi -n democratic-csi
persistentvolumeclaim/test-claim-iscsi edited
```

If the storage claim is being used by a pod, then within seconds the storage claim with be adjusted as defined, expanded in this case.  If claim is not being used yet, then the expansion will be differed until it is.

### Delete Test Claim

```shell
$ kubectl -n democratic-csi delete -f test-claim-iscsi.yaml
persistentvolumeclaim "test-claim-iscsi" deleted
```

---

## Full Test Deployment

A full test deployment script will be placed in the non-root `kube` home directory `~/democratic-csi/test-app-nfs-claim.yaml` which do the followng:

* Create 2 containers backed by CSI Persistent NFS storage claims of 2MB
* A sample `index.html` with "Hello Green World" and "Hello Blue World" will be created in the respective storage claims
* A service will be created for each container
* An ingress route will be created with middleware to clean up the URI
* Requests to the `/nginx/` URI will be round-robin between the two containers

```shell
cd /home/kube/democratic-csi

$ kubectl create namespace nfs-test-app
namespace/nfs-test-app created

$ kubectl apply -f test-app-nfs-claim.yaml -n nfs-test-app

deployment.apps/nginx-pv-green created
deployment.apps/nginx-pv-blue created
persistentvolumeclaim/test-claim-nfs-green created
persistentvolumeclaim/test-claim-nfs-blue created
service/nginx-pv-green created
service/nginx-pv-blue created
middleware.traefik.containo.us/nginx-strip-path-prefix created
ingressroute.traefik.containo.us/test-claim-ingressroute created
```

```shell
$ kubectl get all -n nfs-test-app
NAME                                 READY   STATUS    RESTARTS   AGE

pod/nginx-pv-green-9c9f6d448-nw6bh   1/1     Running   0          106s
pod/nginx-pv-blue-c7d6d44bf-gvbxv    1/1     Running   0          106s

NAME                     TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/nginx-pv-green   ClusterIP   10.43.132.60    <none>        80/TCP    2m9s
service/nginx-pv-blue    ClusterIP   10.43.240.245   <none>        80/TCP    2m9s

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx-pv-green   1/1     1            1           106s
deployment.apps/nginx-pv-blue    1/1     1            1           106s

NAME                                       DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-pv-green-9c9f6d448   1         1         1       106s
replicaset.apps/nginx-pv-blue-c7d6d44bf    1         1         1       106s
```

Testing the deployment using the Lynx Text Browser:

```shell
$ lynx -dump http://testlinux.example.com/nginx/
                                Hello Green World

$ lynx -dump http://testlinux.example.com/nginx/
                                Hello Blue World

$ lynx -dump http://testlinux.example.com/nginx/
                                Hello Blue World

$ lynx -dump http://testlinux.example.com/nginx/
                                Hello Green World

$ lynx -dump http://testlinux.example.com/nginx/
                                Hello Blue World
```

Delete the deployment:

```shell
$ kubectl delete -f test-app-nfs-claim.yaml -n nfs-test-app

deployment.apps "nginx-pv-green" deleted
deployment.apps "nginx-pv-blue" deleted
persistentvolumeclaim "test-claim-nfs-green" deleted
persistentvolumeclaim "test-claim-nfs-blue" deleted
service "nginx-pv-green" deleted
service "nginx-pv-blue" deleted
middleware.traefik.containo.us "nginx-strip-path-prefix" deleted
ingressroute.traefik.containo.us "test-claim-ingressroute" deleted

# Page no longer exists:
$ lynx -dump http://testlinux.example.com/nginx/
404 page not found
```

---

## Prometheus Operator and Grafana

These products are not installed by default, but can easily be deployed once everything above is functional.

* **Prometheus Operator** extends the Kubernetes API, so that when we create some of the yaml deployments it will looks as if we’re telling Kubernetes to deploy something, but it’s actually telling Prometheus Operator to do it for us. Official git: [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
* **Prometheus** is the collector of metrics, it uses something called service monitors that provide information Prometheus can come and scrape. Prometheus will use persistent storage, and we will specify for how long it will keep the data. You can have more than one instance of Prometheus in your cluster collecting separate data.
* **Service Monitors** - are other containers/deployments. They can be considered middle steps between the data and Prometheus. We will deploy some that are a single deployment such as for Kubernetes API to collect metrics from a server. node-exporter will use a daemonset deployment which deploys containers to each node to collects underlying OS information per node.
* **Grafana** takes data from one or more Prometheus instances to combine them into a single dashboard.  Dashboards can be customized as you wish.
