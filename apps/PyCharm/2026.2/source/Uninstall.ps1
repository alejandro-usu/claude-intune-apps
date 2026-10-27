<#
.SYNOPSIS
    Intune Win32 uninstall script for PyCharm 2026.2.3.

.DESCRIPTION
    Runs as SYSTEM. Removes PyCharm 2026.2.3, its firewall rule, the Active Setup entry and the
    per-user defaults script. Python 3.14 is a separate app and stays installed. Users' own
    PyCharm settings in %APPDATA% are left alone.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PyCharm-2026.2.3-Uninstall.log
#>
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$PyCharmDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm 2026.2.3'
$DefaultsDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm-Python-Defaults'
$ActiveSetupKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\PyCharm2026.2-Python3.14-Interpreter'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'PyCharm-2026.2.3-Uninstall.log') -Append | Out-Null

$exitCode = 0
try {
    # --- PyCharm ------------------------------------------------------------------------------
    Get-Process -Name pycharm64, pycharm -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like "$PyCharmDir\*" } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $uninstaller = Join-Path $PyCharmDir 'bin\Uninstall.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        Write-Output "Running: `"$uninstaller`" /S"
        $process = Start-Process -FilePath $uninstaller -ArgumentList '/S' -Wait -PassThru
        # Logged only: this is the exit code of the stub, not of the real uninstall (below).
        Write-Output "Exit code: $($process.ExitCode)"
        # The NSIS uninstaller copies itself to %TEMP% and continues from there, so the process
        # above returns early. Wait for the real work to finish.
        $deadline = (Get-Date).AddMinutes(15)
        while ((Test-Path -LiteralPath (Join-Path $PyCharmDir 'bin\pycharm64.exe')) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 5
        }
        Get-Process -Name 'Un_*', 'Au_*' -ErrorAction SilentlyContinue | Wait-Process -Timeout 300 -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $PyCharmDir) {
        Remove-Item -LiteralPath $PyCharmDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Stop here if PyCharm is still installed. Removing the firewall rule and Active Setup key
    # below would make Detect.ps1 report the app as gone, and Intune would record a failed
    # uninstall as a success.
    $remaining = @('bin\pycharm64.exe', 'product-info.json') |
        Where-Object { Test-Path -LiteralPath (Join-Path $PyCharmDir $_) }
    if ($remaining) {
        throw "PyCharm is still installed; found $($remaining -join ', ') in '$PyCharmDir'"
    }

    # --- Firewall rule and per-user defaults hook ---------------------------------------------
    Get-NetFirewallRule -Group 'PyCharm 2026.2.3' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Remove-Item -Path $ActiveSetupKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $DefaultsDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output 'Uninstall complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
