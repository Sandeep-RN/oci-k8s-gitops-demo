# 0024. Secret scanning in layers: gitleaks hook, full-history CI, GitHub push protection

Status: Accepted. The hook and the custom rules date from the first commit of
each repo (2026-10-21); the CI scan was added on 2026-10-25 (issue #69).
Recorded later, on 2026-11-13.

## Context
- All three repos are public. A secret pushed once is public for good, even
  if a later commit deletes it: the history keeps it.
- Some values are not credentials but still must not be published, because
  they identify the account: OCIDs (tenancy, compartment, user), the Object
  Storage namespace, and OCI API key fingerprints. Generic scanners do not
  know these formats.
- The project is built with an AI coding agent that writes and commits files.
  Review alone is not a reliable gate.

## Decision
Three layers, each catching what the one before can miss:

1. **gitleaks as a pre-commit hook** (`.pre-commit-config.yaml`, pinned). It
   stops a secret before the commit exists. It runs only where
   `pre-commit install` was run, and `git commit --no-verify` skips it.
2. **gitleaks in CI on every pull request and every push to `main`**
   (`.github/workflows/gitleaks.yml`), the same version as the hook, the
   binary checked against its published sha256. It scans the **full
   history**, not only the new commits: a secret that was committed and later
   deleted keeps failing the job until it is rotated and consciously
   allowlisted. Findings are printed with `--redact`, because the job log is
   public.
3. **GitHub secret scanning with push protection**, enabled in all three
   repos. It knows the token formats of many providers and blocks a push
   that contains one.

The same `.gitleaks.toml` is used by the hook and by CI. It extends the
default rules with four of our own: `oci-ocid`,
`oci-object-storage-namespace-url`, `oci-api-key-fingerprint` and, since
2026-11-14, `public-ipv4` (issue #167). The last one flags any IPv4 address
outside the private, loopback, link-local, shared (100.64/10) and
documentation ranges, apart from netmask values and the two public resolvers
the repos use (1.1.1.1, 8.8.8.8). It is the same text in all three repos.
In the gitops repo one narrow allowlist accepts kubeseal ciphertext (`Ag...`,
100 or more characters) for the `generic-api-key` rule only, because
SealedSecrets are meant to be public (ADR 0006).

## Consequences
- A leak needs all three layers to miss it.
- Each custom rule must be tested on a fake value. The fingerprint rule once
  redacted only its last byte (demo PR #10).
- A newer gitleaks can flag old commits (it flagged two SealedSecrets when CI
  was added). The fix is a narrow allowlist on one rule, never a broad path
  exclusion.
- Known gaps:
  - The `public-ipv4` rule does not see IPv6 addresses, an address split
    across lines, or an address inside an image. For those, "never commit a
    public IP" is still enforced only by review.
  - The gitleaks job is not a required check in any of the three repos.
    A red job warns but does not block a merge.

## At scale
gitleaks (or a commercial scanner) as a required check enforced through
organisation rulesets, push protection with custom patterns for internal
identifiers, alerts routed to a security team, and short-lived credentials
(OIDC to the cloud) so that a leaked value expires on its own.
