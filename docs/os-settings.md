# Linux OS Settings & Important Notes

[Back to README.md](../README.md)

Review the non-root user account that will be created for Kubernetes with optional passwordless access to `kubectl` command:

```yaml
install:
  os:
    non_root_user:
      name: "kube"
      shell: "/bin/bash"
      groups: "sudo"

    allow_passwordless_sudo: true
```

* This allows for a simple `sudo su - kube` command to reach the account with Kubernetes access.

---

Review the packages which will be removed from the base Ubuntu Linux installation:

```yaml
  remove_packages:                             
    enabled: true
    packages:
      - "snapd"                             # Remove Snapd Demon, we don't need it.
```

* To disable package removal set `enabled: false` you can add additional package names to the list of packages to uninstall.

---

Sysctl modifications to be applied to `/etc/sysctl.conf`:

```yaml
  sysctl_updates:
    fs.inotify.max_user_instances: 8192
    fs.inotify.max_user_watches: 524288
```

[Back to README.md](../README.md)
