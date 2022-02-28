# K3s Kubernetes with ContainerD for ZFS

Automated 'K3s Lightweight Distribution of Kubernetes' deployment with many enhancements:

* non-root user account for Kubernetes, passwordless access to `kubectl` by default.
* condainerd to provide zfs snapshotter support
* Helm Client
* Cert-manager
* Traefik ingress Letsencrypt wildcard certificates for domains to staging or prod (Cloudflare DNS validator)
* [democratic-csi](https://github.com/democratic-csi/democratic-csi) to provide Persistent Volume Claim storage via iSCSI to TrueNAS

## Notes

* `k3s` does not have native support for ZFS file system, it will produce `overlayfs` error message.
  * See: [https://github.com/k3s-io/k3s/discussions/3980](https://github.com/k3s-io/k3s/discussions/3980)
* To get around this ZFS issue, this will also install `containerd` and `container network plugins` packages and configure them to support ZFS. The k3s configuration is then updated to use containerd.
  * Based on: [https://blog.nobugware.com/post/2019/k3s-containterd-zfs/](https://blog.nobugware.com/post/2019/k3s-containterd-zfs/)
* Cert-manager is installed since Traefik's Let's Encrypt support retrieves certificates and stores them in files. Cert-manager retrieves certificates and stores them in Kubernetes secrets.
* Traefik's Letsencrypt is configured for staging certificates, but you can default it to prod or use provided CLI parameter below to switch from staging to prod.
* democratic-csi uses a combination of the TrueNAS API over SSL/TLS and non-privileged SSH to dynamically allocate persistent storage zvols on TrueNAS upon request when storage claims are made.
  * The API key is admin access equivalent it needs to be protected (save in ansible vault, restrict access to the `yaml` file generated.)
  * non-privileged SSH has some limitations. ZFS delegation is used to give permissions to the non-privileged account. However some actions have no equivalent delegation to assign and can not be done unless an account with sudo access is provided such as an iSCSI zvol resize.
  * Be aware that iSCSI only allows a single claim to have write access at a time.  Multiple claims can have read-only access

## Environments Tested

* Ubuntu 20.04.4 based [ZFS on Root](https://gitea.rich-durso.us/reefland/ansible/src/branch/master/roles/zfs_on_root) installation.

---

## Packages Installed

* python3-pip (required for Ansible managed nodes)
* pip packages - openshift, pyyaml, kubernetes (required for Ansible to execute K8s module)
* k3s (Runs official script [https://get.k3s.io](https://get.k3s.io))
* containerd, containernetworking-plugins, iptables
* helm, apt-transport-https (required for helm client install)
* open-iscsi, lsscsi, sg3-utils, multipath-tools, scsitools (required for iSCSI support)

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

NOTE: That TrueNAS core requires the use of both API key and SSH access.  TrueNAS Scale only requires API access.

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
  * Dataset names are IMPORTANT, the combination of pool and datasets names and slashes must be under `17` characters.  (There are length limits and character overhead in the protocol documented below.)
  * Navigate to Storage > Click the triple dot on the storage pool > select Add Dataset.
  * Create two nested datasets in the root of the storage pool named "**k8s**" and "**iscsi**". My ZFS pool is named 'main', thus my path would become (`main/k8s/iscsi`)
    * Create two sibling datasets under "**iscsi**" named "**v**" (`main/k8s/iscsi/v`) and "**s**" (`main/k8s/iscsi/s`).
    * (Dataset `v` will hold the zvols created for persistent storage whereas dataset `s` will hold detached snapshots of the `v` dataset)
  * I used the following defaults for each snapshot:

  ```text
  - Sync: Inherit (standard)
  - Compression: Inherit (lz4)
  - Enable Atime: Inherit (off)
  - Encryption: Inherit (encrypted)
  - Record Size: Inherit (129Kib)
  - ACL Mode: Passthrough
  ```

  To create these manually from the TrueNAS CLI instead of the Admin Console:

  ```shell
  zfs create -o org.freenas:description="Persistent Storage for Kubernetes" main/k8s
  zfs create -o org.freenas:description="Container to hold iSCSI zvols and snapshots" main/k8s/iscsi
  zfs create -o org.freenas:description="Storage Container to hold zvols" main/k8s/iscsi/v
  zfs create -o org.freenas:description="Storage Container to hold detached snapshots" main/k8s/iscsi/s
  ```

![TrueNAS Datasets Created](images/zfs_iscsi_datasets.png)

* 5th - Delegate ZFS Permissions to non-root account "k8s" for dataset `main/k8s/iscsi`
  * NOTE: The delegations below may still be excessive for what is required.
  * See [ZFS allow](https://openzfs.github.io/openzfs-docs/man/8/zfs-allow.8.html) for more details.

  ```shell
  zfs allow -u k8s aclmode,canmount,checksum,clone,create,destroy,devices,exec,groupquota,groupused,mount,mountpoint,nbmand,normalization,promote,quota,readonly,recordsize,refquota,refreservation,receive,rename,reservation,rollback,send,setuid,share,snapdir,snapshot,userprop,userquota,userused,utf8only,version,volblocksize,volsize,vscan,xattr main/k8s/iscsi
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
