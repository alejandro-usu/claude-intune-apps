<#
.SYNOPSIS
    Intune Win32 uninstall script for MATLAB R2026b (both editions).

.DESCRIPTION
    Runs as SYSTEM. Stops MATLAB, runs MathWorks' uninstaller for C:\Program Files\MATLAB\R2026b,
    then removes anything it left behind: the folder, Start menu shortcuts into it and its PATH
    entry. Both editions install to the same folder, so this removes every R2026b product on the
    device. Users' own MATLAB settings in %APPDATA%\MathWorks are left alone.

    Log: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\MATLAB-R2026b-Uninstall.log
#>
$ErrorActionPreference = 'Stop'

if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
    exit $LASTEXITCODE
}

$MatlabRoot = Join-Path $env:ProgramFiles 'MATLAB\R2026b'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'MATLAB-R2026b-Uninstall.log') -Append | Out-Null

$exitCode = 0
try {
    # --- MATLAB -------------------------------------------------------------------------------
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { try { $_.Path -like "$MatlabRoot\*" } catch { $false } } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $uninstaller = Join-Path $MatlabRoot 'bin\win64\MathWorksProductUninstaller.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        Write-Output "Running: `"$uninstaller`" --mode silent"
        $process = Start-Process -FilePath $uninstaller -ArgumentList '--mode silent' -Wait -PassThru -WindowStyle Hidden
        # Whatever it reports, the steps below remove what's left.
        Write-Output "Exit code: $($process.ExitCode)"
        Get-Process -Name MathWorksProductUninstaller -ErrorAction SilentlyContinue |
            Wait-Process -Timeout 1800 -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $MatlabRoot) {
        Remove-Item -LiteralPath $MatlabRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath (Join-Path $MatlabRoot 'bin\matlab.exe')) {
        throw "Could not remove '$MatlabRoot'"
    }
    # Leave C:\Program Files\MATLAB if other releases are in it.
    $parent = Split-Path -Path $MatlabRoot -Parent
    if ((Test-Path -LiteralPath $parent) -and -not (Get-ChildItem -LiteralPath $parent -Force)) {
        Remove-Item -LiteralPath $parent -Force
    }

    # --- Start menu shortcuts and PATH --------------------------------------------------------
    $startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    $shell = New-Object -ComObject WScript.Shell
    Get-ChildItem -LiteralPath $startMenu -Filter *.lnk -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $shell.CreateShortcut($_.FullName).TargetPath -like "$MatlabRoot\*" } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $binDir = Join-Path $MatlabRoot 'bin'
    $envKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    try {
        $entries = @($envKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames') -split ';' | Where-Object { $_ })
        $kept = @($entries | Where-Object { $_.TrimEnd('\') -ne $binDir })
        if ($kept.Count -ne $entries.Count) {
            $envKey.SetValue('Path', ($kept -join ';'), 'ExpandString')
            Write-Output "PATH: removed $binDir"
        }
    } finally {
        $envKey.Close()
    }

    Write-Output 'Uninstall complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $exitCode
