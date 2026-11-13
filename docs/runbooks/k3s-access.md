# Runbook: reach and check the k3s node

ADR 0010 (SSH-only access), ADR 0012 (host firewall). Issue: #7.

The node's Kubernetes API (6443) is never open to the internet. The security
list allows SSH (22) from `ssh_allowed_cidr` only, plus ICMP. `kubectl` goes
through an SSH tunnel:

```
laptop 127.0.0.1:16443 ──ssh (22)──► node 127.0.0.1:6443 (k3s API)
```

Port 16443 on the laptop keeps the k3s tunnel apart from the OKE tunnel
(`scripts/oke-tunnel.sh`, 6443), so both can run during the move.

## Open the tunnel

Needs the SSH key `~/.ssh/k3s-node` and a valid OCI session (the node's IP is
read from Terraform state, which lives in Object Storage).

```bash
oci session authenticate --region ap-hyderabad-1 --profile-name oke-demo
scripts/k3s-tunnel.sh          # fetches ~/.kube/k3s.kubeconfig, holds the tunnel; Ctrl+C closes
# in another terminal:
kubectl --kubeconfig ~/.kube/k3s.kubeconfig get nodes
```

`scripts/k3s-tunnel.sh --no-tunnel` only refreshes the kubeconfig. With
`K3S_NODE_IP` set, no OCI session is needed.

`~/.kube/k3s.kubeconfig` holds the cluster-admin certificate. Never put it in
a repo, an issue or a chat.

## Check the node

With the tunnel running:

```bash
scripts/k3s-verify.sh                   # 9 checks, about 1 minute
scripts/k3s-verify.sh --skip-terraform  # without an OCI session (set K3S_NODE_IP)
```

One PASS/FAIL/SKIP line per check; IPs and OCIDs are masked, so the output can
be pasted into an issue. Exit code 1 if any check failed.

| Check | What it proves |
|---|---|
| terraform-no-drift | the node and network match the code |
| prevent-destroy | a plan to delete the node is refused (plan only) |
| ssh-key-only | the server offers public-key login only |
| api-closed, kubelet-closed | 6443 and 10250 are not reachable from the internet |
| bootstrap-done | the first-boot script finished |
| node-ready, k3s-version | Ready, on the pinned k3s version |
| pod-dns-internet | a throwaway pod resolves cluster DNS and reaches the internet, then is deleted |

The A1 retry script has an offline test: `scripts/tests/a1-wait-and-apply.test.sh`.

## Rotate the SSH key

Do this on the node, not in Terraform. `ssh_public_key` in `terraform.tfvars` is
the first-boot key, and `metadata["ssh_authorized_keys"]` is in `ignore_changes`
on the instance (#157): editing the variable plans no change and does not touch
the running node. Without that, the edit would plan a replace, which
`prevent_destroy` refuses for every plan in this root.

1. Create the new key pair on your laptop (`ssh-keygen -t ed25519 -f ~/.ssh/k3s-node-new`).
2. With the old key still working, append the new public key on the node:
   `ssh -i ~/.ssh/k3s-node ubuntu@<node-ip> '(echo; cat) >> ~/.ssh/authorized_keys' < ~/.ssh/k3s-node-new.pub`
   (the `echo` guards against a file that lacks a final newline).
3. In a second terminal, check the new key logs in (`ssh -i ~/.ssh/k3s-node-new ubuntu@<node-ip> true`).
   Only then remove the old public key line from `~/.ssh/authorized_keys` on the node.
4. Move the new private key to `~/.ssh/k3s-node` (or set `SSH_KEY` for the scripts).
5. Update `ssh_public_key` in `terraform.tfvars` to the new public key, so a
   deliberate rebuild (#57) starts with the key you actually use. `terraform plan`
   still shows no changes.

## When something fails

| Symptom | Cause and fix |
|---|---|
| `ssh: connect to host ... timed out`, or the tunnel script fails at "fetching the kubeconfig" | Your public IP changed and is outside `ssh_allowed_cidr`. Set it in `terraform/k3s/terraform.tfvars` (git-ignored), then `terraform plan` (expect 1 in-place change to `oci_core_security_list.node`) and apply. |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` | The node was rebuilt and has a new host key. Only after a deliberate rebuild: `ssh-keygen -R <node-ip>`. Otherwise stop and find out why the key changed. |
| `127.0.0.1:16443 is already in use` | Another tunnel is open. Close it, or set `LOCAL_PORT` (then refetch the kubeconfig with the same `LOCAL_PORT`). |
| `bootstrap-done` FAIL, `k3s: command not found` | The first-boot script stopped early. Read `sudo cat /var/log/bootstrap-node.log` on the node, fix the cause, then re-run it: `sudo bash /usr/local/sbin/bootstrap-node.sh` (safe to repeat). On 2026-11-11 it stopped at `sshd -t` (`/run/sshd` missing; fixed in the template by #121). `cloud-init status` keeps saying `error` after such a repair; the bootstrap log is the record to trust. |
| `terraform-no-drift` FAIL | Someone changed the node or network outside Terraform, or the code changed. Read the plan before applying. A change to the cloud-init template does not show up: it is ignored on purpose and takes effect only on a rebuild (#57). |
