# 0020. TLS and the public hostname on OKE, with token-gated link creation

Status: Accepted (2026-10-27). Amends ADR 0004, 0013 and 0015.

## Context
The plan put Ingress, TLS and `demo.sandeeprn.in` on the k3s node (ADR 0004, 0005, 0013). The node does not exist: from 2026-10-22 to 2026-10-27 the home region (one availability domain) reported `OUT_OF_HOST_CAPACITY` for A1 at 2/12, 1/6 and 1/4, and for the E2.1.Micro shape too, under constant polling. Upgrading to Pay As You Go is ruled out (cost). OKE runs until 2026-11-15 (ADR 0015) and today serves the app over plain HTTP on the free Flexible Load Balancer, by IP.

Without a change, the portfolio would have no HTTPS URL and no TLS evidence at all. None of that work depends on k3s.

## Decision

**Edge**
- **Traefik** (Helm chart 42.1.3, Traefik v3.7.16) is installed on OKE by ArgoCD, with 2 replicas spread one per node and a PodDisruptionBudget, so the entry point survives a node drain like the app does. Traefik is also what k3s ships, so the same standard `Ingress` objects work on both targets. ingress-nginx was rejected: it was retired and its repository archived on 2026-03-24, with no further security fixes.
- **The free Network Load Balancer fronts Traefik**, with `oci.oraclecloud.com/load-balancer-type: "nlb"`, `externalTrafficPolicy: Cluster`, the `is-preserve-source` annotation omitted (setting it under `Cluster` makes requests fail), security-rule management `None` (Terraform owns the security lists) and default health checks. Traffic reaches the nodes from the load balancer subnet, which the existing rules already allow. Client IPs are not preserved.
- **No reserved public IP.** external-dns follows the IP, so it does not need to be stable, and its Always Free status is still unconfirmed.
- **TLS terminates in the cluster** at Traefik. Plain HTTP redirects to HTTPS at the entrypoint. HSTS is sent for `demo.sandeeprn.in` only, 6 months, without `includeSubDomains` or preload, because HSTS cannot be withdrawn early.
- **A per-IP rate limit** on the host, as a Traefik middleware.
- Admin UIs stay port-forward only (ADR 0014); Traefik's dashboard is not exposed.

**Certificates and DNS**
- **cert-manager** (v1.21.3) issues Let's Encrypt certificates by DNS-01 through Cloudflare: staging issuer first, then production (ADR 0005).
- **external-dns** (chart 1.23.0) creates `demo.sandeeprn.in` from the Ingress, replacing the Terraform-managed record of ADR 0013. Settings: `--domain-filter=sandeeprn.in`, Ingress source only, TXT registry with a cluster-specific owner id and a fixed prefix (never changed after deployment), `--policy=sync`, records DNS only (not proxied). Records it does not own, such as the blog's, are never touched.
- **Two Cloudflare API tokens**, one for cert-manager and one for external-dns, each with Zone:DNS:Edit and Zone:Zone:Read on the `sandeeprn.in` zone, each a SealedSecret. A leak or rotation affects one component, and Cloudflare's audit log shows which one acted.

**Link creation is token-gated**
A public link shortener on a real domain is an open redirector: spam and phishing links on `sandeeprn.in` would put the domain, and the blog, on browser and email blocklists.
- Redirects (`GET /{code}`) stay public; they are what the SLO measures.
- Creating a link requires one of several **named tokens** from one SealedSecret (for example `owner`, `k6`). The token's name is recorded with the link and in the logs. Adding a tester is adding a token; revoking one does not affect the others.
- A creation-mode setting: `token` now. `open` is reserved and refuses to start until these exist: a stricter rate limit, a destination allow/blocklist, link expiry and a way to disable a reported link. Turning it on is a new ADR.

**Observability**
- A ServiceMonitor for Traefik and one dashboard panel for edge request rate and errors. The SLO stays measured at the app (ADR 0008, 0019).

**Cutover, in two steps**
1. Add Traefik, the NLB, cert-manager, external-dns, the token gate and the Ingress. Verify `https://demo.sandeeprn.in` with a staging, then a production certificate. Point the external probe (`PROBE_BASE_URL`) at the hostname.
2. Switch the app Service to `ClusterIP`, which releases the Flexible Load Balancer and its IP.

**Versions** are pinned exactly and changed only through a PR; a fix may take a newer patch of the same minor.

## Consequences
- The portfolio gets a real HTTPS URL and TLS evidence before OKE's teardown, independent of A1.
- The k3s overlay can reuse cert-manager, external-dns, the Ingress and the token gate; on k3s, Traefik is the built-in one.
- ADR 0015's "free NLB stays reserved for k3s" no longer holds. Both are not needed at once: the NLB is released at OKE's teardown.
- ADR 0013's reserved IP and Terraform-managed record are replaced by external-dns. The Terraform Cloudflare token is no longer needed.
- Teardown (#13) must delete the Ingress before the cluster, so external-dns removes `demo.sandeeprn.in`; otherwise the record points at a released IP. If the cluster goes first, remove the record and its TXT owner record by hand.
- New secrets to rotate: two Cloudflare tokens and the link-creation tokens.
- Three more components on a 2-node cluster (Traefik, cert-manager, external-dns), each with resource limits.

## At scale
A WAF or CDN in front (Cloudflare proxy with origin certificates), client IP preservation for per-client limits, abuse handling with user accounts instead of shared tokens, and DNS changes through a reviewed pipeline rather than a controller with a write token.
