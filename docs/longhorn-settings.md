# Longhorn Distributed Storage Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* Longhorn Distributed storage is intended to be the default storage class, once installed the "local-path" StorageClass "default" flag will be removed.
* By default a ZFS Zvol of a defined size will be created at `/var/lib/longhorn` this limits how much space Longhorn can consume.  A zvol can easily be made larger when needed.

## Longhorn Infrastructure Diagram

![Longhorn Infrastructure Diagram](../images/how-longhorn-works.svg)

* See [Longhorn Web Site](https://longhorn.io/) for details.

## Review `defaults/main.yml` for Longhorn Settings

The Longhorn Settings are in variable namespace `install.longhorn`.

* Enable or disable installation of Longhorn Distributed storage.  Setting will default to `true` but you can override this value per host to prevent a host(s) from allocating local storage to Longhorn.

  ```yml
  install:
    longhorn:
      install_this: "{{longhorn_enabled|default(true)}}"  # Install longhorn distributed cluster storage
  ```

* Pin which version of Longhorn to install. This value should be defined in the inventory file or group_vars file or can be updated directly here.

  ```yml
      # Select Release to use: https://github.com/longhorn/longhorn/releases 
      install_version: "{{longhorn_install_version|default('v1.2.4')}}"
  ```

* The name space and release name Helm will use to install Longhorn:

  ```yml
      namespace: "longhorn-system"
      release: "longhorn"
  ```

---

### ZFS Zvol for Longhorn

* Define the ZFS pool name to use and volume name to create.

  * The `pool` can be defined per host or host group using variable `longhorn_zfs_pool` if this is not defined, it will default to `rpool` as shown below.

  ```yml
      zfs:                           # Combined "rpool/longhorn"
        pool: "{{longhorn_zfs_pool|default('rpool')}}"
        volume_name: "longhorn"
  ```

* Define some properties to be used with Zvol creation. The `volsize` specifies storage space dedicated to Longhorn usage.  You can select different compression if you like.

  ```yml
        zvol:
          options:
            volsize: "10G"
            compression: "lz4"        # "" (inherit), lz4, gzip-9, etc
            volblocksize: "16k"
  ```

### Longhorn Default Mountpoint

The ZFS Zvol will be formatted and mounted at the location specified below and Longhorn installation is set to look at this location.

```yml
zfs:
  zvol:
    mountpoint: "/var/lib/longhorn"
```

---

### Change Default Storage Class

The intent of longhorn is to be used instead of "local-path" storage class. Once Longhorn is installed kubernetes "local-path" will no longer be available.

```yaml
   disable_local_path_as_default_storage_class: true
```

---

### Longhorn Dashboard

* Settings for the Longhorn Web Dashboard. The `create_route` will create a Traefik Ingress route to expose the dashboard on the URI defined in `path`.

  ```yml
      # Longhorn Dashboard
      dashboard:
        create_route: true           # Create Ingress Route to make accessible 
        enable_basic_auth: true      # Require Authentication to access dashboard

        # Fully Qualified Domain for ingress routes - Traefik Load Balancer address name
        # This is the DNS name you plan to point to the Traefik ingress Load Balancer IP address.
        ingress_name: '{{k3s_cluster_ingress_name|default("k3s.{{ansible_domain}}")}}'

        # Default Dashboard URL:  https://k3s.{{ansible_domain}}/longhorn/
        path: "/longhorn"            # URI Path for Ingress Route

        # Encoded users and passwords for basic authentication
        allowed_users: "{{LONGHORN_DASHBOARD_USERS}}"
  ```

* The `ingress_name` should reference the DNS which points to the Traefik Load Balancer IP address used for all Traefik ingress routes. If a name is not provided it will default to hostname `k3s` and use the domain of the Kubernetes Linux host.
* The `allowed_users` maps to which users are allowed to access the Longhorn Dashboard (see more below).

The Longhorn Dashboard URL path will resemble: `https://k3s.example.com/longhorn/#/dashboard`

![Longhorn Storage Dashboard](../images/longhorn-dashboard.png)

* By default basic authentication for the dashboard is enabled.  Individual users allowed to access the dashboard are defined in `var/secrets/longhorn_dashboard_secrets.yml` as follows:

```yaml
# Define encoded Longhorn users allowed to use the Longhorn Dashboard (if enabled)
# Multiple users can be listed below, one per line (indented by 2 spaces)
# Created with "htpasswd" utility and then base64 encode that output such as:
# $ htpasswd -nb [user] [password] | base64

# Example of unique users from other dashboards:
#LONGHORN_DASHBOARD_USERS: |
#  dHJhZWZpa2FkbTokMnkkMTAkbHl3NWdYcXpvbFJCOUY4M0RHa2dMZW52YWJTcmpxUk9XbXNGUmZKa2ZQSlhBbzNDSmJHY08K

# Use same users currently defined by Traefik dashboard:
# NOTE: They do not share a common K8s secret. This will place the same information in two different
#       secrets.
LONGHORN_DASHBOARD_USERS: "{{TRAEFIK_DASHBOARD_USERS}}"
```

NOTE: by default, any users defined in the Traefik Dashboard allowed user list is allowed to log into the Longhorn dashboard.

* If you need to restrict access to the dashboard to different set of users or require different passwords, then update the file as needed.
* As stated in the comments this is not a shared Kubernetes secrets with Traefik. Once deployed a change in one will not be reflected in the other.  This is just to make initial setup easier.

---

### Test Claim

* Adjust if you want a Longhorn storage test claim performed once all validations have completed:

```yml
  test_claim:
    enabled: true               # true = attempt longhorn storage claim
    mode: "ReadWriteOnce"       # storage claim access mode
    size: "1Mi"                 # size of claim to request ("1Mi" is 1 Mebibytes)
    remove: true                # true = remove claim when test is completed (false leaves it alone)
```

---

### Show Storage Claim Provisioners and Claim Policy

```shell
$ kubectl get sc

NAME                 PROVISIONER            RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
longhorn (default)   driver.longhorn.io     Delete          Immediate           true                   4d3h

```

---

## Increasing Zvol Size in the Future

You can easily check the current `volsize` using standard ZFS commands:

```shell
$ zfs get volsize rpool/longhorn

NAME           PROPERTY  VALUE    SOURCE
rpool/longhorn  volsize   10G      local
```

Determine how much space you have available before increasing the `volsize`:

```shell
$ zfs get available rpool/longhorn

NAME           PROPERTY   VALUE  SOURCE
rpool/longhorn  available  783G   -
```

You can increase the `volsize` manually in the future using standard ZFS commands such as:

```shell
$ sudo zfs set volsize=15G rpool/longhorn

$ zfs get volsize rpool/longhorn

NAME            PROPERTY  VALUE    SOURCE
rpool/longhorn  volsize   15G      local
```

Then expand the filesystem to use newly allocated space:

```shell
$ sudo xfs_growfs /var/lib/longhorn

meta-data=/dev/zd0               isize=512    agcount=4, agsize=655360 blks
         =                       sectsz=512   attr=2, projid32bit=1
         =                       crc=1        finobt=1, sparse=1, rmapbt=0
         =                       reflink=1
data     =                       bsize=4096   blocks=2621440, imaxpct=25
         =                       sunit=0      swidth=0 blks
naming   =version 2              bsize=4096   ascii-ci=0, ftype=1
log      =internal log           bsize=4096   blocks=2560, version=2
         =                       sectsz=512   sunit=0 blks, lazy-count=1
realtime =none                   extsz=4096   blocks=0, rtextents=0
data blocks changed from 2621440 to 3932160
```

Within a few seconds the new size should be reflected in the Longhorn dashboard.

---

## Uninstall Longhorn

Should you need to remove longhorn:

```shell
$ helm uninstall longhorn -n longhorn-system
release "longhorn" uninstalled

$ kubectl delete namespace longhorn-system 
namespace "longhorn-system" deleted
```

### Remove Longhorn Dataset

You can also remove the ZFS dataset you specified, default was:

```shell
sudo umount /var/lib/longhorn

sudo zfs destroy rpool/longhorn
```

Then remove this line from `/etc/fstab`.

```text
/dev/zvol/rpool/longhorn /var/lib/longhorn xfs noatime,discard 0 0
```

[Back to README.md](../README.md)
