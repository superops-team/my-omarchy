# Local Security Hardening Second-Round Review

## Adversarial scenarios

- Replace the diagnostics pathname after a secure directory has been opened.
- Grow historical logs after preflight so only close-time 10-file/50-MiB enforcement can restore quota.
- Split secret names and values across arbitrary stderr chunks.
- Resolve Force Stop after cancel, duplicate clicks, child exit, session replacement, policy invalidation, or termination takeover.
- Try Home lookalikes, Home itself, `/Volumes`, volume roots, system roots, ancestor-symlink escapes, nonexistent overrides, and forged `$HOME`.
- Exercise exactly 10 MiB and 10 MiB plus one byte on both clipboard endpoints.

## Findings and disposition

| ID | Severity | Category | Location | Evidence and impact | Disposition |
|---|---|---|---|---|---|
| R2-01 | high | Security | `LaunchDiagnosticsLog.retainManagedLogs` | Creation used a directory FD, but retention still enumerated and deleted by pathname. Replacing the directory name could redirect close-time deletion to attacker-selected managed-looking files. | Fixed: enumeration, metadata verification, and deletion now use the retained directory FD with `fdopendir`, `fstatat(AT_SYMLINK_NOFOLLOW)`, and `unlinkat`. A replacement-directory test proves it is untouched. |
| R2-02 | medium | Correctness | `LaunchDiagnosticsLog.directoryEntryNames` | `dup` shares the directory file description and offset. Without rewinding, the close-time scan could start at EOF after preflight and miss quota enforcement. | Fixed: rewind the duplicated directory stream before every enumeration. A test grows history after create and proves close removes the oldest file to restore the final quota. |

## Rechecked and rejected hypotheses

- The 50-MiB comparison correctly permits exactly 50 MiB; the initial close-quota counterexample was corrected to exceed the boundary by one byte rather than weakening the implementation.
- Shell `/Volumes/<volume>/<child>` matching is followed by physical canonicalization and the same allowlist check, so `..` and ancestor links cannot survive into mutation for explicit overrides.
- Unsafe or unowned diagnostic entries are ignored, never deleted; inability to meet quota fails logging without blocking VM launch.
- A confirmation result cannot kill a later session because session, child-running, termination, and policy state are all revalidated after the modal result.

## Verification

| Command | Result |
|---|---|
| `swift test --filter QEMUStandardErrorDrainTests.launchDiagnosticLogEnforcesQuotaOnClose` | Passed |
| `swift test --filter QEMUStandardErrorDrainTests` | Replacement-directory test passed; full suite rerun is part of final E2E |
| Static search for production `SIGKILL` | Exactly one call, behind the controller confirmation gate |
| Cross-repository search for clipboard limits and old storage helpers | Endpoint constants aligned; no obsolete production helper remains |

## Gate

No open P0/P1 or lower-severity actionable finding remains. Code quality is accepted for final E2E and repository-wide regression.
