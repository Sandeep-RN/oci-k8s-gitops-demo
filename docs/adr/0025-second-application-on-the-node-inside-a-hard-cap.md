# 0025. A second application on the node, inside a hard resource cap

Status: Accepted (2026-11-21). Decided by the owner after the 2026-11-21 review; the live checks are demo #196.

## Context
The node (ADR 0001) is the whole Always Free A1 allowance, 2 OCPU / 12 GB, so
there is no second free VM. A new application, the on-call assistant
(repository `oncall-assistant`), will run on the same node as the link
shortener. A read-only snapshot on 2026-11-17 showed CPU at 10% and memory at
41% (4925Mi), with pod memory requests at only 15% and limits at 38%. That
snapshot was taken before ArgoCD and Sealed Secrets got requests and limits
(gitops #75, 2026-11-21). Measured again on 2026-11-21 (demo #193): memory in
use 4.0 to 4.6 GiB (node-exporter 4003Mi, peak 4227Mi since the rebuild;
`kubectl top` 4598Mi), requests 22%, limits 59%, 36 GiB of the 47 GiB boot
disk free. The peak covers about 21 hours, so it is read again at M1. A budget of about 4 GB was set aside for all experiments
(staying under about 75% of node memory); the planned platform upgrades take
about 1.3 GB of it, Loki included.

Who gets memory on a node is decided in four separate places, and each reads
a different setting:

1. **The scheduler** reads requests. If a pending pod does not fit on paper,
   it may preempt pods of lower priority.
2. **A ResourceQuota** reads the namespace's total requests or limits and
   refuses a pod that would exceed them.
3. **The kubelet**, when the node runs low on memory, evicts pods ranked
   first by whether they use more than they requested, then by priority,
   then by how far over their request they are.
4. **The kernel OOM killer**, as a last resort, scores processes by QoS
   class and request size; *Guaranteed* pods (requests equal to limits for
   both CPU and memory) are killed last.

The node's requests are far below 12 GB, so step 1 almost never preempts
anything. Protection against real memory pressure has to come from limits.

## Decision
- **Own namespace, own database, own ArgoCD Application.** The assistant
  gets its own namespace, its own Postgres with pgvector (the link
  shortener's `postgres:18.6-alpine` image lacks it; the pgvector image is
  pinned by digest and must have an arm64 build), and its own Application in
  the gitops repo. Nothing is shared with the link shortener's database. It
  is served at `ask.sandeeprn.in` through the existing Traefik, cert-manager
  and external-dns, with its own per-client rate limit.
- **The platform owns the tenant's guardrails.** The namespace, its
  ResourceQuota and LimitRange, and the PriorityClass are deployed by a
  platform Application, not by the assistant's. The assistant's Application
  runs in its own ArgoCD AppProject (the existing `demo` project allows only
  the `link-shortener` namespace) that may deploy only into the assistant's
  namespace and may not create ResourceQuota, LimitRange or PriorityClass
  objects. A change to the assistant's folder therefore cannot raise its own
  cap.
- **The database is a cache.** Everything in it is rebuilt by re-indexing
  public documents, so it is not backed up and uses no Object Storage. Its
  volume is local-path on the node's boot disk (no new block volume). An
  accidental prune of the Application (ADR 0023) loses nothing that cannot be
  rebuilt.
- **A hard cap on the namespace.** A ResourceQuota of 1 GiB of memory limits
  and 1 CPU of limits for everything in it, with a LimitRange supplying
  defaults so no pod runs uncapped. The cap is what protects the live site:
  about 4.9 GB in use plus at most 1 GiB stays near 50% of the node, well
  under the 75% line, however the assistant misbehaves.
- **A memory budget that fits the cap at peak**, with every pod running at
  once, not only in steady state. Starting point (tuned in M1):

  | Pod | Memory (request = limit) |
  |---|---|
  | App (API, page, query embedding) | 384Mi |
  | Postgres with pgvector | 256Mi |
  | Indexing Job | 384Mi |
  | **Total** | **1024Mi** |

- **No surge pods.** The app runs one replica with `strategy: Recreate`, and
  the indexing CronJob uses `concurrencyPolicy: Forbid`. A default rolling
  update starts a second app pod before stopping the old one; under a full
  quota that pod is refused and the rollout hangs. Recreate costs a short gap
  on each deploy, which the assistant's 99% target absorbs.
- **Embeddings run on ONNX Runtime with a small model** (MiniLM or bge-small
  class), with no PyTorch in the image. PyTorch alone needs more memory than
  the app's share.
- **Memory requests equal to memory limits**, so the scheduler counts what
  the pods really use.
- **A CPU limit, with the CPU request below it.** Unlike the link shortener
  (no CPU limit, to avoid throttling), the assistant is throttled when the
  node is busy. Keeping the CPU request below the limit keeps its pods
  *Burstable*, never *Guaranteed*, so the OOM killer does not prefer the live
  site over them.
- **A priority below the link shortener's.** A PriorityClass with a negative
  value and `preemptionPolicy: Never`. It applies at scheduling time only: if
  requests ever fill the node, the site's pods may preempt the assistant's,
  and the assistant never preempts anything. It does not make the assistant
  the kubelet's first eviction choice, because pods within their requests
  rank after pods above them.
- **Only the public provider's key enters the cluster.** The cluster holds
  the Groq API key and the demo tokens, both as SealedSecrets (ADR 0006).
  The development and eval key (KodeKey) stays on the developer's laptop and
  in CI secrets and is never stored in the cluster.

## Consequences
- The live site is protected by the cap and the headroom, not by priority:
  the assistant cannot use more than 1 GiB, and the node stays near half full.
- Priority matters only if requests fill the node. Under node memory
  pressure the kubelet may still evict a link shortener pod that is over its
  request before an assistant pod that is within it; the cap is what keeps
  that pressure from coming from the assistant.
- The assistant may be throttled when the node is busy, and each deploy
  causes a short gap. Its own SLO (99% over 7 days) is set with that in mind.
- The node's boot disk now also holds the pgvector image, the model and the
  index. Free space is checked before M1 (the disk alert is demo #140).
- M3's rule that the agent may reach only Prometheus and the API server
  depends on NetworkPolicy enforcement, which is not yet proven on this k3s
  node. It is proven by a test before M3.
- To verify in M1, read-only, with no manual changes: k3s v1.36 accepts the
  negative-value PriorityClass; the pods report the expected priority and QoS
  class `Burstable`; the quota refuses an over-cap pod in a server-side dry
  run (`kubectl apply --dry-run=server`; that quota is checked on dry runs is
  itself to be confirmed); the peak memory of each pod stays within its
  budget line.

## At scale
Each tenant gets its own node pool, kept apart with taints and tolerations,
so a tenant cannot share memory with a live service at all. Quotas,
LimitRanges, PriorityClasses and default NetworkPolicies come from a platform
template applied to every new namespace, not from per-application choices.
The vector store moves to a managed database with its own backups when its
contents can no longer be rebuilt cheaply.
