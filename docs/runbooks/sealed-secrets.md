# Runbook: Sealed Secrets keys (backup, restore, sealing)

ADR 0006. Git holds only ciphertext. **The controller's private sealing keys
are the real secrets.** Lose them and every SealedSecret in Git becomes
unreadable; leak them and every one of them can be decrypted.

Tested end to end on the OKE target on 2026-10-24 (controller v0.40.0, drill
record below), every command run as written there. The restore was done again
on k3s on 2026-11-12 with the minimal export, when the OKE keys were moved to
k3s (ADR 0022): the restore commands below are the ones run then (step 2 of
[k3s-bootstrap](k3s-bootstrap.md)).

## Not yet run on k3s in this form

Only the kubeconfig or the certificate path changed for these. Run each once
on k3s and remove it from this list:

- the minimal export in "Back up the keys" (it ran on OKE on 2026-11-12, and its file was restored on k3s)
- the seal example with `--cert argocd/clusters/k3s/sealed-secrets-cert.pem` (the file is identical to the OKE one it ran with)
- `kubeseal --kubeconfig ~/.kube/k3s.kubeconfig --fetch-cert > argocd/clusters/k3s/sealed-secrets-cert.pem` (after a key renewal)
- `$K -n kube-system delete secret <generated-key-name>`, `$K -n kube-system delete pod -l name=sealed-secrets-controller` and the `wait` after it (restore, only when the controller already ran without the keys)
- the `patch` that removes a `restartedAt` annotation (gotcha 2)

## Facts

| | |
|---|---|
| Controller | `sealed-secrets-controller` in `kube-system`, installed by ArgoCD from `platform/sealed-secrets` (gitops repo) |
| Keys | Secrets in `kube-system` labelled `sealedsecrets.bitnami.com/sealed-secrets-key` |
| Rotation | The controller adds a new key every 30 days and keeps the old ones, so older SealedSecrets still decrypt. **Back up again after each renewal.** |
| Public cert | `argocd/clusters/<cluster>/sealed-secrets-cert.pem` in the gitops repo; encrypt-only, safe to publish |
| Backup location | The owner's password manager. **Never** a repo, chat, ticket or screenshot |
| Scope | **One set of keys for this project** (ADR 0022): the OKE keys were restored on k3s on 2026-11-12, so the same sealed files decrypt on both clusters and one backup covers both. Do not delete it at the OKE teardown: it is the k3s key now |

All commands assume the k3s tunnel is running (`scripts/k3s-tunnel.sh`, see
[k3s-access](k3s-access.md)) and use:

```bash
K="kubectl --kubeconfig $HOME/.kube/k3s.kubeconfig"     # k3s, NOT the OKE kubeconfig
```

kubectl's default context on the laptop is a different cluster, so every
command names the k3s kubeconfig.

## Seal a secret (no plaintext on disk)

Generate values inside a pipe so they never reach shell history, argv or a file:

```bash
python - <<'EOF' | kubeseal --cert argocd/clusters/k3s/sealed-secrets-cert.pem \
                            --format yaml --scope strict > NAME-sealedsecret.yaml
import json, secrets
print(json.dumps({
  "apiVersion": "v1", "kind": "Secret",
  "metadata": {"name": "NAME", "namespace": "NAMESPACE"},
  "type": "Opaque",
  "stringData": {"password": secrets.token_urlsafe(32)},
}))
EOF
```

- `--scope strict` binds the ciphertext to that name and namespace. It cannot
  be copied elsewhere and decrypted.
- Files must end in `-sealedsecret.yaml`. The gitops `.gitignore` blocks
  `*-secret.yaml`, and the `validate` check rejects plain `kind: Secret`.
- After a key renewal, refresh the committed cert:
  `kubeseal --kubeconfig ~/.kube/k3s.kubeconfig --fetch-cert > argocd/clusters/k3s/sealed-secrets-cert.pem`.
  The gitops seal scripts (`scripts/seal-link-tokens.sh`,
  `scripts/seal-cloudflare-token.sh`) still read the identical copy in
  `argocd/clusters/oke/`, so refresh both files while both exist.

## Back up the keys

Export only the fields a restore needs. `get secret -o yaml` is not enough on
a cluster where the keys were restored with `kubectl apply`: apply adds a
`kubectl.kubernetes.io/last-applied-configuration` annotation that holds the
private key a second time, plus `resourceVersion` and `uid`. On 2026-11-12 that
backup was 14 KB and the password manager refused it (limit: 10,000 characters
per note, about 7 KB of plain text). The minimal export below was 6.8 KB for one
key, and restores cleanly on another cluster (server-side dry run and apply
both passed):

```bash
F=sealed-secrets-keys-<cluster>-$(date +%Y%m%d)-min.yaml
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o go-template='{{range .items}}---
apiVersion: v1
kind: Secret
type: {{.type}}
metadata:
  name: {{.metadata.name}}
  namespace: kube-system
  labels:
    sealedsecrets.bitnami.com/sealed-secrets-key: {{index .metadata.labels "sealedsecrets.bitnami.com/sealed-secrets-key"}}
data:
  tls.crt: {{index .data "tls.crt"}}
  tls.key: {{index .data "tls.key"}}
{{end}}' > "$F"
chmod 600 "$F"
echo "bytes: $(wc -c < "$F")  keys: $(grep -c '^kind: Secret' "$F")  last-applied: $(grep -c last-applied "$F")"
# keys = the number on the cluster; last-applied = 0; bytes must stay under about 7300 per note
```

