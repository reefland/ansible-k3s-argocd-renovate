# K3s Kubernetes with ContainerD for ZFS

Automated 'K3s Lightweight Distribution of Kubernetes' deployment with many enhancements:

* **non-root** user account for Kubernetes, passwordless access to `kubectl` by default.
* **condainerd** to provide ZFS snapshotter support
* Helm Client
* Cert-manager
* **Traefik** ingress with **Letsencrypt wildcard certificates** for domains against LE staging or prod (Cloudflare DNS validator)
* [democratic-csi](https://github.com/democratic-csi/democratic-csi) to provide **Persistent Volume Claim** storage via **iSCSI** and **NFS** from TrueNAS

## Notes

* `k3s` does not have native support for ZFS file system, it will produce `overlayfs` error message.
  * See: [https://github.com/k3s-io/k3s/discussions/3980](https://github.com/k3s-io/k3s/discussions/3980)
* To get around this ZFS issue, this will also install `containerd` and `container network plugins` packages and configure them to support ZFS. The k3s configuration is then updated to use containerd.
  * Based on: [https://blog.nobugware.com/post/2019/k3s-containterd-zfs/](https://blog.nobugware.com/post/2019/k3s-containterd-zfs/)
* `Cert-manager` is installed since Traefik's Let's Encrypt support retrieves certificates and stores them in files. Cert-manager retrieves certificates and stores them in Kubernetes secrets.
* Traefik's Letsencrypt is configured for staging certificates, but you can default it to prod or use provided CLI parameter below to switch from staging to prod.
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

## Environments Tested

* Ubuntu 20.04.4 based [ZFS on Root](https://gitea.rich-durso.us/reefland/ansible/src/branch/master/roles/zfs_on_root) installation.
* TrueNAS Core 12-U8
* K3s v1.23.3

---

## Packages Installed

* python3-pip (required for Ansible managed nodes)
* pip packages - openshift, pyyaml, kubernetes (required for Ansible to execute K8s module)
* k3s (Runs official script [https://get.k3s.io](https://get.k3s.io))
* containerd, containernetworking-plugins, iptables
* helm, apt-transport-https (required for helm client install)
* open-iscsi, lsscsi, sg3-utils, multipath-tools, scsitools (required when iSCSI support is enabled)
* libnfs-utils (required for NFS support is enabled)

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

6. Configure Letsencrypt certificate generation for Traefik.  The file `vars/k3s_traefik_api_secrets.yml` needs to be configured to provide three variables:

    * `CF_DNS_API_TOKEN` - CloudFlare API token value
    * `CF_AUTH_EMAIL` - CloudFlare Email address associated with the API token
    * `LE_AUTH_EMAIL` - Letsencrypt Email Address for expiration Notifications

    ```yml
    # Cloudflare API token used by Traefik
    # Requires Zone / Zone / Read
    # Requires Zone / DNS / Edit Permissions
    CF_DNS_API_TOKEN: abs123 ... 456xyz

    # Email address associated to DNS API key
    CF_AUTH_EMAIL: you@domain.com

    # Email address associated to Let's Encrypt
    LE_AUTH_EMAIL: you@domain.com
    ```

    Be sure to encrypt this secret when completed `ansible-vault encrypt k3s_traefik_api_secrets.yml`

    By default staging certificates are generated and controlled by:

    ```yaml
    k3s:
      traefik:
        # Generate Staging Certificates
        staging: true
    ```

    Don't change this value. Once staging certificates are verified to be working, the playbook can be run to switch to production certificates:

    ```shell
    ansible-playbook -i inventory kubernetes.yml --tags="config_traefik_dns_certs" --extra-vars '{le_staging:false}' 
    ```

    To test generated certificates, a deployment script for `whoami` is created (namespace `default`):

    ```shell
    sudo su - kube
    cd ~/traefik

    # Deploy apps & create ingress rules
    kubectl apply -f traefik_test_apps.yaml

    # Confirm pods are running:
    kubectl get pods -n default

      NAME                      READY   STATUS    RESTARTS      AGE
      whoami-5b69cdcd49-2gfts   1/1     Running   2 (23m ago)   6h9m
      whoami-5b69cdcd49-bg5j4   1/1     Running   2 (23m ago)   6h9m

    # Simple test without certificates (notice URI of "/notls")
    curl http://$(hostname -f):80/notls

    Hostname: whoami-5b69cdcd49-2gfts
    IP: 127.0.0.1
    IP: ::1
    IP: 10.42.0.37
    IP: fe80::c43:7ff:fe31:3b61
    RemoteAddr: 10.42.0.34:52596
    GET /notls HTTP/1.1
    Host: testlinux.example.com
    User-Agent: curl/7.68.0
    Accept: */*
    Accept-Encoding: gzip
    X-Forwarded-For: 10.42.0.36
    X-Forwarded-Host: testlinux.example.com
    X-Forwarded-Port: 80
    X-Forwarded-Proto: http
    X-Forwarded-Server: traefik-6bb96f9bd8-72cj8
    X-Real-Ip: 10.42.0.36

    # This will work ONLY with a production cert, it will FAIL with a staging cert:
    curl https://$(hostname -f):/tls

    # This will work with EITHER staging OR production cert:
    curl -k https://$(hostname -f):/tls

    # Show certificate information:
    kubectl describe certificates wildcard-cert -n kube-system

    Spec:
      Dns Names:
        example.com
        *.example.com
      Issuer Ref:
        Kind:       ClusterIssuer
        Name:       letsencrypt-prod
      Secret Name:  wildcard-secret
    Status:
      Conditions:
        Last Transition Time:  2022-02-24T18:09:47Z
        Message:               Certificate is up to date and has not expired
        Observed Generation:   1
        Reason:                Ready
        Status:                True
        Type:                  Ready
      Not After:               2022-05-25T17:09:46Z
      Not Before:              2022-02-24T17:09:47Z
      Renewal Time:            2022-04-25T17:09:46Z

    # To delete the "whoami" deployment and ingress rules:
    kubectl delete -f traefik_test_apps.yaml

    deployment.apps "whoami" deleted
    service "whoami" deleted
    ingressroute.traefik.containo.us "simpleingressroute" deleted
    ingressroute.traefik.containo.us "ingressroutetls" deleted
    ```

7. Define the version of Cert Manager to be installed. Available version number can be found [here](https://artifacthub.io/packages/helm/cert-manager/cert-manager).

    ```yml
    cert_manager:
      install_version: "v1.7.1"
    ```

8. Configure TrueNAS for democratic-csi Configuration.

NOTE: That TrueNAS core requires the use of both API key and SSH access.  (TrueNAS Scale only requires API access)

* 1st - Generate a SSH key.  
  * The public key will be placed in the TrueNAS user account and the private key will be placed in an ansible vault configuration file (`vars/secrets/truenas_api_secrets.yml` variable `TN_SSH_PRIV_KEY`).

  ```shell
  ssh-keygen -a 100 -t ed25519 -f ~/.ssh/k8s.<remote_hostname>
  ```

* 2nd - Generate a TrueNAS API Key from the Admin Console Web Interface.
  * Click Gear Icon in upper left corner and select API Keys
    * Click `[Add]` and give the API key a name such as `k8sStorageKey` (can be named anything).
    * Click `[Add]` to create the API key. **IMPORTANT** _make note of the API Key generated you will need it!_
* 3rd - Create a TrueNAS non-privileged user account in the Admin Console
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

* 4th - Create Datasets
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
    ![TrueNAS Datasets Created](images/zfs_iscsi_nfs_datasets.png)

* 5th - Delegate ZFS Permissions to non-root account `k8s`.
  * NOTE: The delegations below may still be excessive for what is required.
  * See [ZFS allow](https://openzfs.github.io/openzfs-docs/man/8/zfs-allow.8.html) for more details.

    For dataset `main/k8s/iscsi`:

      ```shell
      zfs allow -u k8s aclmode,canmount,checksum,clone,create,destroy,devices,exec,groupquota,groupused,mount,mountpoint,nbmand,normalization,promote,quota,readonly,recordsize,refquota,refreservation,receive,rename,reservation,rollback,send,setuid,share,snapdir,snapshot,userprop,userquota,userused,utf8only,version,volblocksize,volsize,vscan,xattr main/k8s/iscsi
      ```

    For dataset `main/k8s/nfs`:

      ```shell
      zfs allow -u k8s aclmode,canmount,checksum,clone,create,destroy,devices,exec,groupquota,groupused,mount,mountpoint,nbmand,normalization,promote,quota,readonly,recordsize,refquota,refreservation,receive,rename,reservation,rollback,send,setuid,share,snapdir,snapshot,userprop,userquota,userused,utf8only,version,volblocksize,volsize,vscan,xattr main/k8s/nfs
      ```

* 6th - Define Ansible Secrets within `vars/secrets/truenas_api_secrets.yml`:
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

* 7th - update values in `defaults/main.yml`.

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

* 8th - update iSCSI values in `defaults/main.yml`:

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

* 9th - update NFS values in `defaults/main.yml`:

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

  * Has sudo access been enabled for the SSH account? This is required for TrueNAS Core 12

  ```yml
      zfs:
        sudo_enabled: true          # TrueNAS Core 12 requires non-root account have sudo access
  ```

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

  * Confirm the dataset and detached snapshot dataset names match what you created above:

  ```yml
        zfs:
        # Assumes pool named "main", dataset named "k8s", child dataset "nfs"
        # Any additional provisioners such as iSCSI would be at the same level as "nfs" (sibling of it)
        datasets:
          parent_name: "main/k8s/nfs/v"
          snapshot_ds_name: "main/k8s/nfs/s"     
  ```

  * Additional ZFS settings for NFS:

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

## Access Modes

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

## Troubleshooting

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
