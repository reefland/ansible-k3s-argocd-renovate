# Containerd Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* Ubuntu's `zsys` system snapshot creator does _not_ play nicely with containerd.  A dataset outside of its reach is created.

## Review `defaults/main.yml` for Containerd Settings

The Containerd Settings are in variable namespace `install.containerd`.

### Define ZFS Dataset for Containerd

A ZFS dataset will be created for containerd ZFS snapshotter support.  

* NOTE that Ubuntu's `zsys` system snapshot creator does _not_ play nicely with containerd.

The ZFS dataset should be created outside of `zsys` monitoring view. The following is a reasonable ZFS dataset configuration:

  ```yml
  install:
    containerd:
      zfs:
        detect_uuid: false
        pool: "rpool"
        dataset_prefix: "containerd"
        uuid: ""
        dataset_postfix: ""
  ```

---

### For Future Reference

When Ubuntu's `zsys` system snapshot creator supports disabling snapshots for specific datasets (this one) then the following would be designed for Ubuntu 20.04 based [ZFS on Root](https://github.com/reefland/ansible-zfs_on_root) installation where UUIDs are used in the dataset name.

```yml
install:
  containerd:
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
* When enabled, an expected result would be a dataset name such as: `rpool/ROOT/ubuntu_3wgs2q/var/lib/containerd`

[Back to README.md](../README.md)
