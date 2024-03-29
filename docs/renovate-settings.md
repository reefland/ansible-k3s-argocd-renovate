# Renovate Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* Renovate is a Kubernetes scheduled job that runs on a defined schedule to check for application updates for the applications defined in the Git repository
* Renovate configuration via Ansible will attempt parse the Git URL and Access Token defined for ArgoCD to the formats required by Renovate. Seems to work, might not be fool-proof. You can override values if needed
* Renovate will open a Pull Request when an application upgrade is detected
  * After the 1st run it will open a Pull Request as an introduction to the process so you have an idea what to expect
  * See [Example of Initial PR (Pull Request)](renovate-workflow-example.md)
  * See [Example of Application Upgrade PR (Pull Requests)](renovate-workflow-multi.md)

---

## Review `defaults/main.yml` for Renovate Settings

The Renovate Settings are in variable namespace `install.renovate`.

* Pin which version of Renovate to install.  This is the Helm Chart version, not the application version.
  * This is for initial installation only. Do not update this value to attempt to push an application upgrade.

  ```yaml
  install:

    renovate:
      # Select Release to install: https://github.com/renovatebot/helm-charts/releases
      install_version: "{{renovate_install_version|default('32.152.0')}}"
  ```

* Define the namespace to install Renovate into.

  ```yaml
      namespace: "renovate"
  ```

* Define Repository Connection Settings

  ```yaml
      platform: "github"
      repositories:
        - "{{argocd_repo_url|default('UNDEFINED_REPO_URL') | urlsplit('path') | regex_replace('^\\/|\\/$, ''') }}"    # Hopefully the <user>/<repo-name> part of URL
  ```
  
  * The URL for the ArgoCD Git URL is parsed determine repo name
    * Hopefully something like `<user>/<repo-name>` is detected, you can set manually if you like
  * Multiple repositories for the platform can be defined

* Define Schedule for Renovate Job.

  ```yaml
      # Cron style schedule when renovate should look for updates
      schedule: "0 1 * * *"                     # At 01:00 every day
  ```
  
  * Define when the Renovate job should run.  This is a Cron style schedule.

---

## Renovate Deployed Configuration

Renovate can be customized to perform additional functionality.  The renovate runtime configuration file is located at the root of the repository named `renovate.json`. The default contents have been modified to support ArgoCD application files:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": [
    "config:base",
    ":semanticCommits",
    "github>{{argocd_repo_url|default('UNDEFINED_REPO_URL') | urlsplit('path') | regex_replace('^\\/|\\/$, ''') }}//.github/renovate/labels.json5",
    "github>{{argocd_repo_url|default('UNDEFINED_REPO_URL') | urlsplit('path') | regex_replace('^\\/|\\/$, ''') }}//.github/renovate/semanticCommits.json5"
  ],
  "argocd": {
    "fileMatch": [
      "applications/.+\\.yaml$",
      "workloads/.+\\.yaml$"
      ]
  },
  "regexManagers": [
    {
      "description": "Update Democratic-csi docker image references",
      "fileMatch": ["^applications\\/democratic_csi_.*\\.yaml$"],
      "matchStrings": ["image: (?<depName>.*?):(?<currentValue>.*?)\\s+"],
      "datasourceTemplate": "docker"
    },
    {
      "description": "Process various dependencies",
      "fileMatch": [
        "applications/.+\\.ya?ml$",
        "workloads/.+\\.ya?ml$"
      ],
      "matchStrings": [
        "datasource=(?<datasource>\\S+) depName=(?<depName>\\S+)( versioning=(?<versioning>\\S+))?\n.*?\"(?<currentValue>.*)\"\n"
      ],
      "datasourceTemplate": "{{#if datasource}}{{{datasource}}}{{else}}github-releases{{/if}}",
      "versioningTemplate": "{{#if versioning}}{{{versioning}}}{{else}}semver{{/if}}"
    },
    {
      "description": "Process raw GitHub URLs",
      "fileMatch": [
        "applications/.+\\.ya?ml$",
        "workloads/.+\\.ya?ml$"
      ],
      "matchStrings": [
        "https:\\/\\/raw.githubusercontent.com\\/(?<depName>[\\w\\d\\-_]+\\/[\\w\\d\\-_]+)\\/(?<currentValue>[\\w\\d\\.\\-_]+)\\/.*"
      ],
      "datasourceTemplate": "github-releases",
      "versioningTemplate": "semver"
    }
  ]
}
```

* Renovate Documentation: [https://docs.renovatebot.com/](https://docs.renovatebot.com/)
* The `argocd` > `fileMatch` enables processing of ArgoCD application files
* The `regexManagers` covers special case Docker image names within democratic-csi yaml files

---

## Renovate Config Validation Github Workflow

As Renovate runtime is a batch job that runs at intervals, you might not know for a while if a configuration change to the `renovate.json` is invalid.  The following GitHub workflow action is deployed to `.github/workflows` folder to help validate the configuration file.

```yaml
name: renovate-config-validator

