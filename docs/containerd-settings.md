# Containerd Settings & Important Notes

## Important Notes

* Ubuntu's `zsys` system snapshot creator does _not_ play nicely with containerd.  A dataset outside of its reach is created.

## Review `defaults/main.yml` for Containerd Settings

The Containerd Settings are in variable namespace `install.containerd`.

### Define ZFS Dataset for Containerd

A ZFS dataset will be created for containerd ZFS snapshotter support.  

* NOTE that Ubuntu's `zsys` system snapshot creator does _not_ play nicely with containerd.

The ZFS dataset should be created outside of `zsys` monitoring view. The following is a reasonable ZFS dataset configuration:

  ```yml
  containerd:
    zfs:
      detect_uuid: false
      pool: "rpool"
      dataset_prefix: "containerd"
      uuid: ""
      dataset_postfix: ""
  ```

Some containerd configuration locations can be adjusted if needed, but the default values should be fine.

  ```yml
  containerd:
    # Location generate config.toml file
    config_path: "/etc/containerd"

    # Location to place flannel.conflist
    flannel_conflist_path: "/etc/cni/net.d"
  ```

---

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
* When enabled, an expected result would be a dataset name such as: `rpool/ROOT/ubuntu_3wgs2q/var/lib/containerd` being created.
  * The mountpoint of the dataset does not need to be changed, but is defined in `vars/containerd.yml`.

[Back to README.md](../README.md)