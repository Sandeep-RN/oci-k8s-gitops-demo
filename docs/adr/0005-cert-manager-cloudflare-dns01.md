# 0005. cert-manager with Cloudflare DNS-01 at demo.sandeeprn.in

Status: Accepted (2026-10-21)

## Context
A clickable live demo with real HTTPS is worth far more than screenshots. DNS for sandeeprn.in is managed at Cloudflare.

## Decision
Serve the demo at `demo.sandeeprn.in`. cert-manager obtains Let's Encrypt certificates using the DNS-01 challenge with a Cloudflare API token scoped to DNS edit on that one zone. The record is "DNS only" (not proxied), so Cloudflare's certificate does not sit in front of the in-cluster TLS (see ADR 0004). The token is stored as a SealedSecret (ADR 0006).

## Consequences
- Certificates renew automatically.
- The Cloudflare token is a secret with a small blast radius.

## At scale
Per-environment hostnames, wildcard certificates, and Cloudflare proxy/WAF if the edge design changes.
