# 0002. Ubuntu 24.04 (aarch64) as the node OS

Status: Accepted (2026-10-21)

## Context
The node image affects how much time goes into OS quirks instead of the project's actual subject.

## Decision
Use Ubuntu 24.04 aarch64. k3s documentation and examples assume it, and cloud-init behaviour is well known. Oracle Linux was rejected because SELinux and firewalld add friction that isn't the point of this project.

## Consequences
- Container images must be built for arm64 (multi-arch or arm64-only in CI).
- The OS firewall (iptables rules set by the image) must allow the ports the NLB forwards.

## At scale
A hardened, regularly rebuilt golden image, with node replacement instead of in-place patching.
