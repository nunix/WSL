# BTRFS Rootfs Support for WSL2

This document describes the BTRFS (and XFS) rootfs feature for WSL2, how to use
it, how to reapply the patch on future upstream releases, and the complete
end-to-end workflow to build a distributable `msixbundle` from a GitHub Actions
runner.

---

## Background

By default WSL2 formats its virtual hard disk (VHD) with the **ext4** file
system. A community member ([artiga033](https://github.com/artiga033/WSL))
implemented support for **btrfs** and **xfs** as alternative rootfs types,
originally based on WSL 2.6.x ([feature-release/custom-root-fs@2.6.3](
https://github.com/artiga033/WSL/releases/tag/feature-release%2Fcustom-root-fs%402.6.3)).

This fork adapts those changes to the **pre-release (2.7.x)** codebase at
[nunix/WSL](https://github.com/nunix/WSL).

The feature implements [microsoft/WSL#9339](https://github.com/microsoft/WSL/issues/9339).

---

## Section 1 – What Changed (Code Adaptation)

The following files were modified to port the feature from the 2.6.x base to
the 2.7.x pre-release codebase.  A single-commit patch that can be (re)applied
to any future upstream version lives at:

```
patches/0001-feat-allow-custom-root-fs-type-and-mount-options.patch
```

### Files modified

| File | What changed |
|------|-------------|
| `src/linux/init/main.cpp` | `FormatDevice()` now accepts a filesystem type and calls `mkfs.ext4`, `mkfs.btrfs`, or `mkfs.xfs`. New `CreateBtrfsSubvolumeOnDevice()` helper creates the `subvol=` target automatically. `ProcessImportExportMessage()` passes the FS type and mount options through. |
| `src/windows/inc/wsl.h` | Added `WSL_IMPORT_ARG_FS_TYPE` (`--fs-type`) and `WSL_IMPORT_ARG_FS_MOUNT_OPTIONS` (`--fs-mount-options`) constants. |
| `src/windows/service/inc/wslservice.idl` | Added `FsType` / `FsMountOptions` parameters to `RegisterDistribution` and `RegisterDistributionPipe` IDL methods. Added `LXSS_DISTRO_DEFAULT_FS_TYPE` and per-FS default mount option macros. |
| `src/windows/service/exe/DistributionRegistration.cpp/.h` | `FsType` and `FsMountOptions` are persisted to and read from the Windows registry. Default mount options are chosen per FS type when only `--fs-type` is given. |
| `src/windows/service/exe/LxssCreateProcess.h` | Added `FsType` and `FsMountOptions` fields to `LXSS_DISTRO_CONFIGURATION`. |
| `src/windows/service/exe/LxssUserSession.cpp/.h` | `RegisterDistribution` signature extended; values read from registry into distro configuration. |
| `src/windows/service/exe/WslCoreVm.cpp` | Uses `Configuration.FsType` / `Configuration.FsMountOptions` instead of hard-coded `"ext4"` / `"discard,errors=remount-ro,data=ordered"`. |
| `src/windows/service/exe/WslCoreInstance.cpp` | Removed `EINVAL` from the disk-corruption error check so that an unknown FS type does not trigger a false "disk corrupted" error. |
| `src/windows/common/WslClient.cpp` | Parses `--fs-type` and `--fs-mount-options` in both `--import` and `--install` code paths. |
| `src/windows/common/WslInstall.cpp/.h` | `InstallDistribution` and `InstallModernDistribution` accept and forward `fsType` / `fsMountOptions`. |
| `src/windows/common/svccomm.cpp/.hpp` | `RegisterDistribution` forwards `FsType` / `MountOptions` to the RPC call. |
| `localization/strings/en-US/Resources.resw` | Help text for the two new arguments. |
| `localization/strings/zh-CN/Resources.resw` | Chinese translations for the two new arguments. |

---

## Section 2 – Reapplying the Patch to a Future Version

When Microsoft releases a new upstream version of WSL, follow these steps to
reapply the BTRFS feature.

### Prerequisites (cross-platform – works on Linux or Windows)

- `git` ≥ 2.39
- `patch` utility (Linux) **or** `git apply` (Windows / Linux)

### Steps

```bash
# 1. Fetch the latest upstream changes into your fork
git remote add upstream https://github.com/microsoft/WSL   # first time only
git fetch upstream

# 2. Rebase or merge upstream main into your feature branch
git checkout copilot/adapt-btrfs-for-wsl2
git rebase upstream/main        # or: git merge upstream/main

# 3. If the patch is not yet applied, apply it
#    (git apply is smarter than patch(1) for C++ code with context changes)
git apply --whitespace=nowarn \
  patches/0001-feat-allow-custom-root-fs-type-and-mount-options.patch

# 4. Resolve any conflicts
#    The most likely conflict areas are:
#      - src/linux/init/main.cpp  (around FormatDevice / ProcessImportExportMessage)
#      - src/windows/service/exe/LxssUserSession.cpp  (RegisterDistribution signature)
#      - src/windows/service/inc/wslservice.idl       (IDL method signatures)

# 5. After resolving, regenerate the patch for next time
git add -p          # stage only the BTRFS-related changes
git diff --cached > patches/0001-feat-allow-custom-root-fs-type-and-mount-options.patch
```

> **Tip:** The patch is deliberately kept as a single-commit file so it can be
> reviewed, shared, and reapplied mechanically.  Use `git apply --check` first
> to do a dry-run without touching the working tree.

---

## Section 3 – End-to-End Build Workflow

The GitHub Actions workflow at
`.github/workflows/btrfs-build.yml` implements the full pipeline.
Trigger it manually from the **Actions** tab → **Build WSL with BTRFS rootfs
support** → **Run workflow**.

### Prerequisites – Windows build machine

> **All steps below are one-time setup on the self-hosted runner machine.**

#### 1. Enable Developer Mode

```powershell
# PowerShell (Administrator) – enable Developer Mode for symbolic-link support
$path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
Set-ItemProperty -Path $path -Name AllowDevelopmentWithoutDevLicense -Value 1
```

Or via **Settings → System → For developers → Developer Mode → On**.

#### 2. Install CMake ≥ 3.25

```powershell
winget install Kitware.CMake
# Verify:
cmake --version
```

#### 3. Install Visual Studio 2022 with required components

```cmd
:: Download the VS installer, then run (adjust channel as needed):
vs_community.exe --passive --norestart ^
  --add Microsoft.VisualStudio.Component.Windows11SDK.26100 ^
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 ^
  --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 ^
  --add Microsoft.VisualStudio.Component.VC.Runtimes.ARM64.Spectre ^
  --add Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre ^
  --add Microsoft.VisualStudio.Component.VC.ATL ^
  --add Microsoft.VisualStudio.Component.VC.ATL.ARM64 ^
  --add Microsoft.VisualStudio.Component.VC.ClangToolset ^
  --add Microsoft.VisualStudio.Component.ManagedDesktop.Core ^
  --add Microsoft.VisualStudio.Workload.NativeDesktop ^
  --add Microsoft.VisualStudio.Workload.Universal ^
  --add Microsoft.VisualStudio.Workload.ManagedDesktop ^
  --add Microsoft.VisualStudio.Component.WinUI
```

#### 4. Register the self-hosted GitHub Actions runner

Follow the GitHub documentation for [adding a self-hosted runner](
https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/adding-self-hosted-runners).
Add the labels **`self-hosted`**, **`windows`**, and **`x64`** to match the
`runs-on` values in the workflow file.

Run the runner service as **Administrator** so the unit tests can execute.

---

### Building manually (without GitHub Actions)

If you prefer to build on a local Windows machine without a CI runner:

```powershell
# Clone the fork
git clone https://github.com/nunix/WSL
cd WSL

# (Optional) Ensure the patch is applied
git apply --check patches\0001-feat-allow-custom-root-fs-type-and-mount-options.patch
git apply --whitespace=nowarn patches\0001-feat-allow-custom-root-fs-type-and-mount-options.patch

# Generate the Visual Studio solution (x64)
cmake . -A x64 -DCMAKE_BUILD_TYPE=Release

# Build  (takes 20–45 min – do NOT cancel)
cmake --build . --config Release -- -m

# Optionally build for ARM64 as well (required for the bundle)
cmake . -A arm64 -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release -- -m

# Build the msixbundle (requires both x64 and ARM64 builds)
cmake . -A x64 -DCMAKE_BUILD_TYPE=Release -DBUILD_BUNDLE=TRUE
cmake --build . --config Release -- -m
```

The finished packages are located under `bin\<platform>\<target>\`:

| Artefact | Description |
|----------|-------------|
| `wsl.msi` | Traditional MSI installer for one architecture |
| `*.msix` | Per-architecture MSIX package |
| `*.msixbundle` | Multi-architecture bundle (install this one) |

#### Install the unsigned bundle

```powershell
# Developer Mode must be ON  (see Step 1 above)
Add-AppxPackage -AllowUnsigned .\Microsoft.WSL_*_x64_ARM64.msixbundle
```

---

### Running the unit tests

```powershell
# After a full build, run only the unit-test subset (5–15 min):
bin\x64\Release\test.bat /name:*UnitTest*

# Full test suite (30–60 min, requires Administrator):
bin\x64\Release\test.bat

# Speed up subsequent runs (skip package reinstall):
wsl --set-default test_distro
bin\x64\Release\test.bat /name:*UnitTest* -f
```

> **Note:** Tests require Administrator privileges.  Run PowerShell or the
> Command Prompt as Administrator before executing `test.bat`.

---

## Section 4 – Using the BTRFS Feature

Once WSL is installed from the custom build, the two new arguments are
available on `wsl --install` and `wsl --import`:

```
--fs-type <type>
    Filesystem type for the distribution rootfs (ext4 | btrfs | xfs).
    Defaults to ext4.

--fs-mount-options <options>
    Additional mount options for the rootfs filesystem.
    If omitted, sensible defaults are chosen per filesystem type:
      ext4  → discard,errors=remount-ro,data=ordered
      btrfs → discard
      xfs   → discard
```

### Quick-start examples

```powershell
# Install from a .wsl file using the default ext4 (unchanged behaviour)
wsl --install --from-file .\archlinux.wsl

# Install with btrfs and default mount options
wsl --install --from-file .\archlinux.wsl --fs-type btrfs

# Install with btrfs, custom mount options, and an automatic subvolume
wsl --install --from-file .\ubuntu.wsl `
    --fs-type btrfs `
    --fs-mount-options "compress=zstd,subvol=@,ssd,discard"

# Import a tar with xfs
wsl --import MyDistro C:\WSL\MyDistro .\rootfs.tar.gz --fs-type xfs

# Import with btrfs and a specific subvolume layout (timeshift-compatible)
wsl --import Ubuntu C:\WSL\Ubuntu .\ubuntu.tar.gz `
    --fs-type btrfs `
    --fs-mount-options "compress=zstd,subvol=@,ssd"
```

> **btrfs subvolume auto-creation:** When `subvol=<name>` is present in
> `--fs-mount-options`, the specified subvolume is created automatically on
> first import if it does not already exist.

### Verifying the filesystem inside WSL

```bash
# Inside the WSL shell, confirm the rootfs filesystem type:
findmnt -n -o FSTYPE /

# For btrfs – list subvolumes:
sudo btrfs subvolume list /

# For btrfs – show filesystem usage:
sudo btrfs filesystem usage /
```
