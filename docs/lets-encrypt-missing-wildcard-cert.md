# Let's Encrypt Missing Wildcard Certificate

[Back to README.md](../README.md)

## Important Notes

* An ArgoCD sync issue can prevent Let's Encrypt from generating the Wildcard certificate needed to allow Traefik ingress from working.  This prevents you from logging in to ArgoCD to force a Sync to resolve the issue.
* This has only been observed during a fresh cluster installation.

The following steps use the ArgoCD CLI to force a resync to allow the certificate to be generated.

---

If no Let's Encrypt certificates have been generated during a fresh cluster installation, you can check the status using the ArgoCD CLI.

```shell
$ kubectl get certificates -A
No resources found

```

The following will fetch the ArgoCD CLI password and log you into the ArgoCD CLI environment:

```shell
$ ARGOIP=$(kubectl get svc argocd-server -n argocd -o jsonpath='{.spec.clusterIP}')

$ argocd login --plaintext ${ARGOIP} --username admin --password password
'admin:login' logged in successfully
Context '10.43.67.241' updated
```

Once logged in, you can query ArgoCD about Traefik:

```shell
$ argocd app list | grep traefik

argocd/traefik                  https://kubernetes.default.svc  traefik         ingress         Synced     Healthy   Auto-Prune  <none>                             https://helm.traefik.io/traefik                                                      18.1.0
argocd/traefik-config           https://kubernetes.default.svc  traefik         ingress         OutOfSync  Healthy   Auto-Prune  RepeatedResourceWarning,SyncError  https://github.com/reefland/k3s-argocd-test.git  workloads/traefik-config/           HEAD
```

* Note the status of the 2nd entry for `traefik-config` is `OutOfSync` and is stuck in this state.

Force ArgoCD to re-sync the `traefik-config` application:

```shell
$ argocd app sync traefik-config

# Look for output such as:

2022-12-13T09:39:34-05:00  cert-manager.io  Certificate     traefik         wildcard-cert  OutOfSync  Missing              certificate.cert-manager.io/wildcard-cert created
2022-12-13T09:39:34-05:00  cert-manager.io  Certificate     traefik         wildcard-cert    Synced  Progressing              certificate.cert-manager.io/wildcard-cert created
2022-12-13T09:39:35-05:00  cert-manager.io  Certificate     traefik         wildcard-cert    Synced  Degraded              certificate.cert-manager.io/wildcard-cert created

# After a few minutes....

2022-12-13T09:42:06-05:00  cert-manager.io  Certificate     traefik         wildcard-cert    Synced  Healthy              certificate.cert-manager.io/wildcard-cert created

```

Now the `wildcard-cert` now shows `Synced` and `Healthy` has been created:

```shell
$ kubectl get certificates -A

NAMESPACE   NAME            READY   SECRET          AGE
traefik     wildcard-cert   True    wildcard-cert   38m
```

* Traefik ingress via HTTPS should now be functional.

[Back to README.md](../README.md)
