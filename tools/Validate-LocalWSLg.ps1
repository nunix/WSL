<#
.SYNOPSIS
    Validates that a locally-built Microsoft.WSLg NuGet package exists in ./nupkgs
    and contains the files expected by the WSL build system.

.DESCRIPTION
    The WSL build consumes the following files from Microsoft.WSLg.1.0.73.nupkg:

        build/native/bin/x64/system.vhd          – x64 system distro VHD
        build/native/bin/x64/WSLDVCPlugin.dll    – x64 Terminal Services DVC plugin
        build/native/bin/arm64/system.vhd        – ARM64 system distro VHD
        build/native/bin/arm64/WSLDVCPlugin.dll  – ARM64 Terminal Services DVC plugin
        build/native/bin/wslg.rdp                – WSLg RDP configuration
        build/native/bin/wslg_desktop.rdp        – WSLg desktop RDP configuration

    Run this script from the repository root before starting the build to verify
    that the local override package has the correct layout.

.PARAMETER NupkgPath
    Path to the nupkg file to validate.
    Defaults to ./nupkgs/Microsoft.WSLg.1.0.73.nupkg.

.EXAMPLE
    # Validate the default package location
    .\tools\Validate-LocalWSLg.ps1

.EXAMPLE
    # Validate a specific nupkg file
    .\tools\Validate-LocalWSLg.ps1 -NupkgPath C:\artifacts\Microsoft.WSLg.1.0.73.nupkg
#>
[CmdletBinding()]
param(
    [string]$NupkgPath = (Join-Path $PSScriptRoot '..\nupkgs\Microsoft.WSLg.1.0.73.nupkg')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Resolve path ─────────────────────────────────────────────────────────────
$NupkgPath = [System.IO.Path]::GetFullPath($NupkgPath)

if (-not (Test-Path $NupkgPath)) {
    Write-Warning "Local WSLg package not found at: $NupkgPath"
    Write-Warning "The build will fall back to the upstream Microsoft.WSLg 1.0.73 package."
    Write-Warning "To use a custom WSLg build, follow the instructions in:"
    Write-Warning "  doc/docs/btrfs-rootfs.md – Section 5 (Custom WSLg Package)"
    exit 0   # non-fatal: upstream fallback is available
}

Write-Host "Validating: $NupkgPath" -ForegroundColor Cyan

# ─── Required entries inside the nupkg (zip) ──────────────────────────────────
$required = @(
    'build/native/bin/x64/system.vhd',
    'build/native/bin/x64/WSLDVCPlugin.dll',
    'build/native/bin/arm64/system.vhd',
    'build/native/bin/arm64/WSLDVCPlugin.dll',
    'build/native/bin/wslg.rdp',
    'build/native/bin/wslg_desktop.rdp'
)

# ─── Open as ZIP and collect entry names ──────────────────────────────────────
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead($NupkgPath)
try {
    $entries = $zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' }
} finally {
    $zip.Dispose()
}

# ─── Check each required entry ────────────────────────────────────────────────
$missing = @()
foreach ($req in $required) {
    if ($entries -notcontains $req) {
        $missing += $req
    }
}

if ($missing.Count -gt 0) {
    Write-Error "The following required files are missing from ${NupkgPath}:`n  $($missing -join "`n  ")"
    exit 1
}

Write-Host "All required files present. Package is valid." -ForegroundColor Green
exit 0
