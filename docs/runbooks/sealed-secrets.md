# Runbook: Sealed Secrets keys (backup, restore, sealing)

ADR 0006. Git holds only ciphertext. **The controller's private sealing keys
are the real secrets.** Lose them and every SealedSecret in Git becomes
unreadable; leak them and every one of them can be decrypted.

Tested end to end on the OKE target on 2026-10-24 (controller v0.40.0). Every
command below was run as written.

## Facts

| | |
|---|---|
| Controller | `sealed-secrets-controller` in `kube-system`, installed by ArgoCD from `platform/sealed-secrets` (gitops repo) |
| Keys | Secrets in `kube-system` labelled `sealedsecrets.bitnami.com/sealed-secrets-key` |
| Rotation | The controller adds a new key every 30 days and keeps the old ones, so older SealedSecrets still decrypt. **Back up again after each renewal.** |
| Public cert | `argocd/clusters/<cluster>/sealed-secrets-cert.pem` in the gitops repo; encrypt-only, safe to publish |
| Backup location | The owner's password manager. **Never** a repo, chat, ticket or screenshot |
| Scope | Keys are per cluster. The k3s cluster will have its own keys and its own backup |

All commands assume a working `kubectl` context (on OKE: `scripts/oke-tunnel.sh`,
then `K="kubectl --kubeconfig ~/.kube/oke-demo.kubeconfig"`).

## Seal a secret (no plaintext on disk)

Generate values inside a pipe so they never reach shell history, argv or a file:

```bash
python - <<'EOF' | kubeseal --cert argocd/clusters/oke/sealed-secrets-cert.pem \
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
- After a key renewal, refresh the committed cert: `kubeseal --fetch-cert >
  argocd/clusters/<cluster>/sealed-secrets-cert.pem`.

## Back up the keys

```bash
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-keys-<cluster>-$(date +%Y%m%d).yaml
chmod 600 sealed-secrets-keys-*.yaml
grep -c '^- apiVersion: v1' sealed-secrets-keys-*.yaml   # number of keys; compare with the cluster
```

1. Write the file **outside every repo**.
2. Store it in the password manager as a secure note or attachment, named with the cluster and date.
3. Delete the local file.

Repeat after every 30-day renewal, and before any cluster rebuild.

## Restore (disaster recovery or cluster rebuild)

On a rebuilt cluster, restore the keys **before** syncing SealedSecrets, or
restart the controller afterwards. Either works.

```bash
$K apply -f sealed-secrets-keys-<cluster>-<date>.yaml          # key Secrets
# Optional: remove a key the new controller generated, to return to the original key set.
$K -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key
$K -n kube-system delete secret <generated-key-name>
# Restart by deleting the pod, NOT `rollout restart` (see gotcha 2).
$K -n kube-system delete pod -l name=sealed-secrets-controller
$K -n kube-system wait --for=condition=Ready pod -l name=sealed-secrets-controller --timeout=180s
```

Verify:

```bash
$K get sealedsecrets -A \
  -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SYNCED:'.status.conditions[?(@.type=="Synced")].status'
# every row: True
kubeseal --fetch-cert | diff - argocd/clusters/<cluster>/sealed-secrets-cert.pem && echo "cert matches"
```

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
   Deployment. That is drift, and ArgoCD self-heal does not remove it, because
   its apply only prunes fields it set itself, so the app stays OutOfSync.
   Delete the pod instead, which changes no spec. If it already happened,
   remove the annotation:
   `kubectl -n kube-system patch deploy sealed-secrets-controller --type=json -p '[{"op":"remove","path":"/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"}]'`

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
