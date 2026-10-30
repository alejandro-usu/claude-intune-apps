<#
.SYNOPSIS
    Intune Win32 install script: Python packages (numpy, matplotlib, pandas, scipy, sympy,
    dataretrieval, ipykernel and their dependencies) for Python 3.15, machine-wide.

.DESCRIPTION
    Runs as SYSTEM. Python 3.15 is a separate Intune app, which this one depends on, so Intune
    installs it first. Steps:
      1. pip installs every wheel in requirements.txt into C:\Program Files\Python315, offline
         (--no-index, from the wheels in this package) and only if each file's SHA-256 matches
         (--require-hashes).
      2. Checks that the packages import and that the exact versions are installed.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.15-Packages-Install.log
#>
$ErrorActionPreference = 'Stop'

# The Intune Management Extension can start a 32-bit PowerShell. Relaunch as 64-bit so that
# Program Files and HKLM are not redirected to their WOW64 copies.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

# Installed by the Python 3.15 app. Patch releases keep this path, and keep these packages.
$PythonExe = Join-Path $env:ProgramFiles 'Python315\python.exe'
$SitePackages = Join-Path $env:ProgramFiles 'Python315\Lib\site-packages'
# The packages in requirements.in, at the versions tools/pin_wheels.py pinned. Detect.ps1 checks
# the same list.
$Expected = @(
    'dataretrieval-1.4.0.dist-info'
    'ipykernel-7.4.0.dist-info'
    'matplotlib-3.11.2.dist-info'
    'numpy-2.5.4.dist-info'
    'pandas-3.1.0.dist-info'
    'scipy-1.18.1.dist-info'
    'sympy-1.14.0.dist-info'
)
$ImportCheck = 'import dataretrieval, ipykernel, matplotlib, numpy, pandas, scipy, sympy'

$AppLogName = 'Python-3.15-Packages'
$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "$AppLogName-Install.log") -Append | Out-Null

function Invoke-Python([string[]]$Arguments) {
    # Windows PowerShell turns a native command's redirected stderr into errors, which 'Stop'
    # would throw on pip's first warning. Relax it for this call only; the exit code decides.
    $ErrorActionPreference = 'Continue'
    Write-Host "Running: `"$PythonExe`" $($Arguments -join ' ')"
    & $PythonExe @Arguments 2>&1 | ForEach-Object { Write-Host "$_" }
    $code = $LASTEXITCODE
    Write-Host "Exit code: $code"
    return $code
}

$exitCode = 0
try {
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        throw "Python not found at '$PythonExe'. Check the app's dependency on Python 3.15."
    }

    # --isolated ignores pip settings from environment variables and config files on the device.
    $code = Invoke-Python @('-m', 'pip', 'install', '--isolated', '--no-index', '--find-links', $PSScriptRoot,
        '--require-hashes', '--only-binary', ':all:', '--requirement', (Join-Path $PSScriptRoot 'requirements.txt'),
        '--no-warn-script-location', '--disable-pip-version-check', '--no-input', '--no-cache-dir')
    if ($code -ne 0) { throw "pip install failed with exit code $code" }

    $code = Invoke-Python @('-c', $ImportCheck)
    if ($code -ne 0) { throw "The packages installed but don't import (exit code $code); see the error above" }

    $missing = @($Expected | Where-Object { -not (Test-Path -LiteralPath (Join-Path $SitePackages $_)) })
    if ($missing) { throw "Missing after install: $($missing -join ', ')" }

    Write-Output 'Install complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
