# Local Security Hardening OpenSpec Plan

## 1. Plan

### 1.1 Objective

Implement the approved local security hardening design with test-first, independently enforceable boundaries for launch diagnostics, Force Stop, custom storage roots, and clipboard payloads. Preserve default VM behavior and never migrate or delete existing VM data.

### 1.2 Module graph

```text
T1 Diagnostic contracts -> T2 Diagnostic implementation
T3 Force Stop contracts -> T4 Force Stop implementation
T5 Swift Storage contracts -> T6 Swift Storage implementation
T6 -> T7 Shell Storage contracts and implementation
T8 Clipboard contracts -> T9 Clipboard implementation
T2 + T4 + T6 + T7 + T9 -> T10 Verification and documentation
T10 -> two-round review -> E2E -> commit/tag/push
```

The four feature slices are otherwise independent. They remain sequential in the Dev Loop so every red-green-refactor gate is observable and reviewable.

### 1.3 Architecture boundaries

- `LaunchDiagnosticsLog` owns only private log creation, bounded writes and managed-file retention. `QEMUGPUProcessSupervisor` keeps best-effort integration.
- `VMApplicationController` owns destructive command confirmation and session revalidation. `OverviewView` only sends semantic commands; `ManagementAppKitPresenter` only renders the prompt.
- `StorageLocationPolicy` owns Swift allowlist semantics. Every Swift consumer calls it instead of maintaining a parallel blacklist. The shell independently enforces the same contract before mutation.
- `ClipboardMessage` and the guest agent independently enforce the same numeric payload contract without changing the wire schema.

## 2. Tasks

### T1 — Specify diagnostic security and quota behavior in tests

- Description: Add failing tests for safe directory reuse/creation, symlink and collision rejection, exact file permissions, 10 MiB truncation, 9/40 preflight retention, 10/50 close retention, unrelated-file preservation and best-effort failure.
- Deliverables: Expanded `QEMUGPULauncherTests.swift`; red-test evidence.
- Acceptance:
  - VC-LOG-001, VC-LOG-002 and VC-LOG-003 fail for the intended missing behavior before production changes.
  - Tests use isolated directories and verify negative side effects.
- Estimate: 0.5 day.
- Dependencies: approved design and verification cases.
- Priority: P0.
- Cases: VC-LOG-001, VC-LOG-002, VC-LOG-003.

### T2 — Harden LaunchDiagnosticsLog

- Description: Implement pre-`chmod` directory inspection, post-create validation, exclusive non-following file creation, bounded writes, truncation marker and managed-log cleanup. Preserve supervisor behavior when logging is unavailable.
- Deliverables: Production changes in `QEMUGPULauncher.swift`; green diagnostic tests.
- Acceptance:
  - VC-LOG-001, VC-LOG-002 and VC-LOG-003 pass.
  - No unsafe or unrelated directory entry is deleted or followed.
  - VM launch remains independent of diagnostics availability.
- Estimate: 0.75 day.
- Dependencies: T1.
- Priority: P0.
- Cases: VC-LOG-001, VC-LOG-002, VC-LOG-003, VC-E2E-001.

### T3 — Specify Force Stop confirmation races in tests

- Description: Add failing controller tests for cancel, confirm, duplicate request, child exit, session replacement, policy invalidation and termination takeover while confirmation is pending.
- Deliverables: Expanded `ManagementControllerBridgeTests.swift`; red-test evidence.
- Acceptance:
  - Existing direct-force behavior is proven to violate the new confirmation contract.
  - Tests assert exact supervisor signal sequences and lifecycle state.
- Estimate: 0.25 day.
- Dependencies: approved design and verification cases.
- Priority: P0.
- Cases: VC-FORCE-001, VC-FORCE-002.

### T4 — Centralize Force Stop confirmation

- Description: Remove View-owned confirmation, add one injectable controller confirmation seam backed by the existing AppKit presenter, guard duplicate prompts and revalidate the captured session after confirmation.
- Deliverables: Changes to `OverviewView.swift`, `ManagementAppKitPresenter.swift`, `VMApplicationController.swift`, and tests.
- Acceptance:
  - VC-FORCE-001 and VC-FORCE-002 pass.
  - Every UI command path reaches the controller gate.
  - OS termination and normal stop behavior remain unchanged.
- Estimate: 0.5 day.
- Dependencies: T3.
- Priority: P0.
- Cases: VC-FORCE-001, VC-FORCE-002, VC-E2E-001.

### T5 — Specify Swift Storage allowlist and compatibility behavior

- Description: Add failing pure-policy and integration tests for Home/Volumes true descendants, roots, lookalike prefixes, symlink escape, saved preferences, environment override, read-only estimates and unchanged legacy data.
- Deliverables: Expanded `StorageLocationTests.swift`; red-test evidence.
- Acceptance:
  - Tests cover every row in the allow/reject matrix.
  - Invalid environment overrides are proven not to fall back.
  - Legacy workspace fixtures remain byte-identical.
