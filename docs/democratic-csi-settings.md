# democratic-csi for TrueNAS Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

Neither the democratic-csi iSCSI or NFS provisioners for TrueNAS are installed by default due to the complexity in setting it up.  I've gathered as much information as I could and present it below in an as easy as I could way showing examples how to configure it.  Once configured, it works fantastic!  Both can be installed giving you flexibility to pick between them.

Once you have configured your yaml files as outlined below you can trigger the installation by passing Ansible tags `--tags="install_democratic_csi_iscsi"` or `--tags="install_democratic_csi_nfs"`.  This should be run against all nodes in the cluster to install the respective iSCSI and NFS packages needed.

On the master node Ansible will clone the ArgoCD repository and copy in the respective `applications`, `namespaces` and `workloads` files and commit and push changes to repository.  You can then monitor installation and review logs from within ArgoCD dashboard.  On all other nodes it will just install the required packaged.

![democratic-csi iSCSI and NFS provisioners within ArgoCD](../images/democratic-csi_in_argocd.png)

* ArgoCD showing deployed and sync from repository.

---

* `democratic-csi` - CSI or **C**ontainer **S**torage **I**nterface defines a standard interface for container orchestration systems (like Kubernetes) to expose arbitrary storage systems to their container workloads.
  * Uses a combination of the TrueNAS API over SSL/TLS and SSH to dynamically allocate persistent storage zvols on TrueNAS upon request when storage claims are made.
  * The TrueNAS API key is **admin access** equivalent.  This needs to be protected (save in ansible vault, restrict access to the `yaml` file generated.)  
  * TrueNAS Core specific notes:
    * iSCSI with SSH can use a non-privileged user
    * NFS with SSH will require user with password-less sudo (instructions below)
    * ZFS delegation is used to give ZFS abilities to the SSH user. These abilities (permissions) are scoped to the specific dataset used for democratic-csi.  
    * The SSH user account is required for ZFS operations not available within the TrueNAS API.
  * Be aware that:
    * iSCSI backed PVC allow only a single claim with write access at a time.  Multiple claims can have read-only access to the PVC
    * NFS backed PVC can have multiple claims with write access
* TrueNAS core requires the use of both API key and SSH access. (TrueNAS Scale only requires API access)

---

## TrueNAS Configuration

The following steps get TrueNAS ready for democratic-csi.

### Generate SSH Key

* The public key will be placed in the TrueNAS user account.
* The private key will be placed in an ansible vault configuration file `vars/secrets/truenas_api_secrets.yml` variable `TN_SSH_PRIV_KEY`.

```shell
ssh-keygen -a 100 -t ed25519 -f ~/.ssh/k8s.<remote_hostname>
```

### Generate TrueNAS API Key

From the Admin Console Web Interface:

* Click Gear Icon in upper left corner and select API Keys
  * Click `[Add]` and give the API key a name such as `k8sStorageKey` (can be named anything).
  * Click `[Add]` to create the API key. **IMPORTANT** _make note of the API Key generated you will need it!_

Create a TrueNAS non-privileged User Account

From the Admin Console Web Interface:

* Navigate to Accounts > Users and click `[Add]`, provide details:

```text
- Full Name: Kubernetes Storage Account
- Username:  k8s
- Email: <blank>
- Password: (leave blank will be disabled)
- User ID: (leave default)
- Primary Group: k8s
- Auxiliary Groups: <blank>
- Home directory: `/mnt/main/users/k8s`  (wherever you place user account datasets)
    - Permissions:
    - User: Read, Write Execute
    - Group: Read Execute
    - Other: none

- SSH Public Key:  (paste contents of the k8s.<remote_hostname>.pub file created above in here)
- Disable Password: Yes
- Shell: `/usr/local/bin/bash`
- Microsoft Account: unchecked
- Samba Authentication: unchecked
```

### Create ZFS Datasets

