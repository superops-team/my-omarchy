# My Omarchy Phase 1D Guest ABI 实施设计

## 1. Scope

Phase 1D completes the My Omarchy product identity migration inside the guest
image and the host-to-guest ABI. It covers guest repository/package/path names,
guest artifact identity, Docker guest builder resources, kernel command-line
tokens, virtio port names, boot-export integration, and the tests and docs that
describe those contracts.

This phase does not implement release candidates, upgrade compatibility,
backup/restore, diagnostics, or performance gates. It also does not migrate,
read, delete, or modify predecessor product data on the developer's machine.

## 2. Target ABI

The target values come from `config/product-identity.json`.

| Area | Target |
| --- | --- |
| Guest package prefix | `my-omarchy-` |
| Local pacman repository | `my-omarchy` |
| Guest share directory | `/usr/share/my-omarchy` |
| Guest library directory | `/usr/local/lib/my-omarchy` |
| Guest artifact kind | `my-omarchy-guest-artifacts` |
| Kernel prefix | `myomarchy.` |
| Virtio/service prefix | `team.superops.myomarchy.` |
| Docker resource prefix | `my-omarchy-` |

Predecessor tokens such as `try-omarchy-*`, `tryomarchy.*`,
`dev.tryomarchy.*`, and predecessor repository links are valid only as
historical source references after this phase.

## 3. Required changes

1. Guest package names move to `my-omarchy-runtime`,
   `my-omarchy-mise`, `my-omarchy-ttfx`, and `my-omarchy-yay`.
2. The guest local repository moves from the predecessor repo name to
   `my-omarchy`.
3. Guest support files move from predecessor share/library directories to
   `/usr/share/my-omarchy` and `/usr/local/lib/my-omarchy`.
4. Guest artifact manifests and host validation expect
   `my-omarchy-guest-artifacts`.
5. SSH activation and boot export kernel tokens move to
   `myomarchy.ssh_access=1` and `myomarchy.export_boot=1`.
6. Boot-export hook, install hook, completion marker, mount tag, and mkinitcpio
   references move to `my-omarchy-boot-export`.
7. Native audio, clipboard, and camera virtio ports move to
   `team.superops.myomarchy.audio`,
   `team.superops.myomarchy.clipboard`, and
   `team.superops.myomarchy.camera`.
8. Docker guest builder image, work volumes, and labels move to
   `my-omarchy-*` names.
9. Documentation and tests describe My Omarchy guest ABI. The release identity
   gate passes with only permanent historical-attribution and verification
   fixture entries.

## 4. Migration rules

This is a pre-1.0 product identity migration. No runtime compatibility bridge is
introduced for predecessor guest ABI values. Existing My Omarchy host code must
produce the new tokens and reject old generated artifacts. Historical
predecessor references may remain only in licensing, source attribution, and
approved design documents.

## 5. TDD sequence

1. Add or update contract tests for `guest/spec.json`, guest manifest kind,
   Docker resource names, boot-export token, SSH token, virtio port names, and
   guest support directories.
2. Update guest scripts, overlay filenames, systemd units, udev rules,
   mkinitcpio snippets, boot-export hooks, package registration scripts, and
   tests.
3. Update host launcher validation and shell tests that generate or inspect
   guest ABI values.
4. Regenerate `config/legacy-identity-allowlist.json` so `ownerPhase=1D`
   disappears.
5. Run the guest and host contract tests, then `make verify-release-identity`.

## 6. Verification

Required before commit:

1. `python3 -m unittest -v tests/test-product-identity.py tests/test-build-cache.py`
2. `guest/test`
3. `macos/Tests/run-qemu-ssh-contract.test.sh`
4. `macos/Tests/qemu-persistent-storage.test.sh`
5. `macos/Tests/qemu-port-forwarding.test.sh`
6. `macos/Tests/qemu-power-actions.test.sh`
7. `make verify-identity`
8. `make verify-release-identity`
9. `git diff --check`

If the local Swift `Testing` module remains unavailable, full `make test` may
still stop at the already recorded environment blocker after the Python, guest,
and shell gates pass.

## 7. Completion definition

Phase 1D is complete when all maintained guest ABI, artifact, Docker resource,
kernel-token, virtio-port, and guest package names use My Omarchy values; the
release identity gate passes; and the only remaining predecessor identity
references are permanent historical attribution or scanner verification
fixtures.
