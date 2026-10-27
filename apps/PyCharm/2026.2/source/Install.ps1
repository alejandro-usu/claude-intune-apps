<#
.SYNOPSIS
    Intune Win32 install script: PyCharm 2026.2.3, with Python 3.14 set as PyCharm's default
    interpreter and PyCharm's first-run prompts pre-answered.

.DESCRIPTION
    Runs as SYSTEM. Python 3.14 is a separate Intune app, which this one depends on, so Intune
    installs it first. Steps:
      1. Install PyCharm 2026.2.3 for all users (C:\Program Files\JetBrains\PyCharm 2026.2.3).
      2. Add a Windows Firewall rule for pycharm64.exe, so Windows doesn't ask each user
         whether to let PyCharm through the firewall.
      3. Copy Set-PyCharmUserDefaults.ps1 to an admin-only folder and register it with
         Active Setup, so it runs once for every user at their next logon. It accepts the
         JetBrains User Agreement, declines anonymous usage statistics and sets the default
         interpreter.
      4. Run Set-PyCharmUserDefaults.ps1 now for every existing user profile, so users who are
         already signed in get the settings without logging off.

    Logs: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\PyCharm-2026.2.3-Install.log
          (this script) and PyCharm-2026.2.3-Setup.log (the PyCharm installer)
#>
$ErrorActionPreference = 'Stop'

# The Intune Management Extension can start a 32-bit PowerShell. Relaunch as 64-bit so that
# Program Files and HKLM are not redirected to their WOW64 copies.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

# Installed by the Python 3.14 app. Patch releases keep this path.
$PythonExe = Join-Path $env:ProgramFiles 'Python314\python.exe'

$PyCharmInstaller = Join-Path $PSScriptRoot 'pycharm-2026.2.3.exe'
$PyCharmDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm 2026.2.3'

$DefaultsDir = Join-Path $env:ProgramFiles 'JetBrains\PyCharm-Python-Defaults'
$DefaultsScript = Join-Path $DefaultsDir 'Set-PyCharmUserDefaults.ps1'
$ActiveSetupKey = 'HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\PyCharm2026.2-Python3.14-Interpreter'
# Bump the last field to make Active Setup run again for users who already ran this version.
$ActiveSetupVersion = '2026,2,3,2'

# Inbound firewall rule for pycharm64.exe. Any rule for the program stops the Windows prompt.
# Block keeps PyCharm unreachable from other machines; its own features (debugger, built-in web
# server) talk over localhost, which Windows Firewall doesn't filter. Use 'Allow' instead if
# users need to reach PyCharm from another computer.
$FirewallAction = 'Block'
$FirewallGroup = 'PyCharm 2026.2.3'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'PyCharm-2026.2.3-Install.log') -Append | Out-Null

$exitCode = 0
try {
    # The dependency rule should have installed Python first. Without it, PyCharm still
    # installs; users just don't get Python 3.14 as their default interpreter.
    if (-not (Test-Path -LiteralPath $PythonExe)) {
        Write-Warning "Python not found at '$PythonExe'. Check the app's dependency on Python 3.14."
    }

    # --- 1. PyCharm ---------------------------------------------------------------------------
    # NSIS rule: /D= must come last and must not be quoted, even when the path has spaces.
    $pycharmArgs = "/S /CONFIG=`"$(Join-Path $PSScriptRoot 'silent.config')`" " +
        "/LOG=`"$(Join-Path $LogDir 'PyCharm-2026.2.3-Setup.log')`" /D=$PyCharmDir"
    Write-Output "Running: `"$PyCharmInstaller`" $pycharmArgs"
    $process = Start-Process -FilePath $PyCharmInstaller -ArgumentList $pycharmArgs -Wait -PassThru -WindowStyle Hidden
    Write-Output "Exit code: $($process.ExitCode)"
    if ($process.ExitCode -ne 0) { throw "PyCharm install failed with exit code $($process.ExitCode)" }
    if (-not (Test-Path -LiteralPath (Join-Path $PyCharmDir 'bin\pycharm64.exe'))) {
        throw "PyCharm install finished but '$PyCharmDir\bin\pycharm64.exe' is missing"
    }

    # --- 2. Firewall -------------------------------------------------------------------------
    Get-NetFirewallRule -Group $FirewallGroup -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    New-NetFirewallRule -DisplayName 'PyCharm 2026.2.3' -Group $FirewallGroup `
        -Program (Join-Path $PyCharmDir 'bin\pycharm64.exe') -Direction Inbound `
        -Action $FirewallAction -Profile Any | Out-Null
    Write-Output "Firewall: inbound $FirewallAction rule added for pycharm64.exe"

    # --- 3. Per-user defaults via Active Setup ------------------------------------------------
    New-Item -ItemType Directory -Path $DefaultsDir -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Set-PyCharmUserDefaults.ps1') -Destination $DefaultsScript -Force

    New-Item -Path $ActiveSetupKey -Force | Out-Null
    Set-ItemProperty -Path $ActiveSetupKey -Name '(default)' -Value 'PyCharm 2026.2 user defaults'
    Set-ItemProperty -Path $ActiveSetupKey -Name 'StubPath' -Value (
        "`"$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoProfile -NonInteractive " +
        "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$DefaultsScript`"")
    Set-ItemProperty -Path $ActiveSetupKey -Name 'Version' -Value $ActiveSetupVersion
    Set-ItemProperty -Path $ActiveSetupKey -Name 'IsInstalled' -Value 1 -Type DWord

    # --- 4. Existing profiles, now -----------------------------------------------------------
    $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
    foreach ($entry in Get-ChildItem -Path $profileList) {
        # Local/domain accounts (S-1-5-21-*) and Entra ID accounts (S-1-12-1-*).
        if ($entry.PSChildName -notmatch '^S-1-(5-21|12-1)-') { continue }
        $profilePath = (Get-ItemProperty -Path $entry.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath
        if (-not $profilePath) { continue }
        $roaming = Join-Path ([Environment]::ExpandEnvironmentVariables($profilePath)) 'AppData\Roaming'
        if (-not (Test-Path -LiteralPath $roaming)) { continue }
        # A signed-in user's registry hive is loaded under HKEY_USERS. For anyone else, Active
        # Setup sets the registry part at their next logon.
        $hive = "Registry::HKEY_USERS\$($entry.PSChildName)"
        $registryRoot = if (Test-Path -LiteralPath $hive) { $hive } else { '' }
        try {
            & $DefaultsScript -ConfigRoot $roaming -RegistryRoot $registryRoot
        } catch {
            Write-Warning "Could not configure PyCharm for '$profilePath': $($_.Exception.Message)"
        }
    }

    Write-Output 'Install complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
