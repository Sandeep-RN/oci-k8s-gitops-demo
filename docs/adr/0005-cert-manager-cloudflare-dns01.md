# 0005. cert-manager with Cloudflare DNS-01 at demo.sandeeprn.in

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
A clickable live demo with real HTTPS is worth far more than screenshots. DNS for sandeeprn.in is managed at Cloudflare.

## Decision
- Serve the demo at `demo.sandeeprn.in`. The record is "DNS only" (not proxied), so Cloudflare's certificate does not sit in front of the in-cluster TLS (ADR 0004). The record is managed by Terraform (ADR 0013).
- cert-manager obtains Let's Encrypt certificates with the DNS-01 challenge, using a Cloudflare API token scoped to that one zone with **Zone: DNS: Edit** and **Zone: Zone: Read** (cert-manager needs both).
- Use the Let's Encrypt **staging** issuer until issuance works, then switch to production, to avoid production rate limits.
- The token is stored as a SealedSecret (ADR 0006).

## Consequences
- Certificates renew automatically.
- The Cloudflare token is a secret with a small blast radius.

## At scale
Per-environment hostnames, wildcard certificates, and Cloudflare proxy/WAF if the edge design changes.