The file grows by about 6.8 KB per key, so one password-manager note holds one
key. After the first 30-day renewal there are two keys: store the file as an
attachment, or one note per key.

1. Write the file **outside every repo**.
2. Store it in the password manager as a secure note or attachment, named with the cluster and date.
3. Delete the local file.

Repeat after every 30-day renewal, and before any cluster rebuild.

## Restore (disaster recovery or cluster rebuild)

This is the one restore procedure for the project. [k3s-bootstrap](k3s-bootstrap.md)
step 2 links here and keeps the record of the run on k3s on 2026-11-12.

Restore the keys **before ArgoCD syncs anything** (before `root.yaml`, step 3
of the bootstrap). `root.yaml` syncs the controller together with every
SealedSecret; a controller that starts without the old keys creates a new one,
and every sealed file then fails to decrypt (ADR 0006).

**The owner runs every command that reads or applies the key file**, in a
directory outside every repo. Anyone helping checks only outcomes: the number
of key Secrets, their names, and the public certificate.

```bash
F=sealed-secrets-keys-<cluster>-<date>-min.yaml          # the file from the password manager, outside every repo
[ "$($K get nodes -o jsonpath='{.items[*].metadata.name}')" = "k3s-node-vnic" ] && echo "cluster: k3s OK" \
  && $K apply --dry-run=server -f "$F" \
  && $K apply -f "$F"
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key
```

The `&&` chain applies nothing unless the node check (the right cluster) and
the server-side dry run pass. A pasted block does not stop on a failed line by
itself.

Check: the number of key Secrets equals the number in the file
(`grep -c '^kind: Secret' "$F"`), with the same names. Then delete the local
file (`rm -f "$F"`).

**If the controller already ran without the keys** (it made a key of its own,
and SealedSecrets show `Synced=False`, "no key could decrypt"): apply the keys
as above, then remove the generated key and restart the controller. Restart by
deleting the pod, NOT `rollout restart` (see gotcha 2):

```bash
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key   # the extra name is the generated key
$K -n kube-system delete secret <generated-key-name>
$K -n kube-system delete pod -l name=sealed-secrets-controller
$K -n kube-system wait --for=condition=Ready pod -l name=sealed-secrets-controller --timeout=180s
```

Verify:

```bash
$K get sealedsecrets -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SYNCED:'.status.conditions[?(@.type=="Synced")].status'
# every row: True
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key --no-headers | wc -l
# the same number as in the file: the controller made no key of its own
# From the gitops repo's main checkout:
kubeseal --kubeconfig ~/.kube/k3s.kubeconfig --fetch-cert | tr -d '\r' \
  | diff - <(tr -d '\r' < argocd/clusters/k3s/sealed-secrets-cert.pem) && echo "cert matches"
```

(`tr -d '\r'`: a Windows checkout has CRLF line endings, and a plain `diff`
then reports a difference that is not there.) On a cluster that restored the
keys with `apply` in the same session, `get secret` shows one key, with the
`last-applied-configuration` annotation; this is harmless, and the minimal
export above never includes it.

Restoring keys is a deliberate exception to "no manual kubectl apply": the
keys must never be in Git, so ArgoCD cannot restore them.

## Gotchas found in the drill

1. **Restart before you delete.** The controller keeps keys in memory. If you
   delete a key **and** a decrypted Secret, then restart, the old pod may
   recreate the Secret in the seconds before it stops. In the drill, the
   Secret was recreated at 08:12:01 and the new pod started at 08:12:29, which
   made it look as if decryption still worked. Restart the controller first,
   wait until it is Ready, and then check or delete.
2. **Do not use `kubectl rollout restart` on ArgoCD-managed workloads.** It
   writes a `kubectl.kubernetes.io/restartedAt` annotation into the
   Deployment, a change that Git does not have. In this drill ArgoCD flagged
   it, and self-heal did not remove it (its apply only prunes fields it set
   itself), so the app stayed OutOfSync until the annotation was removed.
   ArgoCD does not flag every field that is missing from Git, so the outcome
   can differ on another resource; deleting the pod changes no spec and is
   safe either way. The Restart action in the ArgoCD UI writes the same
   annotation. If it already happened, remove the annotation:
   `$K -n kube-system patch deploy sealed-secrets-controller --type=json -p '[{"op":"remove","path":"/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"}]'`

## Drill record (2026-10-24, OKE)

1. Fingerprint of `postgres-credentials` (a sha256 of its data, never the values): `9add966d…`.
2. Deleted the key and the Secret, then restarted. A new key was generated.
   The SealedSecret reported `Synced=False`, "no key could decrypt secret",
   and the Secret stayed absent.
3. Applied the backup, deleted the generated key, restarted. `Synced=True`,
   the Secret came back, and the fingerprint matched exactly: `9add966d…`.
4. The active cert equals the committed cert.
5. The drill used `rollout restart`, which left the `sealed-secrets` app
   OutOfSync (gotcha 2). Fixed by removing the annotation. A pod-delete
   restart was then verified to keep the app Synced.

Result: the backup is sufficient to recover every SealedSecret.
