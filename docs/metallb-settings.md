# MetalLB Load Balancer Settings

[Back to README.md](../README.md)

## Important Notes

* Pre-configured for Layer 2 which is the simplest to configure.
  * You don’t need any protocol-specific configuration, only IP addresses.

Layer 2 mode does not require the IPs to be bound to the network interfaces of your worker nodes. It works by responding to ARP requests on your local network directly, to give the machine’s MAC address to clients.

---

## Review `default/main.yml` for MetalLB Settings

The MetalLB Settings are in variable namespace `install.metallb`.

```yaml
  ###[ MetalLB Installation Settings ]#############################################################
  # When enabled this will disable k3s built-in Klipper Load Balancer and enable MetalLB instead.
  metallb:
    enabled: true

    # Select release to use:  https://github.com/metallb/metallb/releases
    # Alternate: https://metallb.universe.tf/installation/
    install_version: "v0.12.1"

    # Ranges of IP Addresses MetalLB can handout for LoadBalancer Services
    ip_ranges: 
      - "192.168.10.240-192.168.10.253"
```

* When `enabled` is `true` this will flag K3s to disable its own internal load balance called Klipper and use MetalLB Load Balancer instead.
* MetalLB is under rapid development, keep it pinned to a known working version.
* The `ip_ranges` allow multiple ranges to be defined. CIDR ranges are also supported:

```yaml
ip_ranges:
  - 192.168.12.0/24
  - 192.168.144.0/20
```

---

If you choose not to enable MetalLB initially, it can be enabled at a later point and the K3s Klipper Load Balancer will be disabled.  All existing LoadBalancer services will then be issued an IP Address from the MetalLB Load Balancer Pool within a few seconds.  

```shell
ansible-playbook -i inventory.yml kubernetes.yml --tags="install_k3s,install_metallb"
```

---

Once MetalLB was installed, Traefik was automatically assigned an `EXTERNAL-IP` from the MetalLB Pool:

```text
$ kubectl get services traefik -n kube-system

NAME      TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
traefik   LoadBalancer   10.43.227.65   192.168.10.240   80:30070/TCP,443:31909/TCP   2d1h
```

The IP address used by Traefik is no longer tied to a specific node IP, it is now node independent.

---

## Additional Documentation

### Important Info from the FAQ

How to specify the host interface for an address pool?

* There’s no need: MetalLB automatically listens/advertises on all interfaces. That might sound like a problem, but because of the way ARP/NDP works, only clients on the right network will know to look for the service IP on the network.

  * NOTE Because of the way layer 2 mode functions, this works with tagged vlans as well. Specify the network and the ip stack figures out the rest.

* [MetalLB FAQs](https://metallb.universe.tf/faq/)

---

## Removing MetalLB Installation

1. Uninstall Manifest File

    ```shell
    cd /home/kube/metal_lb
    kubectl delete -f metallb.yaml-v0.12.1-manifest.yaml 
    ```

2. Uninstall ConfigMap

    ```shell
    kubectl delete -f configmap.yaml
    ```

3. Uninstall Namespace

    ```shell
    kubectl delete -f namespace.yaml-v0.12.1-manifest.yaml
    ```

4. Disable MetalLB in `defaults/main.yml`

    ```yml
    metallb:
      enabled: false
    ```

5. Run K3s installation to enable default LoadBalancer

  ```shell
  ansible-playbook -i inventory.yml kubernetes.yml --tags="install_k3s"
  ```

Once K3s installation scripts completes, the LoadBalancer address of Traefik will return to just being the Node IP address within a few seconds.

```text
$ kubectl get services traefik -n kube-system

NAME      TYPE           CLUSTER-IP     EXTERNAL-IP      PORT(S)                      AGE
traefik   LoadBalancer   10.43.227.65   192.168.10.110   80:30070/TCP,443:31909/TCP   2d1h
```

[Back to README.md](../README.md)
