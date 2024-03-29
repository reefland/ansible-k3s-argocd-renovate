# Sealed Secrets Settings & Important Notes

[Back to README.md](../README.md)

Bitnami Labs [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) are designed to allow for storage of sensitive information, such as passwords, keys, certificates, OAuth tokens, and SSH keys encrypted in secrets in a way that is considered safe for public github repositories.  

_Without Sealed Secrets the default Kubernetes secret is only base64 encoded which anyone can decode and completely not safe for public git repositories._

## Important Notes

* Sealed Secrets are completely transparent to your applications and they require zero modifications to use sealed secrets.
* By default sealed secrets are specific to the namespace it is generated for and cannot be used outside this namespace (this can be changed at creation time using the `--scope` argument)
* Sealed Secrets is not a set and forget technology.  You should read the documentation and understand the key rotation frequency (~30 days) and process
* You should be able to convert existing secret YAML files with `kubeseal` into Sealed Secrets which are considered safe to check into git public repositories (private repository is still recommended)
* This Ansible role will install the version matched `kubeseal` CLI tool for creation of sealed secrets
* Existing Secrets created by this Ansible role can be converted to Sealed Secrets at a later date if you do not wish to use Sealed Secrets as part of the initial installation.
* It is easy to generate your own x509 master key and store it as an Ansible secret (see below) to allow sealed secrets to work on multiple clusters
  * Or can be used as part of a Disaster Recovery plan where this Ansible role is used to create a new cluster pointing to an existing git repository and ArgoCD will deploy everything as defined within the git repository (just sit back and watch!)

### How This Ansible Role Handles Sealed Secrets

* When Sealed Secrets is not enabled:
  * Any secrets created or processed by this Ansible role will NOT be persistent to the git repository
  * The YAML files are deleted from disk after being processed and before git changes are determined and committed to repository
* When Sealed Secrets is enabled:
  * Any new secrets created by this role will be converted to Sealed Secret and that is applied and retained within the repository; the original secret is deleted and not committed to repository
  * Any existing secrets (unsealed) originally created by this role upon being processed again will be annotated to assign management to the Sealed Secrets controller
  * Then the secret as stored within Ansible (not as deployed in cluster) will be regenerated and converted to a Sealed Secret
  * The converted Sealed Secret will be applied to cluster which overwrites the existing secret deployed
  * This may reset passwords back to default to reset configurations back to default
  * The Sealed Secret encrypted YAML file will be committed to the git repository and managed by ArgoCD
    * The raw YAML files will be under `/workloads/secrets` and can be managed within Argo-CD via the `app-secrets` Argo-CD application:

  ![ArgoCD Application Container for applied Sealed Secrets](../images/argocd_app-secrets_sealed.png)

---

It is important to understand how Sealed Secrets work.  Every 30 days a new signing key is generated.  Any new sealed secrets created after that will be signed with the new key and not the private key below.  

Overtime you will have many sealed secrets signed by different signing keys.  This is normal and a good thing.  However, older sealed secrets do not get re-encrypted with new keys.  It will be up to you to change passwords and re-seal (re-sign) with new keys from time to time.

## Review `vars/secrets/main.yml` for Sealed Secret Pregenerated Private Key

This is completely optional:  

You can have Sealed Secrets always generate a new private key with each installation.  However, no other installation will be able to decrypt the sealed secret YAML files.  By using your own Private Key you can share your initial sealed secrets across multiple clusters or restore a cluster from an existing git repository (you will need to extract all active signing keys). Remember every 30 days (default) new signing keys are generated automatically so multiple clusters will start to diverge.

Your private certificate and key can be stored within `vars/secrets/main.yml`:

```yaml
###[ Sealed Secrets Private Key ]##################################################################
# By default Sealed Secrets will generate its own private key upon installation.  These can not
# be shared across clusters or used to restore your cluster and make existing sealed secrets 
# reusable without you taking manual steps.  This section allows you to define your own reusable
# initial private keys for Sealed Secrets to use.

SEALED_SECRETS_PRIVATE_CERT_SECRET: |
  -----BEGIN CERTIFICATE-----
  MIIFQTCC...
  ...iO8+8hc=
  -----END CERTIFICATE-----

SEALED_SECRETS_PRIVATE_KEY_SECRET: |
  -----BEGIN PRIVATE KEY-----
  MIIJQwIB...
  ...EdgSteM=
  -----END PRIVATE KEY-----
```

To Generate your Own Private Certificate and Key:

