# My Omarchy product identity

`config/product-identity.json` is the single design-time contract for product,
repository, macOS, storage, guest ABI, runtime, build, and release naming. It is
not loaded by the app at runtime. Production code embeds the approved values,
and later phase contract tests must compare those values back to this file.

The only maintained repository and release source is
`superops-team/my-omarchy`. My Omarchy owns independent bundle identifiers, VM
storage, preferences, runtime endpoints, guest namespaces, artifacts, and
release channels. Code must never discover, import, migrate, modify, or delete
data belonging to the predecessor product.

## Local gates

Run the reviewed migration baseline during normal development:

```sh
make verify-identity
```

This scans only UTF-8 text paths returned by `git ls-files`. It fails on an
unreviewed legacy token, a count change, a stale entry, a glob path, an unknown
pattern, or missing ownership metadata. `make test` runs this gate first.

Before any release candidate, run the strict gate:

```sh
make verify-release-identity
```

Strict mode permits only exact historical-attribution and verification-fixture
entries. During Phase 1A it intentionally fails and summarizes remaining work
by owner phase. It becomes a required passing release gate after Phases 1B, 1C,
and 1D have removed their entries.

## Reviewing allowlist changes

Each entry identifies one exact repository-relative path and one controlled
pattern, with an exact occurrence count, category, owner phase, and reason.
Review changes using these rules:

1. Fix a newly introduced legacy identity instead of adding it to the baseline.
2. Add an entry only when the occurrence already belongs to an approved later
   migration phase or is permanent attribution/test evidence.
3. Assign brand work to 1B, macOS host identity and storage to 1C, and guest ABI
   or guest build resources to 1D. Split mixed files by pattern when ownership
   differs.
4. When an occurrence is removed, update or delete its exact entry in the same
   change. Never use directory exclusions, glob paths, broad regex exceptions,
   or inflated counts.
5. Treat a baseline count increase as a regression requiring correction, not as
   routine inventory maintenance.

Automated inventory generation may propose counts, but it cannot approve an
entry's category, owner, or reason. Those fields require human review.

## CI validation

Local required checks use only the Python standard library. CI additionally
installs a pinned JSON Schema validator and validates both identity documents
against their Draft 2020-12 schemas before running the baseline and complete
test suite. This makes schema conformance explicit without adding a runtime
dependency to My Omarchy.
