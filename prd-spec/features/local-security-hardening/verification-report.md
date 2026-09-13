# Local Security Hardening Verification Report

## Result

All 13 planned verification Cases passed. Both code-review rounds closed every evidence-backed finding. The production macOS app compiled and launched without touching the existing VM, and the repository-wide regression exited 0.

## Case results

| Case | Result | Evidence |
|---|---|---|
| VC-LOG-001 | PASS | `.build/verification/local-security-hardening/VC-LOG-001.log` plus final 15-test diagnostics suite |
| VC-LOG-002 | PASS | Exact 10 MiB cap, one marker, split-callback secret regression |
| VC-LOG-003 | PASS | 9/40 preflight, 10/50 close quota, FD-bound replacement test |
| VC-FORCE-001 | PASS | `.build/verification/local-security-hardening/VC-FORCE-001.log` |
| VC-FORCE-002 | PASS | `.build/verification/local-security-hardening/VC-FORCE-002.log` |
| VC-STORAGE-001 | PASS | `.build/verification/local-security-hardening/VC-STORAGE-001.log` |
| VC-STORAGE-002 | PASS | `.build/verification/local-security-hardening/VC-STORAGE-002.log` |
| VC-STORAGE-003 | PASS | `.build/verification/local-security-hardening/VC-STORAGE-003.log` |
| VC-STORAGE-004 | PASS | `.build/verification/local-security-hardening/VC-STORAGE-004.log` |
| VC-CLIP-001 | PASS | `.build/verification/local-security-hardening/VC-CLIP-001.log` |
| VC-CLIP-002 | PASS | `.build/verification/local-security-hardening/VC-CLIP-002.log` |
| VC-REG-001 | PASS | `.build/verification/local-security-hardening/VC-REG-001-release.log` |
| VC-E2E-001 | PASS with noted upstream rebuild limitation | `.build/verification/local-security-hardening/VC-E2E-001-app-only.log` and build-attempt log |

## Final regression

- `make test`: exit 0.
- Product identity contracts passed.
- Guest/native contracts passed.
- Swift: 271 tests passed.
- Persistent-storage shell suite: PASS.
- Resize-disk Python suite: 14 tests passed.
- Final diagnostics suite includes split-secret, directory-replacement, and post-growth quota regressions.

## App E2E

The standard `make app` first attempted to rebuild the guest because package-index inputs had changed. Its immutable package-lock gate correctly stopped on upstream Arch ARM version drift; the lock was not refreshed because supply-chain updates are outside this feature.

The repository's supported component scripts were then run against the existing local `dist/guest`, which had just passed the complete guest contract in `make test`:

```bash
make runtime
OMARCHY_CODESIGN_IDENTITY=- macos/build-app.sh --guest-dir dist/guest
```

Results:

- Production Swift build passed.
- 19 bundled runtime Mach-O images were self-contained.
- 20 app Mach-O images passed the macOS 15 compatibility contract.
- Ad-hoc signature verification and the app designated requirement passed.
- The built executable launched and remained live until the test terminated it.
- Launch used `OMARCHY_QEMU_GPU_STATE_ROOT=/private/tmp/my-omarchy-e2e-disallowed`; that disallowed target was not created, proving the startup path failed closed before VM storage mutation.
- Existing user VM data and the already-running installed app were not stopped or modified.
- The real diagnostics directory remained owner-only (`0700`), and inspected launch logs were owner-only regular files (`0600`) and far below 10 MiB. Exact quota enforcement is covered by the real `LaunchDiagnosticsLog` integration tests because this fail-closed launch intentionally did not start QEMU.

## Review results

- First round: four findings fixed (documentation contract, directory TOCTOU, split-callback redaction, MainActor completion typing).
- Second round: two findings fixed (path-based retention and shared directory-offset rescan).
- Open P0/P1 findings: 0.
- Remaining known issue: upstream package repository drift prevents a clean guest rebuild until maintainers intentionally review and refresh `packages.lock.json`; it does not invalidate this change's compiled app or test results.

## Acceptance mapping

- Diagnostics: 10 MiB per file, 10 files/50 MiB total, private descriptor-bound directory/file operations, best-effort startup behavior.
- Force Stop: one controller-owned confirmation, duplicate suppression, and post-confirmation session/state checks.
- Storage: only true descendants of current-user Home or `/Volumes/<volume>`; all other paths fail closed without migration, deletion, or fallback.
- Clipboard: host and guest accept at most `10_485_760` raw bytes.

Final gate: **PASS**.