* **IMPORTANT**: Dataset names for iSCSI are length limited. The combination of pool and datasets names and slashes must be under `17` characters.  (There are length limits and character overhead in the protocol documented below.)
* Click `Shell` towards the lower left of the TrueNAS Admin Web Console.
  * The commands further down will create the directory structure in zpool `main` as shown below:

  ```txt
    k8s
    ├── iscsi
    │   ├── s
    │   └── v
    └── nfs
        ├── s
        └── v
  ```

  * The datasets named `v` will hold the zvols created for persistent storage whereas datasets `s` will hold detached snapshots of the `v` dataset

  The following commands can be used from TrueNAS Shell to create the iSCSI and NFS datasets:

  ```shell
  zfs create -o org.freenas:description="Persistent Storage for Kubernetes" main/k8s
  
  zfs create -o org.freenas:description="Container to hold iSCSI zvols and snapshots" main/k8s/iscsi
  zfs create -o org.freenas:description="Storage Container for iSCSI zvols" main/k8s/iscsi/v
  zfs create -o org.freenas:description="Storage Container for iSCSI detached snapshots" main/k8s/iscsi/s

  zfs create -o org.freenas:description="Container to hold NFS zvols and snapshots" main/k8s/nfs
  zfs create -o org.freenas:description="Storage Container for NFS zvols" main/k8s/nfs/v
  zfs create -o org.freenas:description="Storage Container for NFS detached snapshots" main/k8s/nfs/s
  ```

  My datasets have these default:

  ```text
  - Sync: Inherit (standard)
  - Compression: Inherit (lz4)
  - Enable Atime: Inherit (off)
  - Encryption: Inherit (encrypted)
  - Record Size: Inherit (129Kib)
  - ACL Mode: Passthrough
  ```

  Datasets as seen in TrueNAS Admin Web Console:
  ![TrueNAS Datasets Created](../images/zfs_iscsi_nfs_datasets.png)

### Delegate ZFS Permissions to non-Root Account `k8s`

