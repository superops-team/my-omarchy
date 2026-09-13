# My Omarchy Phase 3 Resource Profile Implementation

## 1. Scope

This slice starts Phase 3 by removing the launcher's fixed 4 GiB RAM and
up-to-8 vCPU defaults. It implements the first machine-readable
`VMResourceProfile v1` contract and wires normal launches through it.

This does not claim that Phase 3 performance qualification, discard/fstrim, or
video benchmarking is complete.

## 2. Resource Profile v1

The Swift launcher owns resource selection. The shell launcher consumes the
selected values and fails closed if they are absent or outside the approved
range. Shell code must not independently choose resources from host hardware.

Automatic profile:

| Host physical memory | Guest vCPUs | Guest RAM |
|----------------------|-------------|-----------|
| 8 GiB to <16 GiB | 4 | 2560 MiB |
| 16 GiB to <24 GiB | 4 | 4096 MiB |
| >=24 GiB | 6 | 4096 MiB |

CPU rule:

- Host must report enough active processors to run at least 4 guest vCPUs while
  reserving 2 host CPUs for macOS.
- Automatic defaults must never choose 8 vCPUs.

Low-resource profile:

- `low-resource-v1`
- 4 vCPUs
- 2048 MiB RAM
- Still requires the 8 GiB host memory floor and CPU reserve rule.

## 3. Environment Contract

Swift sets these environment variables for `run-qemu-gpu.sh`:

- `OMARCHY_QEMU_GPU_RESOURCE_PROFILE`
- `OMARCHY_QEMU_GPU_VCPUS`
- `OMARCHY_QEMU_GPU_MEMORY_MIB`

The shell validates:

- profile is `automatic-v1`, `low-resource-v1`, or `custom-v1`;
- built-in profile vCPU count is a positive integer in `[4, 6]`; custom profile
  vCPU count is `[4, host logical CPUs - 4]`;
- built-in profile memory is `[2048, 4096]` MiB; custom profile memory is
  `[2048, floor(host memory MiB * 70% / 512) * 512]`.

Invalid or missing resource variables must fail before persistent storage
selection so a bad launch request cannot create, reset, or migrate VM disks.

## 4. Verification

Required checks:

1. `cd macos && swift test --disable-sandbox --filter VMResourceProfileTests`
2. `macos/Tests/run-qemu-ssh-contract.test.sh`
3. `guest/test`
4. `make test`
5. `make verify-identity`
6. `make verify-release-identity`
7. `git diff --check`

## 5. Deferred Phase 3 Work

- UI selection for automatic, low-resource, and user-customized profiles.
- Dynamic memory balloon policy.
- Guest fstrim/discard implementation and APFS allocated-byte evidence.
- Benchmark schema and real-device performance evidence.