``` shell
$ openssl req -x509 -nodes -newkey rsa:4096 -keyout tls.key -out tls.crt -subj "/CN=sealed-secret/O=sealed-secret"

Generating a RSA private key
.....................++++
...................................................................................++++
writing new private key to 'tls.key'
-----

$ ls tls*
tls.crt  tls.key
```

* Copy the contents of `tls.crt` under `SEALED_SECRETS_PRIVATE_CERT_SECRET`
* Copy the contents of `tls.key` under `SEALED_SECRETS_PRIVATE_KEY_SECRET`

**Be sure to encrypt all the secrets above when completed:**

```shell
ansible-vault encrypt vars/secrets/main.yml
```

Lastly make sure `use_pre_generated_private_key` is set to `true` in `defaults/main.yml` (see below) otherwise set this to `false`.

NOTE: The pregenerated key still expires within 30 days.  Trying to use it to see a new installation after it expires will fail as seen below.

```shell
fatal: [testlinux.rich-durso.us]: FAILED! => changed=true 
cmd: kubeseal --controller-name sealed-secrets --scope strict --format=yaml --controller-namespace sealed-secrets < "/home/kube/argocd/init_git_repo/workloads/secrets/argocd_admin_secret.yaml" > "/home/kube/argocd/init_git_repo/workloads/secrets/argocd_admin_secret-sealed.yaml"
delta: '0:00:00.049207'
end: '2022-08-08 19:35:39.534637'
msg: non-zero return code
rc: 1
start: '2022-08-08 19:35:39.485430'
stderr: 'error: failed to encrypt using an expired certificate on July 5, 2022'
stderr_lines: <omitted>
stdout: ''
stdout_lines: <omitted>


$ kubectl get secrets -n sealed-secrets sealed-secrets-key --show-labels
NAME                 TYPE                DATA   AGE   LABELS
sealed-secrets-key   kubernetes.io/tls   2      39m   sealedsecrets.bitnami.com/sealed-secrets-key=active


$ kubectl delete secret sealed-secrets-key -n sealed-secrets
```

The pregenerated key had to be deleted.  You can experiment with adjusting the expiration with `-days 365` perhaps.

---

## Review `defaults/main.yml` for Sealed Secrets Settings

The Sealed Secrets Settings are in variable namespace `install.sealed_secrets`.

> Enable or Disable Installation of Sealed Secrets:

* Disabled will prevent any secrets generated by this role from being committed to git repository.

  ```yaml
  install:
    sealed_secrets:
      enabled: true
  ```

> Pin which version of Sealed Secrets to install:

* This is the Helm Chart version, not the application version.
  * This is for initial installation only. Do not update this value to attempt to push an application upgrade.

  ```yaml
      # Select release to use: https://artifacthub.io/packages/helm/bitnami-labs/sealed-secrets
      install_version: "{{sealed_secret_install_version|default('v2.7.1')}}"
  ```

> Define the Namespace to Install Sealed Secrets into:

* The typical namespace used for Sealed Secrets is `kube-system` however you can specify an alternate name.

  ```yaml
      namespace: "sealed-secrets"
  ```

> Define ArgoCD Project to associate with:

* This defines which ArgoCD application Sealed Secrets will be associated with.

  ```yaml
      argocd_project: "security"     # ArgoCD Project to associate this with
  ```

> Determine if existing secrets (unsealed) should be replaced by Sealed Secrets:

* If you use this Ansible Role to create and operate the kubernetes cluster without Sealed Secrets enabled, and then enable Sealed Secrets at a later point any attempt to re-run role tasks again, you may see some failures when the task(s) process secrets already deployed
  * You will see a failure message such as:

  ```error
  Resource already exists and is not managed by Sealed Secret
  ```

* You will have to either delete the existing secret within the cluster to allow a new secret to be created by the role task and converted to Sealed Secret OR enable the option below to allow the existing secret to be annotated for Sealed Secret management
  * This will allow the unsealed secret to be replaced by a Sealed Secret without needing manual deletion
* Either way the contents of the original secret will be lost and the regenerated sealed secret will be whatever the default is by the role task.
  * However - once the initial conversion to Sealed Secrets is completed, this Ansible role will not overwrite your existing sealed secrets within the repository. It will simply skip past existing sealed secrets and will only add new ones as defined by tasks

  ```yaml
      # If a non-Sealed Secret (unsealed secret) already exists, by default it can NOT be replaced
      # by Sealed Secret version as it will fail with "Resource already exists and is not managed
      # by Sealed Secret" message. if replace_unsealed_secrets is "true" then the existing secret
      # will be annotated as managed by Sealed Secrets which will allow the non-Seale dSecret to be
      # replaced.
      replace_unsealed_secrets: true
  ```

