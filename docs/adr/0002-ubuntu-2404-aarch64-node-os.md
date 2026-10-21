# 0002. Ubuntu 24.04 (aarch64) as the node OS

Status: Accepted (2026-10-21, revised 2026-10-21 after review)

## Context
The node image affects how much time goes into OS quirks instead of the project's actual subject.

## Decision
Use Ubuntu 24.04 aarch64. k3s documentation and examples assume it, and cloud-init behaviour is well known. Oracle Linux was rejected because SELinux and firewalld add friction that isn't the point of this project.

## Consequences
- Container images must be built for arm64 (multi-arch or arm64-only in CI).
- Oracle's Ubuntu image ships iptables REJECT rules that break k3s pod networking and block ports 80/443. Fixing this in cloud-init is a day-1 requirement; see ADR 0012.

## At scale
A hardened, regularly rebuilt golden image, with node replacement instead of in-place patching.
