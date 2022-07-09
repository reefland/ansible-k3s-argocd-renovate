# Kube-VIP Settings & Important Notes

[Back to README.md](../README.md)

## Important Notes

* **Kube-VIP** provides Load Balancer service for at least two critical Kubernetes services:
  1. The Kubernetes API service will be a shared virtual IP (vip) across all members of the control-plane.  You can then point an external `kubectl` or any product needing access to the API to this IP address instead of the IP address of a specific host.
  2. Can provide a LoadBalancer for services with a specified `loadBalancerIP: xxx.yyy.zzz.aaa`, if you want a pool of IP addresses to be available then Kube-VIP Cloud Provider service is used.

* **Kube-VIP cloud provider** Maintains a pool of IP address which can be assigned to any services of type LoadBalancer upon request.

The Traefik ingress controller will be the first service to request a Load Balancer IP address.  Once this has been completed, you can create a generic DNS cluster name pointing to this IP address to provide an ingress route hostname that is not specific to any individual Kubernetes host.

## Review `defaults/main.yml` for Kube-vip Settings

The Kube-vip Settings are in variable namespace `install.kube_vip`.

* Enable or disable installation of Kube-vip Load Balancer services.  When enabled (set to `true`) you must define several variables (see below).

  ```yaml
  install:
    kube_vip:
      # When enabled, you must define variable "vip_endpoint_ip" at host or group level within 
      # inventory, host_var or group_var file. This must be set to an IP address. This IP address will
      # be a Load Balanced VIP cluster wide for the API service.  You can point kubectl to this IP 
      # address.
      enabled: true
  ```

* Pin which version of Kube-vip to install. This value should be defined in the inventory file or group_vars file or can be updated directly here.

  ```yml
    # Select release to use: https://github.com/kube-vip/kube-vip/releases
    install_version: "{{kube_vip_install_version|default('v0.4.2')}}"
  ```

---

## Review `defaults/main.yml` for Kube-VIP Cloud Provider LB Settings

* Enable or disable the Kube-vip Cloud Provider as LoadBalancer.  By default this is enabled (set to `true`).
  * When enabled this will flag K3s to disable its own internal load balancer called Klipper and use Kube-VIP Cloud Provider Load Balancer instead.
  * When enabled you must define a variable named `vip_lb_ip_range` to hold the range of IP addresses to assign to LoadBalancer services (see sections further down ).

  ```yaml
  install:
    kube_vip:

    ...

      # To use Kube-VIP Cloud Provider to enable using an address pool with Kube-VIP
      lb:
        # When enabled, you must define variable "vip_lb_ip_range" at host or group level within 
        # inventory, host_var or group_var file. This must be set to an IP range or CIDR range.
        # This will define the pool of IP addresses to hand out to serviced of type LoadBalancer.
        enabled: true
  ```

* Pin which version of Kube-vip Cloud Provider Load Balancer to install. This value should be defined in the inventory file or group_vars file or can be updated directly here.

  ```yaml
        # Select release to use: https://github.com/kube-vip/kube-vip-cloud-provider/releases
        install_version: "{{kube_vip_cloud_provider_install_version|default('v0.0.2')}}
  ```

---

### Define Network Interface Kube-VIP will use

* You must define a variable named `vip_interface` with the network device name that the `vip_endpoint_ip` IP address will be available on.
  * If you know all hosts will have the same network device name this can be defined at an Ansible inventory group level otherwise define at the Ansible host level using the Ansible inventory file, host_var or group_var location.

NOTE: This example shows a YAML formatted inventory file, if you use INI then adjust accordingly (or use Ansible host_var files).

```yaml
k3s_control:
  hosts:
    k3s01.example.com:                  # Master 1
      vip_interface: "enp0s3"

    k3s02.example.com:                  # Master 2
      vip_interface: "enp01sf0"

    k3s03.example.com:                  # Master 3
      vip_interface: "eth0"

  vars:
    vip_endpoint_ip: "192.168.10.220"
    vip_lb_ip_range: "cidr-global: 192.168.10.221/30"   # 4 Addresses
```

### Define the Kube-vip API Load Balancer IP address

* You must define a variable named `vip_endpoint_ip` with the value of the IP address to use for the Kubernetes API load balancer.  This value must be hard coded and cannot be taken from the Load Balancer address pool.
  * This variable must be defined and accessible to primary cluster host(master #1). Can be defined in the Ansible inventory file, host_var or group_var location.

## Define Kube-vip Cloud Provider LoadBalancer IP Range

* You must define a variable named `vip_lb_ip_range` which contains the range of IP address range to use for the Load Balancer IP pool.  For simplicity a CIDR range is used above. Other methods can be used.
  * This variable must be defined and accessible to primary cluster host(master #1). Can be defined in the Ansible inventory file, host_var or group_var location.
* Using the example `192.168.10.221/30` the CIDR range `/30` will use 4 addresses starting from `192.168.10.221` so `.222`, `.223`, `.224` will be assigned to the pool.  If you change this to a `/29` then 8 address will be used, a `/28` is 16 addresses, etc.

---

Once the Kube-vip API Load Balancer is in place this can be confirmed with `cluster-info`:

```shell
$ kubectl cluster-info

Kubernetes control plane is running at https://192.168.10.220:6443
CoreDNS is running at https://192.168.10.220:6443/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://192.168.10.220:6443/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy
```

* The API Server, CoreDNS and Metrics Server are bound the the shared VIP address and will failover to other master cluster nodes.

[Back to README.md](../README.md)