- Estimate: 0.5 day.
- Dependencies: approved design and verification cases.
- Priority: P0.
- Cases: VC-STORAGE-001, VC-STORAGE-002, VC-STORAGE-004.

### T6 — Apply the Swift Storage allowlist to every consumer

- Description: Implement component-aware canonical allowlist evaluation and route picker validation, stored preference, launch environment overrides and space-estimate lookup through it while retaining existing filesystem and capacity checks.
- Deliverables: Changes to `StorageLocation.swift`, `QEMUGPULauncher.swift`, `VMApplicationController.swift`, tests, and any necessary user-facing explanation.
- Acceptance:
  - VC-STORAGE-001, VC-STORAGE-002 and VC-STORAGE-004 pass.
  - Invalid override produces an unavailable reason and is absent from the child environment.
  - No data migration or deletion is introduced.
- Estimate: 0.75 day.
- Dependencies: T5.
- Priority: P0.
- Cases: VC-STORAGE-001, VC-STORAGE-002, VC-STORAGE-004, VC-E2E-001.

### T7 — Enforce the Storage allowlist in the shell runtime

- Description: Add shell contract cases, move the test workspace under the repository/Home allowlist, resolve the real account Home without trusting inherited `$HOME`, require explicit overrides to exist, and reject disallowed roots before mutation.
- Deliverables: Changes to `qemu-persistent-storage.sh` and `qemu-persistent-storage.test.sh`; green shell evidence.
- Acceptance:
  - VC-STORAGE-003 passes.
  - Default-path tests can still use an isolated fake `$HOME` only as a functional-path fixture; security-root decisions use the real account Home.
  - Test seams are function parameters or repository-owned fixtures, never production environment bypasses.
- Estimate: 0.75 day.
- Dependencies: T6 so the semantic matrix is fixed first.
- Priority: P0.
- Cases: VC-STORAGE-003, VC-REG-001.

### T8 — Specify the 10 MiB clipboard contract

- Description: Add host and guest failing tests for exactly 10 MiB, 10 MiB plus one byte and derived line budgets.
- Deliverables: Expanded Swift and Python clipboard tests; red-test evidence.
- Acceptance: VC-CLIP-001 and VC-CLIP-002 fail only because the old 16 MiB boundary remains.
- Estimate: 0.25 day.
- Dependencies: approved design and verification cases.
- Priority: P1.
- Cases: VC-CLIP-001, VC-CLIP-002.

### T9 — Align host and guest clipboard limits

- Description: Change both raw payload constants to 10 MiB and keep line budgets derived from those constants; do not alter formats or echo behavior.
- Deliverables: Changes to `NativeClipboardBridge.swift`, guest clipboard agent, and green tests.
- Acceptance: VC-CLIP-001 and VC-CLIP-002 pass with no existing clipboard regression.
- Estimate: 0.25 day.
- Dependencies: T8.
- Priority: P1.
- Cases: VC-CLIP-001, VC-CLIP-002, VC-REG-001.

### T10 — Consolidate verification evidence and user documentation

- Description: Execute all focused Cases, update architecture/user documentation only where behavior changed, run `make test`, and record commands, results, failures and evidence paths.
- Deliverables: `verification-report.md`, evidence under `.build/verification/local-security-hardening/`, and any required README/architecture updates.
- Acceptance:
  - VC-LOG-*, VC-FORCE-*, VC-STORAGE-*, VC-CLIP-* and VC-REG-001 all pass.
  - Every Spec acceptance criterion maps to passing evidence.
  - No secret-bearing or machine-specific raw log is committed.
- Estimate: 0.5 day plus runtime.
- Dependencies: T2, T4, T6, T7, T9.
- Priority: P0.
- Cases: all except VC-E2E-001, which runs after two-round review.

## 3. Task-to-Case matrix

| Task | Verification Cases | Independent acceptance |
|---|---|---|
| T1 | VC-LOG-001/002/003 | Red tests demonstrate missing behavior |
| T2 | VC-LOG-001/002/003, VC-E2E-001 | Logging contract passes |
| T3 | VC-FORCE-001/002 | Red tests demonstrate direct/unsafe behavior |
| T4 | VC-FORCE-001/002, VC-E2E-001 | Confirmation contract passes |
| T5 | VC-STORAGE-001/002/004 | Red tests demonstrate blacklist gaps |
| T6 | VC-STORAGE-001/002/004, VC-E2E-001 | All Swift consumers fail closed |
| T7 | VC-STORAGE-003, VC-REG-001 | Shell rejects before mutation |
| T8 | VC-CLIP-001/002 | Red tests demonstrate old 16 MiB boundary |
| T9 | VC-CLIP-001/002, VC-REG-001 | Both protocol endpoints use 10 MiB |
| T10 | all Cases | Reported evidence and complete regression |

## 4. Completion gate

Implementation is complete only when T1–T10 are green, the functional Case report is complete, two independent code-review passes have no open P0/P1 findings, VC-E2E-001 passes on the built app, and the final commit/tag/push state is recorded.
