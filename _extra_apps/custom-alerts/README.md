# Custom Alerts for Prometheus Alertmanager

This is a collection of alerts to be added to AlertManger. Many of them I cherry picked from [Awesome Prometheus Alerts](https://awesome-prometheus-alerts.grep.to/), some of them needed to be tweaked.

[Return to Application List](../)

---

## Node Alerts

These alerts cover each node in the cluster.

| Alert Description       | Condition           | Duration to Trigger |
|---                      | ---                 |---                  |
| Host Out of Memory      | Less than 10%       | 5 minutes           |
| Host Under Memory Pressure | High Page Fault Count | 5 minutes      |
| Host out of Disk Space  | Less than 10% left  | 5 minutes           |
| Host Disk almost Full   | Less than 20% left  | 5 minutes           |
| Host High CPU Load      | More than 80% Avg   | 5 minutes           |
| Host OOM Kill Detected  | More than zero      | Within Past 5 minutes |
| Host Components too Hot | More than 75 Celsius | 5 minutes          |
| Host Network Interface Saturated | More than 80% | 5 minutes        |
| Host Clock Skew         | +/- 0.05 seconds    | 2 minutes           |

Example Alert sent to Slack Channel:
![Node too Hot Example Alert](node_too_hot_custom_alert.png)

---

## ArgoCD Sync Alerts

These alerts cover each application deployed.

| Alert Description       | Condition           | Duration to Trigger |
|---                      | ---                 |---                  |
| Application OutofSync   | More than zero      | 1 minute            |
| Application Sycn Failed | More than zero      | 1 minute            |
| Application Missing     | App not found       | 15 minutes          |

Example Alert sent to Slack Channel:
![ArgoCD Sync Failed](argocd_custom_alert.png)

---

## Traefik Ingress Alerts

| Alert Description         | Condition           | Duration to Trigger |
|---                        | ---                 |---                  |
| High HTTP 401 Error Count | 5% of past 3 minute traffic | 1 minute    |
| High HTTP 403 Error Count | 5% of past 3 minute traffic | 1 minute    |
| High HTTP 404 Error Count | 5% of past 3 minute traffic | 1 minute    |
| High HTTP 5xx Error Count | 5% of past 3 minute traffic | 1 minute    |

Example Alert sent to Slack Channel:
![Traefik High HTTP 401 Error Count](traefik_custom_alert.png)

---

## Longhorn Cluster Storage Alerts

| Alert Description           | Condition             | Duration to Trigger |
|---                          | ---                   |---                  |
| Cluster Storage at Capacity | Over 90% capacity     | 5 minutes           |
| Node Volume Fault           | Volume Fault          | 2 minutes           |
| Node Volume Degraded        | Volume Degraded       | 5 minutes           |
| Node Storage at Capacity    | Over 70% capacity     | 5 minutes           |
| Node Disk at Capacity       | Over 70% capacity     | 5 minutes           |
| Longhorn Node Down          | Node offline          | 5 minutes           |
| Instance Manager High CPU   | 3x CPU Request Limit  | 5 minutes           |
| Longhorn Node High CPU      | Over 90% CPU          | 5 minutes           |

---

[Return to Application List](../)
