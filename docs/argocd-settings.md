# ArgoCD Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* ArgoCD will be used to deploy & monitor changes to deployed applications.
* ArgoCD requires a Git repository (GitHub) to store its configuration.
  * A Private repository is recommended and supported by default.
  * This should be a empty repository dedicated to ArgoCD's usage.

### Empty Repository

If the repository is empty:

* The empty repository is cloned to establish a git directory structure.
* This Ansible script renders a set of default application manifests files to built the cluster services.
* The rendered ArgoCD manifest is used to install ArgoCD via rendered Helm Chart.
* The rendered manifest files are checked into the repository, thus no longer empty.
* ArgoCD is configured to monitor this repository and deploy whatever applications are not yet deployed.

### Populated Repository

* The repository is cloned as-is.
* This ansible script will render missing files into the repository.
  * Might mess up existing files if they are different!
* Any updated files are checked into the repository.
* ArgoCD is configured to monitor this repository and deploy whatever applications are not yet deployed.

---

## Troubleshooting ArgoCD

### Early Access to ArgoCD Dashboard

The early initial installation will not have an ingress controller.  To get early access the ArgoCD dashboard to check connectivity to repository and status of deployments:

#### Create a Port Forward

Assuming K3s is not on your local machine, this will open a port accessible external to the cluster:

```shell
$ kubectl port-forward -n argocd svc/argocd-server 8080:80 --address='0.0.0.0'

Forwarding from 0.0.0.0:8080 -> 8080
```

#### Open Web Browser

Point your web browser to the cluster node IP or hostname using port 8080:

`http://k3shost.example.com:8080/argocd/`

You should now see the ArgoCD login page.  The default credentials if you did not change them:

* Username: `admin`
* Password: `password`

---

### Monitor ArgoCD Repository Logs

The ArgoCD repository server might provide additional troubleshooting information:

```shell
kubectl logs pod/argocd-repo-server-b884f4bc5-nsr8q -n argocd
```

* Adjust the pod name to match whatever your instance shows.

[Back to README.md](../README.md)