* NOTE: The delegations below may still be excessive for what is required.  The developers have not stated specific requirements.
* See [ZFS allow](https://openzfs.github.io/openzfs-docs/man/8/zfs-allow.8.html) for more details.

For dataset `main/k8s/iscsi`:

```shell
zfs allow -u k8s aclmode,canmount,checksum,clone,create,destroy,devices,exec,groupquota,groupused,mount,mountpoint,nbmand,normalization,promote,quota,readonly,recordsize,refquota,refreservation,receive,rename,reservation,rollback,send,setuid,share,snapdir,snapshot,userprop,userquota,userused,utf8only,version,volblocksize,volsize,vscan,xattr main/k8s/iscsi
```

For dataset `main/k8s/nfs`:

```shell
zfs allow -u k8s aclmode,canmount,checksum,clone,create,destroy,devices,exec,groupquota,groupused,mount,mountpoint,nbmand,normalization,promote,quota,readonly,recordsize,refquota,refreservation,receive,rename,reservation,rollback,send,setuid,share,snapdir,snapshot,userprop,userquota,userused,utf8only,version,volblocksize,volsize,vscan,xattr main/k8s/nfs
```

---

## Enable sudo access for non-Root User

NOTE: This is only required if you want to use the NFS provisioner.

* To enable sudo access for the SSH account, use the TrueNAS "cli" command from TrueNAS shell in the Admin Web Console or via a root access SSH account.

```yml
# at the command prompt
root@truenas[~]# cli

************************************************************
Software in ALPHA state, highly experimental.
No bugs/features being accepted at the moment.
************************************************************

# This will list all accounts, find the account you created for SSH access.
# In my example the account is named "k8s" and was assigned id "41":

truenas[]> account user query select=id,username,uid,sudo_nopasswd     

...
{'id': 41, 'sudo_nopasswd': False, 'uid': 1004, 'username': 'k8s'}]

# This enables sudo without passwords for the account, adjust "41" as needed:
truenas[]> account user update id=41 sudo=true                                                                                                                                     
truenas[]> account user update id=41 sudo_nopasswd=true                                                                                                                            
truenas[]>

# Exit cli by hitting [CTRL]+[D]

# Confirm account is listed in sudoers file, adjust account name as needed:
cat /usr/local/etc/sudoers | grep k8s

  k8s ALL=(ALL) NOPASSWD: ALL
```

---

## Define Ansible Secrets for democratic-csi

democratic-csisecrets are stored within `vars/secrets/main.yml`.

* Set the TrueNAS HTTP hostname (just hostname NOT URL)

```yml
# Set the FQDN of the TrueNAS hostname to connect to, by default the SSH and ISCSI hostnames
# will also use this value, but you can change them below.
TN_HTTP_HOST:  truenas.mydomain.com
```

* Set the TrueNAS API Key created above:

```yml
# Set the value of the API Key from TrueNAS.  
# From TrueNAS Admin Console, click Gear Icon (top right) and Select "API Keys", click [Add].
# Place the generated API Key value here:
TN_HTTP_API_KEY: 1-abcd ... tI5
```

* Set the TrueNAS SSH hostname, below assumes it is the same as HTTP hostname:

```yml
# Set the value of the SSH TrueNAS hostname to connect to:
TN_SSH_HOST: "{{TN_HTTP_HOST}}"
```

* Set the user name for the SSH connection. This should be a non-root account, ideally without sudo privileges but sudo can be needed for some TrueNAS core options.

```yml
# Set the value of the username for the SSH connection
TN_SSH_USER: k8s
```

* A SSH password or Private Key must be defined.  Don't use a password.  The password is commented out for a reason, don't do it.

```yml
# Set the value of the username's password for the SSh connection
# Do not use this, use a certificate instead (see below)
#TN_SSH_PASSWD: null
```

* Set the SSH Private. Super easy. Just cut & paste, no need to be silly and use a password (Seriously no password). Just fill it between the BEGIN and END markers. (NOTE: the key needs to be indented 2 characters as show)

```yml
TN_SSH_PRIV_KEY: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  b3B...
  QyN...
  dgA...
  AAA...
  Hbv...
  -----END OPENSSH PRIVATE KEY-----
```

* Set the TrueNAS iSCSI hostname, below assumes it is the same as HTTP hostname:

```yml
# Set the value of the iSCSI TrueNAS hostname to connect to:
TN_ISCSI_HOST: "{{TN_HTTP_HOST}}"
```

* Set the TrueNAS NFS hostname, below assumes it is the same as HTTP hostname:

```yml
# Set the value of the NFS TrueNAS hostname to connect to:
TN_NFS_HOST: "{{TN_HTTP_HOST}}"
```

* Don't forget to encrypt the secret file once everything is populated:

```shell
ansible-vault encrypt roles/k3s-argocd/vars/secrets/main.yml 
```

---

## Review `defaults/main.yml` for democratic-csi Settings

The democratic-csi Settings are in variable namespace `install.democratic_csi`.

* Pin which version of democratic-csi to install. This value should be defined in the inventory file or group_vars file or can be updated directly here.

  ```yml
  ###[ Democratic CSI Installation Settings ]######################################################  
  democratic_csi:
    # Select Release to use: https://github.com/democratic-csi/charts/releases
    install_version: "{{democratic_csi_install_version|default('0.13.1')}}"
  ```

* The name space Helm will use to install democratic-csi:

  ```yml
    namespace: "democratic-csi"
  ```

### TrueNAS Connectivity Settings

* Set http protocol settings to connect to TrueNAS (http or https), port number (80, 443), and if insecure connections are allowed:

  ```yml
    truenas:
      http_connection:
        protocol: "https"
        port: 443
        allow_insecure: false
  ```

* Set the SSH port to connect to TrueNAS:

  ```yml
      ssh_connection:
        port: 22
  ```

* Set the iSCSI port to connect to TrueNAS:

  ```yml
      iscsi_connection:
        port: 3260
  ```

### iSCSI Storage Settings

* Settings for the storage class:

  ```yml
      storage_class:
        default_class: false
        reclaim_policy: "Delete"    # "Retain", "Recycle" or "Delete"
        volume_expansion: true
  ```
  
* The `reclaim_policy` values are:

  * `Retain` - Manual reclamation. When the PersistentVolumeClaim is deleted, the PersistentVolume still exists within TrueNAS and the volume is considered "released". But it is not yet available for another claim because the previous claimant's data remains on the volume. This type can be reused.  If you care about the data within the volume, you probably want this.
  * `Recycle` - Warning: The Recycle reclaim policy is deprecated.
  * `Delete` - The deletion removes both the PersistentVolume object from Kubernetes, as well as the associated storage asset within TrueNAS
* The `volume_expansion` when set to `true`:
  * Allows a request for a larger volume for a PVC. This triggers expansion of the volume that backs the underlying PersistentVolume. A new PersistentVolume is never created to satisfy the claim. Instead, an existing volume is resized.
  * Only volumes containing a file system of XFS, Ext3, or Ext4 can be resized.

* Confirm the dataset and detached snapshot dataset names match what you created above:

  ```yml
      zfs:
      # Assumes pool named "main", dataset named "k8s", child dataset "iscsi"
      # Any additional provisioners such as NFS would be at the same level as "iscsi" (sibling of it)
      # IMPORTANT:
      #   total volume name (zvol/<datasetParentName>/<pvc name>) length cannot exceed 63 chars
      #   https://www.ixsystems.com/documentation/freenas/11.2-U5/storage.html#zfs-zvol-config-opts-tab
      #   standard volume naming overhead is 46 chars
      #   Which means names **MUST-BE** 17 characters or LESS!!!!
      datasets:
        parent_name: "main/k8s/iscsi/v"
        snapshot_ds_name: "main/k8s/iscsi/s"
  ```

* Settings for the iSCSI zvols to create can be adjusted:

  ```yml
      zvol:
        compression: "lz4"     # "" (inherit), lz4, gzip-9, etc
        blocksize: ""          # 512, 1K, 2K, 4K, 8K, 16K, 64K, 128K default is 16K
        enable_reservation: false
  ```

* Settings for the iSCSI target group and iSCSI authentication:

  ```yml
    target_group:
      portal_group: 1             # get the correct ID from the "portal" section in the UI
      initiator_group: 1          # get the correct ID from the "initiators" section in the UI
      auth_type: "None"           # None, CHAP, or CHAP Mutual

      # get the correct ID from the "Authorized Access" section of the UI
      auth_group: ""              # only required if using CHAP
  ```

* Settings for the iSCSI extents created:

  ```yml
    extent:
      fs_type: "xfs"              # zvol block-based storage can be formatted as ext3, ext4, xfs
      block_size: 4096            # 512, 1024, 2048, or 4096
      rpm: "5400"                 # "" (let FreeNAS decide, currently defaults to SSD), Unknown, SSD, 5400, 7200, 10000, 15000
      avail_threshold: 0          # 0-100 (0 == ignore)
  ```

* Adjust if you want a iSCSi storage test claim created:

  ```yml
    test_claim:
      enabled: true               # true = attempt iscsi storage claim
      mode: "ReadWriteOnce"       # storage claim access mode
      size: "1Mi"                 # size of claim to request ("1Mi" is 1 Mebibytes)
      remove: true                # true = remove claim when test is completed (false leaves it alone)
  ```

* The test claim will be stored on the master node at `/home/kube/democratic-csi/test-claim-iscsi.yaml`.

---

### NFS Storage Settings

* Settings for the storage class:

  ```yml
    ###[ Democratic CSI NFS Settings ]#############################################################
    nfs:
      provisioner: "freenas-nfs"
      
      storage_class:
        default_class: false
        reclaim_policy: "Delete"    # "Retain", "Recycle" or "Delete"
        volume_expansion: true
  ```

* The `reclaim_policy` values are:

  * `Retain` - Manual reclamation. When the PersistentVolumeClaim is deleted, the PersistentVolume still exists within TrueNAS and the volume is considered "released". But it is not yet available for another claim because the previous claimant's data remains on the volume. This type can be reused.  If you care about the data within the volume, you probably want this.
  * `Recycle` - Warning: The Recycle reclaim policy is deprecated.
  * `Delete` - The deletion removes both the PersistentVolume object from Kubernetes, as well as the associated storage asset within TrueNAS
* The `volume_expansion` when set to `true`:
  * Allows a request for a larger volume for a PVC. This triggers expansion of the volume that backs the underlying PersistentVolume. A new PersistentVolume is never created to satisfy the claim. Instead, an existing volume is resized.
  * Only volumes containing a file system of XFS, Ext3, or Ext4 can be resized.

* Has sudo access been enabled for the SSH account? This is required for TrueNAS Core 12.

  ```yml
      zfs:
        sudo_enabled: true          # TrueNAS Core 12 requires non-root account have sudo access
  ```

* Confirm the dataset and detached snapshot dataset names match what you created above:

  ```yml
      zfs:
        # Assumes pool named "main", dataset named "k8s", child dataset "nfs"
        # Any additional provisioners such as iSCSI would be at the same level as "nfs" (sibling of it)
        datasets:
          parent_name: "main/k8s/nfs/v"
          snapshot_ds_name: "main/k8s/nfs/s"     
  ```

### Additional ZFS settings for NFS

```yml
        enable_quotas: true
        enable_reservation: false

        permissions:
          mode: '"0777"'
          user_id_num: 0          # 0 = root, needs User UID not a name (API needs a number)
          group_id_num: 0         # 0 = wheel, needs Group GUID not a name (API needs a number)
```

* Adjust if you want an NFS storage test claim performed once all validations have completed:

```yml
    test_claim:
      enabled: true               # true = attempt iscsi storage claim
      mode: "ReadWriteOnce"       # storage claim access mode
      size: "1Mi"                 # size of claim to request ("1Mi" is 1 Mebibytes)
      remove: true                # true = remove claim when test is completed (false leaves it alone)
```

---

**Access Modes**:

The `mode` specified in the storage claim described that specific PV's capabilities:

* `ReadWriteOnce` - the volume can be mounted as read-write by a single node. ReadWriteOnce access mode still can allow multiple pods to access the volume when the pods are running on the same node.
* `ReadOnlyMany` - the volume can be mounted as read-only by many nodes.
* `ReadWriteMany` - the volume can be mounted as read-write by many nodes.

In the CLI, the access modes are abbreviated to:

* `RWO` - ReadWriteOnce
* `ROX` - ReadOnlyMany
* `RWX` - ReadWriteMany

**Important!** A volume can only be mounted using one access mode at a time, even if it supports many. For example, iSCSI can be mounted as ReadWriteOnce by a single node or ReadOnlyMany by many nodes, but not at the same time.

PersistentVolumes binds are exclusive, and since PersistentVolumeClaims are namespaced objects, mounting claims with "Many" modes (ROX, RWX) is only possible within one namespace.

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
freenas-iscsi-csi      org.democratic-csi.iscsi   Delete          Immediate              true                   40h
freenas-nfs-csi        org.democratic-csi.nfs     Delete          Immediate              true                   20h
```

---

### Experiment with Test Claims

Test claims for NFS and iSCSI are provided.  They can be used as-is or modified:

```shell
$ kube@testlinux:~/democratic-csi$ ls -l test*
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

## Increase Storage Claim Size

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

---

## Change Storage Claim Policy

For dynamically provisioned PersistentVolumes, the default reclaim policy is `Delete`. This means that a dynamically provisioned volume is automatically deleted when the corresponding PersistentVolumeClaim is deleted (Pod is deleted). This might be inappropriate if the volume contains precious data. You might want to switch to `Retain` policy. With the `Retain` policy, if the PersistentVolumeClaim is deleted (Pod deleted), the corresponding PersistentVolume will not be deleted --  it is moved to the `Released` phase, where all of its data can be manually recovered.

Storage Claim can be patched to change Claim Policy:

```shell
kubectl patch pv <your-pv-name> -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```

---

### Delete Test Claim

```shell
$ kubectl -n democratic-csi delete -f test-claim-iscsi.yaml
persistentvolumeclaim "test-claim-iscsi" deleted
```

---

## Full Democratic CSI Test Deployment

A full test deployment script will be placed in the non-root `kube` home directory `~/democratic-csi/test-app-nfs-claim.yaml` which do the followng:

* Create 2 containers backed by CSI Persistent NFS storage claims of 2MB
* A sample `index.html` with "Hello Green World" and "Hello Blue World" will be created in the respective storage claims
* A service will be created for each container
* An ingress route will be created with middleware to clean up the URI
* Requests to the `/nginx/` URI will be round-robin between the two containers

```shell
$ cd /home/kube/democratic-csi

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

```shell
$ kubectl get pvc -n nfs-test-app

NAME                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS      AGE
test-claim-nfs-green   Bound    pvc-129d713f-54ab-42b7-a658-8395b148e722   2Mi        RWO            freenas-nfs-csi   110s
test-claim-nfs-blue    Bound    pvc-6aaf3095-feac-487b-944a-4c72ee7fe2f4   2Mi        RWO            freenas-nfs-csi   110s

```

Testing the deployment using the `Lynx` Text Browser:

```shell
$ lynx -dump http://k3s.example.com/nginx/
                    Hello Green World

$ lynx -dump http://k3s.example.com/nginx/
                    Hello Blue World

$ lynx -dump http://k3s.example.com/nginx/
                    Hello Blue World

$ lynx -dump http://k3s.example.com/nginx/
                    Hello Green World

$ lynx -dump http://k3s.example.com/nginx/
                    Hello Blue World
```

If you don't have `Lynx` Text Browser, the `wget` utility will work:

```shell
$ wget -q -nv -O - http://k3s.example.com/nginx/
<h1> Hello <font color=blue>Blue World</font></h1>

$ wget -q -nv -O - http://k3s.example.com/nginx/
<h1> Hello <font color=green>Green World</font></h1>

$ wget -q -nv -O - http://k3s.example.com/nginx/
<h1> Hello <font color=blue>Blue World</font></h1>

$ wget -q -nv -O - http://k3s.example.com/nginx/
<h1> Hello <font color=green>Green World</font></h1>

$ wget -q -nv -O - http://k3s.example.com/nginx/
<h1> Hello <font color=blue>Blue World</font></h1>

$ wget -q -nv -O - http://k3s.example.com/nginx/
<h1> Hello <font color=green>Green World</font></h1>
```

Delete the deployment when done testing:

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

$ kubectl get pvc -n nfs-test-app
No resources found

$ kubectl delete namespace nfs-test-app
namespace "nfs-test-app" deleted

# Page no longer exists:
$ lynx -dump http://k3s.example.com/nginx/
404 page not found
```

---

[Back to README.md](../README.md)