on:
  pull_request:
    branches:
    - main
    paths:
    - .github/workflows/renovate-config-validator.yaml
    - renovate.json
  push:
    branches:
    - main
    paths:
    - .github/workflows/renovate-config-validator.yaml
    - renovate.json

jobs:
  validate:
    name: Validate
    runs-on: ubuntu-latest
    steps:
    - name: Checkout
      uses: actions/checkout@v3
    - name: Validate
      uses: rinchsan/renovate-config-validator@v0.0.11
      with:
        pattern: 'renovate.json'
```

---

## Troubleshooting Renovate

Renovate is not an application that runs all the time.  It is a Kubernetes job that is scheduled.  When scheduled it will creates pod(s) that are intended to run one time.  If you don't know how Kubernetes jobs work, see [documentation](https://kubernetes.io/docs/concepts/workloads/controllers/job/)

### Manually Run Renovate Job

You can check the ArgoCD dashboard to confirm that Renovate has been deployed.  However, connectivity is not tested until a job is run.  To schedule a job to run now:

```shell
$ kubectl create job -n renovate --from cronjob/renovate renovate-$(date +%s)

job.batch/renovate-1652114610 created
```

See Jobs Scheduled (Future, Present, Past):

```shell
$ kubectl get jobs -n renovate

NAME                  COMPLETIONS   DURATION   AGE
renovate-1652114610   0/1           54s        54s
```

You can add a `-w` to watch job until it completes:

```shell
$ kubectl get jobs -n renovate -w

NAME                  COMPLETIONS   DURATION   AGE
renovate-1652114610   0/1           16s        16s
renovate-1652114610   0/1           93s        93s
renovate-1652114610   1/1           93s        93s

```

* Renovate's initial job should finish quickly, this is a sign something is wrong.

See Status of Job's Pods:

```shell
$ kubectl get pods -n renovate

NAME                        READY   STATUS   RESTARTS   AGE
renovate-1652114610-sr7zf   0/1     Error    0          2m48s
renovate-1652114610-zfp5t   0/1     Error    0          86s
renovate-1652114610-6g5zz   0/1     Error    0          83s
renovate-1652114610-cc29s   0/1     Error    0          80s
renovate-1652114610-7n494   0/1     Error    0          77s
renovate-1652114610-jp6ql   0/1     Error    0          74s
renovate-1652114610-44wlb   0/1     Error    0          71s
```

* Clearly something is not right.  You can use the ArgoCD dashboard to look at the job and job logs, or you can get logs directly from the failed pod:

```shell
$ kubectl logs renovate-1652114610-sr7zf -n renovate

FATAL: Authentication failure
 INFO: Renovate is exiting with a non-zero code due to the following logged errors
       "loggerErrors": [
         {
           "name": "renovate",
           "level": 60,
           "logContext": "12iLmb1K3_LEP9witA1Ky",
           "msg": "Authentication failure"
         }
       ]
```

* Renovate was having trouble using the GitHub Personal Access Token I defined for ArgoCD.  To troubleshoot that, look at the secrets created in the `renovate` namespace and the values contained to make sure they are correct

* Update the Ansible settings as needed, run the playbook again and then created a new job which ran successfully:

```shell
$ kubectl get pods -n renovate

NAME                        READY   STATUS      RESTARTS   AGE
renovate-1652116383-wjc29   0/1     Completed   0          23s
```

---

### Job Cleanup

Failed jobs can not be restarted, they need to be deleted and scheduled again.

```shell
$ kubectl delete job renovate-1652114610  -n renovate

job.batch "renovate-1652114610" deleted
```

[Back to README.md](../README.md)
