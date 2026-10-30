<#
.SYNOPSIS
    Intune Win32 uninstall script: Python 3.15 packages.

.DESCRIPTION
    Runs as SYSTEM. pip uninstalls every package in requirements.txt from
    C:\Program Files\Python315, then checks they're gone. Python itself, and pip, stay.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.15-Packages-Uninstall.log
#>
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$PythonExe = Join-Path $env:ProgramFiles 'Python315\python.exe'
$SitePackages = Join-Path $env:ProgramFiles 'Python315\Lib\site-packages'
# Must match Install.ps1 and Detect.ps1.
$Expected = @(
    'dataretrieval-1.4.0.dist-info'
    'ipykernel-7.4.0.dist-info'
    'matplotlib-3.11.2.dist-info'
    'numpy-2.5.4.dist-info'
    'pandas-3.1.0.dist-info'
    'scipy-1.18.1.dist-info'
    'sympy-1.14.0.dist-info'
)

$AppLogName = 'Python-3.15-Packages'
$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir "$AppLogName-Uninstall.log") -Append | Out-Null

function Invoke-Python([string[]]$Arguments) {
    # See Install.ps1: keep pip's warnings from stopping the script; the exit code decides.
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
        # Uninstalling Python removed its site-packages, and these packages with it.
        Write-Output "Python not found at '$PythonExe'; nothing to remove."
    } else {
        $names = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'requirements.txt') |
            Where-Object { $_ -match '^([A-Za-z0-9_.\-]+)==' } | ForEach-Object { $Matches[1] })
        # pip skips, with a warning, any package that isn't installed.
        $code = Invoke-Python (@('-m', 'pip', 'uninstall', '--yes', '--isolated', '--disable-pip-version-check') + $names)
        if ($code -ne 0) { throw "pip uninstall failed with exit code $code" }

        $remaining = @($Expected | Where-Object { Test-Path -LiteralPath (Join-Path $SitePackages $_) })
        if ($remaining) { throw "Still installed: $($remaining -join ', ')" }
    }
    Write-Output 'Uninstall complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
