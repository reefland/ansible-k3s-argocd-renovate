# Rook-Ceph - Ceph Toolbox

The Rook toolbox is a container with common tools used for rook debugging and testing. See [Project Documentation](https://rook.io/docs/rook/v1.10/Troubleshooting/ceph-toolbox/) for more details.

The formal way to connect to the Toolbox is:

```shell
kubectl -n rook-ceph exec -it $(kubectl -n rook-ceph get pod -l "app=rook-ceph-tools" -o jsonpath='{.items[*].metadata.name}') -- bash
```

However, this simpler way works:

```shell
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
```

Once inside the Toolbox container you can run various CLI utilities.  You can also run specific CLI commands directly, handy for scripting:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph status

  cluster:
    id:     cb82340a-2eaf-4597-b83e-cc0e62a9d019
    health: HEALTH_OK
 
  services:
    mon: 3 daemons, quorum a,b,c (age 2h)
    mgr: a(active, since 2h)
    mds: 1/1 daemons up, 1 hot standby
    osd: 3 osds: 3 up (since 2h), 3 in (since 6d)
    rgw: 1 daemon active (1 hosts, 1 zones)
 
  data:
    volumes: 1/1 healthy
    pools:   12 pools, 241 pgs
    objects: 1.58k objects, 4.1 GiB
    usage:   11 GiB used, 2.0 TiB / 2.1 TiB avail
    pgs:     241 active+clean
 
  io:
    client:   767 B/s rd, 193 KiB/s wr, 1 op/s rd, 27 op/s wr
```

Status of the Placement Group balancer across OSDs:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph balancer status
{
    "active": true,
    "last_optimize_duration": "0:00:00.003001",
    "last_optimize_started": "Sun Nov 20 17:16:35 2022",
    "mode": "upmap",
    "optimize_result": "Unable to find further optimization, or pool(s) pg_num is decreasing, or distribution is already perfect",
    "plans": []
}
```

List Storage Devices used within cluster:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph device ls

DEVICE                               HOST:DEV       DAEMONS  WEAR  LIFE EXPECTANCY
Samsung_SSD_980_1TB_S64ANS0RB07316T  k3s01:nvme0n1  osd.0      6%                 
Samsung_SSD_980_1TB_S64ANS0T131593J  k3s02:nvme0n1  osd.1      5%                 
Samsung_SSD_980_1TB_S64ANS0T201060J  k3s03:nvme0n1  osd.2      5%                 
```

Show specifics about storage device:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph device info Samsung_SSD_980_1TB_S64ANS0RB07316T

device Samsung_SSD_980_1TB_S64ANS0RB07316T
attachment k3s01 nvme0n1 

osd.0
wear_level 0.06
```

Show Disk Space Usage for Storage Devices:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd df

ID  CLASS  WEIGHT   REWEIGHT  SIZE     RAW USE  DATA     OMAP     META     AVAIL    %USE  VAR   PGS  STATUS
 0   nvme  0.68359   1.00000  700 GiB  3.6 GiB  3.1 GiB   29 KiB  478 MiB  696 GiB  0.51  1.01  187      up
 1   nvme  0.68359   1.00000  700 GiB  3.5 GiB  3.1 GiB  367 KiB  441 MiB  696 GiB  0.51  1.00  188      up
 2   nvme  0.68359   1.00000  700 GiB  3.5 GiB  3.1 GiB  194 KiB  426 MiB  696 GiB  0.50  0.99  204      up
                       TOTAL  2.1 TiB   11 GiB  9.3 GiB  591 KiB  1.3 GiB  2.0 TiB  0.51                   
MIN/MAX VAR: 0.99/1.01  STDDEV: 0.00
```

List Storage Pools:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd lspools

1 ceph-blockpool
2 ceph-objectstore.rgw.control
3 ceph-objectstore.rgw.meta
4 ceph-filesystem-metadata
5 ceph-objectstore.rgw.log
6 ceph-filesystem-data0
7 ceph-objectstore.rgw.buckets.index
8 ceph-objectstore.rgw.buckets.non-ec
9 ceph-objectstore.rgw.otp
10 .rgw.root
11 ceph-objectstore.rgw.buckets.data
12 .mgr
```

Show OSD status and performance IOPS:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd status

ID  HOST    USED  AVAIL  WR OPS  WR DATA  RD OPS  RD DATA  STATE      
 0  k3s01  3668M   696G      2     32.0k      1        0   exists,up  
 1  k3s02  3635M   696G      8      133k      3      106   exists,up  
 2  k3s03  3632M   696G      5     56.7k      1        0   exists,up  
```

Show OSDs per Host:

```shell
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd tree  
ID  CLASS  WEIGHT   TYPE NAME       STATUS  REWEIGHT  PRI-AFF
-1         2.05078  root default                             
-5         0.68359      host k3s01                           
 0   nvme  0.68359          osd.0       up   1.00000  1.00000
-3         0.68359      host k3s02                           
 1   nvme  0.68359          osd.1       up   1.00000  1.00000
-7         0.68359      host k3s03                           
 2   nvme  0.68359          osd.2       up   1.00000  1.00000
```

[Return to Application List](../)