> Use Pregenerated Private Key for Sealed Secrets:

* Have Sealed Secrets use your own pregenerated private certificate and private key that you stored within an ansible secret.  The benefit of using a pregenerated key includes being able to share your initial sealed secrets across multiple environments or being able to use it as part of a recovery process getting a new cluster to use an existing repository. (After the initial 30 days (default) new signing are automatically generated)

  ```yaml
      # By default Sealed Secrets will create a new private key with each installation and secrets
      # can only be decrypted in that cluster unless you manually manipulate the private keys. The
      # setting below when enabled will instead install your standard private key for Sealed 
      # Secrets which allows secrets to work across clusters and allows cluster to be restored from
      # git repository and re-use secrets encrypted with your standard private key. After initial
      # 30 days, new signing keys will be generated automatically and used for new sealed secrets.

      # if not enabled, then a new private key will be used each time Sealed Secrets is installed,
      # this is the default behavior.
      use_pre_generated_private_key: true
  ```

---

## Review `vars/main.yml` for Sealed Secrets Defaults

The Sealed Secrets Settings are in variable namespace `sealed_secrets`.

> Default Sealed Secret Controller Name:

This does not change the name to be using during installation.  This just lets Ansible know what the default controller name is.  This value will be used for all `kubeseal` commands and for the `kubeseal` alias with default controller name.

  ```yaml
  sealed_secrets:
    # This defines the default name used in Helm Chart, does not overwrite or change name to be used
    controller_name: "sealed-secrets"
  ```

> Default Scope for Sealed Secrets:

The default scope for sealed secrets is `strict` but you can change the default to a little more open and less restrictive if you have a need for it.

* `strict` (default): Sealed Secret uses secret name and the namespace. You can’t change the name or the namespaces of your SealedSecret once you've created it (it will not be decryptable)
* `namespace-wide`: This scope allows you to freely rename the SealedSecret within the namespace for which you’ve sealed the Secret
* `cluster-wide`: This scope allows you to freely move the Secret to any namespace within the cluster and rename it as you wish

  ```yaml
    default_scope: "strict"
  ```

> Default Annotation to Assigned to Unsealed Secrets:

To allow the Sealed Secrets controller to replace an existing unsealed secrets the secret will need to have an annotation applied to it.  Without this annotation the controller will refuse to replace it.

  ```yaml
    # Annotation that can be applied to an existing unsealed secret to mark it managed by Sealed
    # Secrets to allow it to be overwritten by Sealed Secrets.
    replace_unsealed_secrets_annotation: "sealedsecrets.bitnami.com/managed=true"
  ```

> Default Pregenerated Private Key Name:

If pregenerated private certificates and keys are enabled, this defined the name of the Kubernetes secret which Sealed Secrets will used for encrypting and decrypting Sealed Secrets.

  ```yaml
    # Define name of Sealed Secret Private to use
    use_pre_generated_private_key_name: "sealed-secrets-key"
  ```

> Default Label Sealed Secrets will use to Find Private Key:

The secret holding the private certificate and private key must have this label in order to be used by Sealed Secrets.

  ```yaml
  # Define label to be applied to pre-generated private key
  use_pre_generated_private_key_label: "sealedsecrets.bitnami.com/sealed-secrets-key: active"
  ```

---

## Using Sealed Secrets

### Converting a Secret into a Sealed Secret

Assuming you have an existing YAML file named `myapp-secret.yaml`, this can be converted into a Sealed Secret via:

```shell
kubeseal --controller-name sealed-secrets --controller-namespace sealed-secrets --scope strict --format=yaml < myapp-secret.yaml > myapp-secret-sealed.yaml
```

The file generated `myapp-secret-sealed.yaml` would be applied to the cluster by saving it within your git repository under `/workloads/secrets` and ArgoCD would apply this to the cluster.

However, if you needed to manually apply it for some reason:

```shell
kubectl apply -f myapp-secret-sealed.yaml [-n namespace-value]
```

The original secret `myapp-secret.yaml` should be deleted or stored someplace else with a fake value for future reference when you need to regenerate the secret.  The actual file with a real value should never be stored within your git repository.

### Recovering / Backup Sealed Secrets Public Key

This step will export the public key used by the controller.

```shell
kubeseal --controller-name sealed-secrets --controller-namespace sealed-secrets --fetch-cert > publickey.pem
```

