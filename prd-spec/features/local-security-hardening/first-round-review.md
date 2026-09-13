# Local Security Hardening First-Round Review

## Scope

- Production: diagnostics lifecycle, Force Stop command routing, Swift and shell storage validation, host and guest clipboard limits.
- Consumers: management UI/controller, storage estimates and maintenance script, QEMU stderr callbacks, documentation.
- Tests: all changed Swift, Python, and shell contract suites.
- Rules: `CONTRIBUTING.md`, approved design, verification Case matrix, and the Dev Loop review gate.

## Findings and disposition

| ID | Severity | Category | Location | Evidence and impact | Disposition |
|---|---|---|---|---|---|
| R1-01 | medium | Scope | `README.md`, `docs/architecture.md`, `macos/README.md` | User and architecture docs still said any APFS folder and that inherited overrides remained unchanged, contradicting the new allowlist and fail-closed launch behavior. | Fixed: all three documents now state Home/Volumes true-descendant rules and validated overrides. |
| R1-02 | high | Security | `QEMUGPULauncher.swift` diagnostics creation | Path-based chmod/open after lstat allowed the directory pathname to be replaced between checks. | Fixed: directory is opened with `O_DIRECTORY | O_NOFOLLOW`, verified and chmodded through the FD, and the log is created with `openat(O_EXCL | O_NOFOLLOW)`. |
| R1-03 | high | Security | `LaunchDiagnosticsLog.append` | FileHandle stderr callbacks can split at any byte. Per-callback regex redaction persisted a key split across three appends in plaintext; a red test reproduced the leak. | Fixed: buffer complete lines, redact once per logical line, and flush the unterminated tail on close. The regression passed after failing against the old implementation. |
| R1-04 | medium | Correctness | `VMApplicationController.requestForceStopConfirmation` | The injected completion type did not express the controller's MainActor requirement, allowing a conforming asynchronous presenter to call it from a background executor. | Fixed: the injection and completion are `@MainActor @Sendable`; controller state and `SIGKILL` forwarding remain actor-isolated. |

## Coverage review

- Every production entry point for Force Stop routes through the controller confirmation gate; no direct `SIGKILL` call remains elsewhere in production sources.
- Picker, saved preference, environment override, read-only estimate, launcher shell, and disk-resize maintenance paths all apply the allowlist or consume a validated root.
- Host and guest clipboard constants are both exactly `10 * 1024 * 1024`, with derived line budgets and exact boundary tests.
- Diagnostics failure remains best-effort: a nil log does not prevent `Process.run()`.

## Verification

| Command | Result |
|---|---|
| `swift test --filter QEMUStandardErrorDrainTests.launchDiagnosticLogRedactsSecretsAcrossChunks` before fix | Failed with plaintext secret, as expected |
| `swift test --filter QEMUStandardErrorDrainTests` after fix | 14/14 passed at this review point |
| `swift test --filter ManagementControllerBridgeTests` | 12/12 passed |
| `git diff --check`, `bash -n`, Python compile | Passed |

## Gate

All confirmed first-round findings are fixed. No open explicit or implicit correctness finding remains; proceed to adversarial second-round review.
