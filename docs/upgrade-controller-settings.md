# System Upgrade Controller Settings & Important Notes

[Back to README.md](../README.md)

The [K3s System Upgrade Controller](https://github.com/rancher/system-upgrade-controller) is deployed to the `system-upgrade` namespace and `system-upgrade` ArgoCD project.  It is used to perform rolling upgrades to newer Kubernetes releases when available.

## Important Notes

* Only nodes that have been labeled with `k3s-upgrade=true` will be upgraded
  * Any node missing this label or set to `false` or `disabled` will not be upgraded until the value is set to `true`
* Be careful skipping versions or not upgrading all nodes within the cluster
  * Understand Kubernetes [Version Skew Policy](https://kubernetes.io/releases/version-skew-policy/)

### The Upgrade Process

* When a new K3s release is made available [See Releases](https://github.com/k3s-io/k3s/releases)
* Renovate will create the Pull Request for your review and approval
* Once approved, within minutes the controller will start to upgrade the master nodes one by one and then the worker nodes.

## Review `defaults/main.yml` for Upgrade Controller Settings

The System Upgrade Controller Settings are in variable namespace `install.upgrade_controller`.

> Enable or Disable Installation of System Upgrade Controller:

  ```yaml
  install:
    upgrade_controller:
      enabled: true
  ```

> Pin which version of System Upgrade Controller to install:

* This is the application version on GitHub, currently no Helm charts available.

  ```yaml
    # Select release to use: https://github.com/rancher/system-upgrade-controller/releases
    install_version: "{{system_upgrade_controller_install_version|default('v0.10.0')}}"
  ```

> Define the Namespace to Install System Upgrade Controller into:

* The typical namespace used for Sealed Secrets is `system-upgrade` however you can specify an alternate name.

  ```yaml
    namespace: "system-upgrade"
  ```

> Define ArgoCD Project to associate with:

* This defines which ArgoCD application System Upgrade Controller will be associated with.

  ```yaml
    argocd_project: "system-upgrade"     # ArgoCD Project to associate this with
  ```

You can define different steps for control plane nodes vs worker nodes in regards to cordon and uncordon or drain the node, etc. The settings are stored in plan files.  The plan get the initial settings from these values:

```yaml
    control_node_upgrade_plan: |
      #cordon: true
      drain:
        force: true
        deleteLocalData: true
        ignoreDaemonSets: true
        skipWaitForDeleteTimeout: 60 # honor pod disruption budgets up to 60 seconds per pod then moves on
```

```yaml
    worker_node_upgrade_plan: |
      #cordon: true
      drain:
        force: true
        deleteLocalData: true
        ignoreDaemonSets: true
        skipWaitForDeleteTimeout: 60 # honor pod disruption budgets up to 60 seconds per pod then moves on
```

[Back to README.md](../README.md)
