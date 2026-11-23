# Runbook: the k3s node (disk)

ADR 0001, ADR 0022, ADR 0025. The single Always Free A1 node that runs everything.
Today this page covers one thing, a disk that is filling up; add other node-level
problems (memory pressure, a reboot, a k3s upgrade) here when they happen.

Access: [k3s-access](k3s-access.md) (the tunnel for `kubectl`, and the SSH key
`~/.ssh/k3s-node` for the node itself). Read-only checks use `kubectl`; fixes that
change the cluster are pull requests to the gitops repo (ArgoCD syncs about 3
minutes after a merge), not hand edits.

## Facts

| | |
|---|---|
| Disk | One boot volume of about 50 GB, mounted at `/` (device `sda1`). It holds the OS, container images, k3s itself, the Postgres volumes of both apps, Prometheus data and the logs. k3s's `local-path` volumes are plain host directories, so a "volume" is not a separate disk |
| Why one alert, not one per volume | On `local-path`, `kubelet_volume_stats_*` reports the host disk for every PVC (measured 2026-11-23: all three show the same 50.9 GB and the same usage), so a per-volume alert would repeat this one |
| Prometheus | Keeps 8 days or 8 GB, whichever comes first (`retention` and `retentionSize` on the `Prometheus` object) |
| Backups | Postgres dumps go to Object Storage, not to this disk ([postgres-backup-restore](postgres-backup-restore.md)) |
| Where the alerts are | The gitops repo, `monitoring/k3s/platform-rules.yaml`. The chart's own `NodeFilesystemAlmostOutOfSpace` fires at 5% and 3% free, which is about where the kubelet starts evicting pods: the last line, not an early warning |

## Disk space low

Alert: `NodeRootDiskLow`, warning under 20% free for 30 minutes, critical under
12% free for 10 minutes (the critical one hides the warning). Both go to
Discord. The thresholds are a judgement, not a measurement: the kubelet's real
eviction threshold on this k3s could not be read (see "Not yet run" below). On a
50 GB disk, 20% is about 10 GB and 12% is about 6 GB.

What it means. Nothing has failed yet. If the disk keeps filling, the kubelet
first deletes unused images and then evicts pods, and a database that cannot
write stops answering. Find what grew before it gets there.

Look from the outside first, then on the node:

```bash
# Prometheus's own view (port-forward, then http://localhost:9090):
$K -n monitoring port-forward svc/kps-prometheus 9090 &
#   node_filesystem_avail_bytes{mountpoint="/"}                     free bytes now
#   deriv(node_filesystem_avail_bytes{mountpoint="/"}[6h]) * 86400    bytes per day (negative = filling)
#   prometheus_tsdb_storage_blocks_bytes                              Prometheus's own data
```

On the node (`ssh -i ~/.ssh/k3s-node ubuntu@<node-ip>`, the address comes from
`terraform -chdir=terraform/k3s output`; never paste it into a repo):

```bash
df -h /
sudo du -xh --max-depth=2 /var/lib/rancher/k3s | sort -h | tail -15   # images, volumes, containerd
sudo du -sh /var/lib/rancher/k3s/storage/*                            # one directory per local-path volume
sudo journalctl --disk-usage
sudo k3s crictl images                                                # what is cached
```

| What is big | Meaning | Action |
|---|---|---|
| `.../containerd` (images) | Unused images from old tags pile up | `sudo k3s crictl rmi --prune` removes images no running container uses |
| `.../storage/pvc-...` of Prometheus | Retention or the series count grew | Lower `retention` or `retentionSize` or the scrape set in `monitoring/kube-prometheus-stack/values.yaml`: a gitops pull request, not a hand edit |
| `.../storage/pvc-...` of a Postgres | The data grew. Find the table; the backups are not on this disk | Do not delete files under `storage/` by hand. Plan more space, see below |
| The systemd journal | Logs | `sudo journalctl --vacuum-size=200M` |

Afterwards, check the alert resolves and the free space holds for a day: a
cleanup that frees 3 GB while the disk fills 5 GB a day only buys time.

At scale. One disk for the OS, images and every database is the design limit
(ADR 0001, [roadmap](../roadmap.md) "Known limits"). The durable fix is a
separate block volume for the data, and a bigger or second node.

Not yet run on k3s: the alert has not fired on the real cluster, and the node
commands above have not been run on this node (the `du` paths follow k3s's
defaults). The kubelet's eviction thresholds could not be read from outside
(`configz` is not served), so check them on the node
(`sudo cat /etc/rancher/k3s/config.yaml`, and `ps aux | grep kubelet`) and write
the real numbers here.