### Recovering / Backup Sealed Secret Certificate and Private Key

These steps will export the certificate and private key used by the controller separately.

```shell
kubectl get secrets sealed-secrets-key -n sealed-secrets -o jsonpath='{.data.tls\.crt}' | base64 -d > tls.crt

kubectl get secrets sealed-secrets-key -n sealed-secrets -o jsonpath='{.data.tls\.key}' | base64 -d > tls.key
```

If you needed to reinstall the cluster from scratch with ArgoCD restoring applications as stored within your Git repository:

* You would need the certificate and private key above to be able to decrypt the secrets stored within your Git repository.
* Place the output of the above keys within: `vars/secrets/main.yml` under the variables `SEALED_SECRETS_PRIVATE_CERT_SECRET` and `SEALED_SECRETS_PRIVATE_KEY_SECRET`
* Then enable `use_pre_generated_private_key: true`.

This will instruct Ansible to create the secret before the Helm Chart is installed allowing Sealed Secrets to re-use the previous key instead of generating a new key at installation (which would not be able to decrypt existing keys).

* Note that the format within the `vars/secrets/main.yml` needs to be exact, proper spacing and no trailing spaces.  If it is not perfect, you might see an error such as this within the Sealed Secrets pod and the Helm Chart installation will fail:

  ```text
  2023/01/10 15:20:06 Searching for existing private keys
  2023/01/10 15:20:06 Error reading key sealed-secrets-key: data does not contain any valid RSA or ECDSA certificates
  panic: runtime error: index out of range [0] with length 0
  ```

### Recovering / Backup Sealed Secret Public and Private Key

This step will export the Public and Private keys into a single file.

```shell
kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >main.key
```

To restore from a backup after some disaster, just put that secrets back before starting the controller - or if the controller was already started, replace the newly-created secrets and restart the controller:

```shell
kubectl apply -f main.key
kubectl delete pod -n sealed-secrets -l name=sealed-secrets-controller
```

---

### Update Kubeseal Executable

While renovate will take care of upgrading Sealed Secrets application, there is nothing that takes care of keeping the `kubeseal` CLI utility updated.  To update the installed CLI to the version matched Sealed Secrets controller, you can just run the role with a single tag:

```shell
$ ansible-playbook -i k3s_test.yml k3s-argocd.yml --tags="update_kubeseal_cli"

...
TASK [k3s-argocd : Install KubeSeal Executable]*********************************************
Saturday 09 July 2022  14:36:55 -0400 (0:00:00.058)       0:00:04.169 ********* 
changed: [testlinux.example.com]
```

---

## Troubleshooting Sealed Secrets

### Reusing Sealed Secrets from Another Cluster

Sealed Secrets are specific to the cluster they were generated in.  Within the cluster resides the master signing key that was generated upon installation. Without that key trying to apply a sealed secret in a different cluster will not work, you will see a failure in the Sealed Secrets Controller log files:

```error
Sealed Secret failed for /home/kube/argocd/init_git_repo/workloads/secrets/argocd_admin_secret-sealed.yaml

Reason: no key could decrypt secret (admin.password, admin.passwordMtime, server.secretkey)
```

* Without the original master signing key you can not decrypt this sealed secret.  You will have to delete this secret and generate a new sealed secret, which will use this clusters signing key.

**IMPORTANT:** to allow Sealed Secrets to be used easily across multiple clusters then enable `use_pre_generated_private_key`, generate the certificate and private key and add them to the Ansible `vars/secrets/main.yaml` file. (Note this pregenerated key will still expire within 30 days.)

### Kubeseal reports Sealed Secrets Controller Not Found

The default sealed secrets controller name used by `kubeseal` is different than the default name used by Sealed Secrets installation.  This is expected:

```shell
$ kubeseal

error: cannot get sealed secret service: services "sealed-secrets-controller" not found

error: cannot get sealed secret service: services "sealed-secrets" not found
```

An alternate controller name can be supplied with argument `--controller-name sealed-secrets`. As this can be annoying to remember, this Ansible role will automatically create an alias for you that applies this argument:

```text
alias kubeseal='kubeseal --controller-name sealed-secrets --controller-namespace sealed-secrets'
```

---

### Monitor Sealed Secrets Controller Logs

The Sealed Secret controller can provide additional troubleshooting information when having issues with secrets:

```shell
kubectl logs pods/sealed-secrets-77c69dff5c-tb2mq -n kube-system
```

* Adjust the pod name to match whatever your instance shows.

[Back to README.md](../README.md)
