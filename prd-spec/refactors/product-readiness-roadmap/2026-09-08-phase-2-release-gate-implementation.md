# My Omarchy Phase 2 Release Gate Implementation

## 1. Scope

Phase 2 establishes the minimum release-gate scaffold for My Omarchy. This
first implementation does not publish a GitHub Release, notarize an artifact, or
claim real-device qualification. It creates the repo-local contracts that make a
future release workflow enforceable: tag/version preflight, candidate identity,
evidence schema validation, and a clear distinction between prerelease and
stable evidence requirements.

## 2. Deliverables

- `config/release-evidence.schema.json`: versioned schema for release evidence.
- `scripts/release-preflight.py`: local preflight for clean tree, semver tag,
  product identity, release profile, DMG naming, and required evidence fields.
- `tests/test-release-gate.py`: unit tests for valid prerelease evidence and
  failing dirty/tag/profile/schema cases.
- `Makefile` targets:
  - `make release-preflight-local`: validates repository state and evidence
    without signing or publishing.
  - `make verify-release-evidence EVIDENCE=...`: validates an existing evidence
    file against schema and repo identity.
- Documentation updates in `docs/releasing.md`.

## 3. Evidence v1 contract

The v1 evidence file is JSON and must contain:

- `schemaVersion`: `1`
- `gateProfile`: `prerelease` or `stable`
- `candidateId`: immutable identifier using `my-omarchy-<semver>-<short-sha>`
- `repository`: `superops-team/my-omarchy`
- `version`, `tag`, `commit`, `buildNumber`
- `artifact`: DMG name, SHA-256, size, and optional GitHub asset id
- `environment`: macOS, architecture, Swift, Xcode selection
- `checks`: named check results with status, command, and summary
- `deviceQualification`: device matrix and result summaries
- `knownLimitations`
- `generatedAt`
- `approvedBy`

Local preflight validates shape and identity using Python standard library only.
CI may add a pinned JSON Schema validator as a second pass, matching Phase 1A.

## 4. Profile rules

`prerelease` evidence requires at least one Apple Silicon device qualification
entry with `status=pass`. `stable` evidence requires at least two devices and
must cover both minimum and latest supported macOS labels. The first scaffold
checks these machine-readable fields; it does not decide whether manual evidence
quality is sufficient.

## 5. Non-goals

- No signing, notarization, Gatekeeper, GitHub Draft Release, asset upload, or
  attestation implementation in this first local scaffold.
- No version rewriting inside `Info.plist`.
- No source-v1 fixture capture.
- No changes to lifecycle, backup, diagnostics, or performance gates.

## 6. Verification

Before commit:

1. `python3 -m unittest -v tests/test-release-gate.py`
2. `make verify-release-evidence EVIDENCE=tests/fixtures/release-evidence/prerelease-pass.json`
3. `make release-preflight-local` must fail outside a release tag or without an
   explicit evidence path, proving the preflight is closed by default.
4. Existing `make verify-identity` and `make verify-release-identity` pass.
5. `git diff --check`

## 7. Completion

This slice is complete when a future release workflow has a concrete local
contract to call, invalid evidence fails with actionable errors, and repository
docs no longer describe release verification as a purely manual checklist.
