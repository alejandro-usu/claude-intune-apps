<#
.SYNOPSIS
    Intune custom detection script for the Python 3.15 packages app (2026.10.30).

.DESCRIPTION
    Reports "installed" (writes to stdout, exits 0) only when each package named in
    requirements.in is installed in C:\Program Files\Python315 at the version this package pins.
    pip records each installed version as a <name>-<version>.dist-info folder in site-packages.
    Set "Run script as 32-bit process on 64-bit clients" to No.
#>
$programFiles = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
$sitePackages = Join-Path $programFiles 'Python315\Lib\site-packages'
# Must match $Expected in source/Install.ps1.
$expected = @(
    'dataretrieval-1.4.0.dist-info'
    'ipykernel-7.4.0.dist-info'
    'matplotlib-3.11.2.dist-info'
    'numpy-2.5.4.dist-info'
    'pandas-3.1.0.dist-info'
    'scipy-1.18.1.dist-info'
    'sympy-1.14.0.dist-info'
)

try {
    foreach ($distInfo in $expected) {
        if (-not (Test-Path -LiteralPath (Join-Path $sitePackages $distInfo))) { exit 1 }
    }
    Write-Output 'Python 3.15 packages 2026.10.30 detected'
    exit 0
} catch {
    exit 1
}
