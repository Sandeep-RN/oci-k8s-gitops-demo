# 0022. Moving the demo from OKE to k3s: edge without a load balancer, reused sealing key, data moved, rebuild on the same VM

Status: Accepted (2026-11-11). Decided by the owner on 2026-11-03; the client-IP and DNS-address parts were decided on 2026-11-11 after a live test. Amends ADR 0001 (rebuild), 0004 and 0012 (no NLB on k3s), 0015 (the free NLB is not kept for k3s) and the k3s parts of ADR 0020.

## Context
The k3s node exists since 2026-11-11 (A1, 2 OCPU / 12 GB, k3s v1.36.5+k3s1, PAYG per ADR 0021). OKE serves `https://demo.sandeeprn.in` until its teardown (#13, by 2026-11-15), and its last nightly backup expires 14 days after it is written. Everything that runs on OKE has to move: the edge, the secrets, the data. The plan (ADR 0004) put a Network Load Balancer in front of k3s. OKE holds the one free NLB until #13.

Facts checked before deciding:

- **The node sees only its private IP.** OCI assigns the public IP to the VNIC's private IP object and maps it outside the VM. `ip addr` shows only the private address, and the k3s node has an `InternalIP` and no `ExternalIP`.
- **So ServiceLB reports the private IP.** The built-in Traefik's `LoadBalancer` Service status was the node's private VCN address (`ipMode: VIP`). k3s's ServiceLB uses the node's external IP if it has one, otherwise the internal IP ([k3s docs](https://docs.k3s.io/networking/networking-services)). external-dns publishes the Ingress status, which Traefik copies from that Service. Left as it is, `demo.sandeeprn.in` would point at a private address. The OKE fix of ADR 0020 (exclude private ranges) would then leave nothing to publish.
- **The visitor's IP reaches the node.** OCI's mapping changes only the destination. A packet capture on the node (2026-11-11, 4 requests over 80 and 443 from the owner's laptop) showed the client's own address arriving on the node's interface. kube-proxy then catches the traffic because its destination (the private IP) equals the Service's status address, and sends it straight to the Traefik pod; the ServiceLB pod is not in the path. What the Traefik pod saw:

  | Traefik Service `externalTrafficPolicy` | Source address at the Traefik pod |
  |---|---|
  | `Cluster` (k3s default) | `10.42.0.1`, the pod network gateway, for every client |
  | `Local` (patched for the test, then reverted) | the client's real address |

- **`node-external-ip` would break that.** It is k3s's usual answer to the first two points, but the k3s docs' Known Issues say that behind NAT (public clouds) it breaks `externalTrafficPolicy: Local`. The capture shows why: with the public IP as the status address, packets (which carry the private IP) would no longer match kube-proxy's rule.
- **An ephemeral public IP lives as long as the instance.** Oracle: it "exists only for the lifetime of the instance", stays assigned across stop and start, and is released when the instance is terminated or its VNIC detached ([docs](https://docs.oracle.com/en-us/iaas/Content/Network/Tasks/managingpublicIPs.htm)). It cannot be converted to a reserved IP later.

## Decision

**Edge**
- **No load balancer on k3s.** Traffic goes to the node's ephemeral public IP, then to k3s's built-in Traefik (ADR 0020's choice for k3s) through ServiceLB. The node's security list allows TCP 80 and 443 from `web_allowed_cidr` (default anywhere; PR #124, applied 2026-11-11). It is the only inbound gate, since the host firewall is open (ADR 0012). Port 80 only redirects to HTTPS; certificates use DNS-01 (ADR 0005).
- **No reserved IP** (as in ADR 0020). The node is never destroyed (below), so its ephemeral IP is stable in practice.
- **Traefik's Service uses `externalTrafficPolicy: Local`**, set in the gitops repo (k3s's `HelmChartConfig` for the bundled chart, W4). Traefik then sees real client IPs, so the per-IP rate limit counts each client separately on k3s, with no proxy protocol (#97). On one node, `Local` has no downside: the only Traefik pod is always local.
- **`node-external-ip` is not set.** It would break `Local`.

**Public address in DNS**
- **Traefik writes the public IP into the Ingress status**: `--providers.kubernetesingress.ingressendpoint.ip=$(PUBLIC_IP)`, with `PUBLIC_IP` an env var read from a SealedSecret. Kubernetes expands `$(VAR)` in container arguments. A plain Traefik env var would not work: Traefik's install configuration comes from exactly one source (file, CLI arguments or environment, "mutually exclusive"), and the chart uses CLI arguments. The chart's `publishedService` is turned off, so the two cannot compete (Traefik's docs do not state which wins).
- The IP is not secret once DNS publishes it. It is sealed only because the repos are public and never hold IPs in plain text, and so the value lives in one place.
- **external-dns on k3s is configured as on OKE** (ADR 0020): Ingress source, `--policy=sync`, a k3s-specific TXT owner id, and the private-range exclusion kept as a guard.
- Verified before the DNS switch: the Ingress status shows the public IP, and `curl --resolve demo.sandeeprn.in:443:<ip>` gets a valid certificate.
- Rejected: `node-external-ip` (breaks `Local`); the IP in plain text in a manifest or external-dns annotation (public repo); external-dns default targets (behaviour differs between versions and was not verified).
- Fallback, if the argument does not reach the Ingress status: set `node-external-ip` and go back to `Cluster`. DNS then works, but the rate limit becomes a shared flood guard, as on OKE today.

**Secrets**
- **Reuse the OKE Sealed Secrets keys on k3s.** Restore every key from the offline backup before the controller starts (ADR 0006 order), then reuse the sealed files unchanged. The namespaces and names stay the same, so the default strict scope still decrypts them. The key backup is **kept** at the OKE teardown (#13); it is now the k3s key.
- This replaces "keys are per cluster" in `docs/runbooks/sealed-secrets.md` for this move.

**Data**
- **Restore OKE's last nightly backup into k3s Postgres** (`docs/runbooks/postgres-backup-restore.md`), so links that already exist, like the landing page's example, keep working. Do it within 14 days of that backup (bucket lifecycle). The bucket lives in `terraform/shared` and survives #13.
- **Backup object names and backup alerts carry a cluster label** (W5), so the two clusters cannot overwrite or mask each other's backups during the overlap.

**Rebuild proof (#57) on the same VM**
- Prove "rebuild from clean state" (ADR 0001) by removing k3s from the node (`k3s-uninstall.sh`) and rebuilding the cluster: bootstrap script, ArgoCD, sealing key, data restore. The VM, its boot volume and its IP are never destroyed. `prevent_destroy` stays.
- The Terraform side is proven by a clean `terraform plan` from a fresh checkout (no changes), not by destroying the instance.

**Cutover**
- A dark period for the URL is acceptable (it is not published anywhere yet).
- Order: k3s edge ready and verified with `curl --resolve` → delete the OKE Ingress, so OKE's external-dns deletes its record → k3s's external-dns creates its own → `scripts/verify-public-url.sh --production --hsts` → OKE teardown (#13).

## Consequences
- The edge on k3s costs nothing and has one moving part fewer than OKE's (no NLB, no cloud controller).
- **Per-client rate limits work on k3s**, which OKE never had (#106, #97). The limit values can go back to per-client numbers; that is part of the k3s overlay.
- **No node-level redundancy at the edge.** A Traefik restart or a node reboot is an outage. That is already true of a single node (ADR 0001).
- **DNS no longer follows the IP automatically on k3s.** If the public IP ever changes (only if the instance is terminated or its VNIC replaced), re-seal `PUBLIC_IP`. The record then follows by itself.
- The node's IP is exposed directly. A Service that binds another port through ServiceLB stays unreachable unless the security list is changed, which needs a reviewed Terraform change.
- One set of sealing keys spans both clusters. OKE is torn down in days; the keys still rotate every 30 days, and each renewal still needs a fresh backup.
- Not tested: whether a pod on the node can reach the public hostname (hairpin through OCI's internet gateway). Probes keep avoiding it (ADR 0008, 0019).
- ADR 0015's "the free NLB stays reserved for k3s" and ADR 0012's "80/443 from the NLB" no longer apply to k3s.
- No non-free resource is created by this ADR.

## At scale
Several nodes behind a load balancer that keeps client IPs (proxy protocol, or a cloud controller that sets `externalTrafficPolicy: Local` up correctly), a reserved or anycast entry point instead of a node's own IP, the public address taken from cloud metadata by a controller rather than sealed by hand, per-cluster sealing keys with a managed secrets store (ADR 0006), and backups named per cluster from day one.
