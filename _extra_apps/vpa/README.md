# Vertical Pod AutoScaler (VPA)

While the full Vertical Pod Autoscaler (VPA) frees the user from setting up-to-date RAM and CPU resource limits and requests for the containers in their pods by configuring requests _automatically_ based on usage.  

[Return to Application List](../)

* This installation only enables the `recommender` portion of VPA
  * It monitors the current and past resource consumption and, based on it, provides recommended values for containers' cpu and memory requests
* It does not enable the automated modifications of container settings or admission controller
* Historical information to base recommendations on is pulled from Prometheus

This provides information to [Goldilocks](../goldilocks/) which exposes a dashboard to review current settings and recommendations.

* Helm based ArgoCD application deployment.

Review `vpa/applications/vpa.yaml`

* No changes should be needed.  This section defines the name of the Prometheus service to get information from:

  ```yaml
  extraArgs: 
    prometheus-address: |
      http://prometheus-operated.monitoring.svc.cluster.local:9090
    storage: prometheus
  ```

Once installed, it is just a single pod running:

```shell
$ kubectl get pods -n vpa

NAME                                                      READY   STATUS    RESTARTS   AGE
vertical-pod-autoscaler-vpa-recommender-75bc5b795-zfzfb   1/1     Running   0          5h14m
```

There is no interface for VPA.  Goldilocks will be used for that.  You can monitor the pod logs for activity which will look something like this once Goldilocks is enabled.

```text
I0528 23:18:29.440695       1 recommender.go:184] Recommender Run
I0528 23:18:29.440749       1 cluster_feeder.go:349] Start selecting the vpaCRDs.
I0528 23:18:29.440759       1 cluster_feeder.go:374] Fetched 6 VPAs.
I0528 23:18:29.440845       1 cluster_feeder.go:384] Using selector app.kubernetes.io/name=argocd-redis for VPA argocd/goldilocks-argocd-redis
I0528 23:18:29.440909       1 cluster_feeder.go:384] Using selector app.kubernetes.io/instance=argocd,app.kubernetes.io/name=argocd-repo-server for VPA argocd/goldilocks-argocd-repo-server
I0528 23:18:29.440957       1 cluster_feeder.go:384] Using selector app.kubernetes.io/instance=argocd,app.kubernetes.io/name=argocd-server for VPA argocd/goldilocks-argocd-server
I0528 23:18:29.440999       1 cluster_feeder.go:384] Using selector app.kubernetes.io/instance=argocd,app.kubernetes.io/name=argocd-application-controller for VPA argocd/goldilocks-argocd-application-controller
I0528 23:18:29.441040       1 cluster_feeder.go:384] Using selector app.kubernetes.io/instance=argocd,app.kubernetes.io/name=argocd-applicationset-controller for VPA argocd/goldilocks-argocd-applicationset-controller
I0528 23:18:29.441158       1 cluster_feeder.go:384] Using selector app.kubernetes.io/instance=argocd,app.kubernetes.io/name=argocd-notifications-controller for VPA argocd/goldilocks-argocd-notifications-controller
I0528 23:18:29.469477       1 metrics_client.go:73] 71 podMetrics retrieved for all namespaces
I0528 23:18:29.470354       1 cluster_feeder.go:460] ClusterSpec fed with #210 ContainerUsageSamples for #105 containers. Dropped #0 samples.
I0528 23:18:29.470382       1 recommender.go:194] ClusterState is tracking 74 PodStates and 6 VPAs
I0528 23:18:29.546281       1 recommender.go:204] ClusterState is tracking 66 aggregated container states
```

[Return to Application List](../)
