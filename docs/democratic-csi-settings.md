# democratic-csi for TrueNAS Settings & Important Notes

## Important Notes

* `democratic-csi` - CSI or **C**ontainer **S**torage **I**nterface defines a standard interface for container orchestration systems (like Kubernetes) to expose arbitrary storage systems to their container workloads.
  * Uses a combination of the TrueNAS API over SSL/TLS and SSH to dynamically allocate persistent storage zvols on TrueNAS upon request when storage claims are made.
  * The TrueNAS API key is **admin access** equivalent.  This needs to be protected (save in ansible vault, restrict access to the `yaml` file generated.)  
  * TrueNAS Core specific notes:
    * iSCSI with SSH can use a non-privileged user
    * NFS with SSH will require user with password-less sudo (instructions below)
    * ZFS delegation is used to give ZFS abilities to the SSH user. These abilities (permissions) are scoped to the specific dataset used for democratic-csi.  
    * The SSH user account is required for ZFS operations not available within the TrueNAS API.
  * Be aware that:
    * iSCSI only allows a single claim to have write access at a time.  Multiple claims can have read-only access
    * NFS can have multiple claims with write access
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

democratic-csisecrets are stored within `vars/secrets/truenas_api_secrets.yml`.

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
ansible-vault encrypt roles/k3s-kubernetes/vars/secrets/truenas_api_secrets.yml 
```

---

## Review `defaults/main.yml` for democratic-csi Settings

The democratic-csi Settings are in variable namespace `install.democratic_csi`.

### Select Chart Version to Install

It is recommended to pin specific version known to work and test newer version when you can by updating this value.

```yml
 democratic_csi:
    # Select release to use: https://github.com/democratic-csi/charts/releases
    install_version: "v0.11.0"    # installs democratic_csi v1.5.4
```

When a newer chart (or previous) version is selected, you can push out changes using tags:

```shell
ansible-playbook -i inventory kubernetes.yml -l testlinux.example.com --tags="install_democratic_csi_iscsi, install_democratic_csi_nfs"
```

### TrueNAS Connectivity Settings

* Set http protocol settings to connect to TrueNAS (http or https), port number (80, 443), and if insecure connections are allowed:

```yml
democratic_csi:

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

* Enable or disable installation of iSCSI provisioner:

```yml
  iscsi:
    install_this: true            # Install the iSCSI provisioner
```

* Settings for the storage class:

```yml
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

* Adjust if you want a iSCSi storage test claim performed once all validations have completed:

```yml
  test_claim:
    enabled: true               # true = attempt iscsi storage claim
    mode: "ReadWriteOnce"       # storage claim access mode
    size: "1Gi"                 # size of claim to request ("1Gi" is 1 Gibibytes)
    remove: true                # true = remove claim when test is completed (false leaves it alone)
```

### NFS Storage Settings

* Enable or disable installation of NFS provisioner:

```yml
  nfs:
    install_this: true            # Install the NFS provisioner
```

* Settings for the storage class:

```yml
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
      size: "1Gi"                 # size of claim to request ("1Gi" is 1 Gibibytes)
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

[Back to README.md](../README.md)
