<#
.SYNOPSIS
    Intune Win32 install script: MATLAB R2026b from MathWorks, licensed from a network license
    server.

.DESCRIPTION
    Runs as SYSTEM. One package serves two Intune apps, picked with -Edition:
      Simulink    MATLAB and Simulink
      Toolboxes   MATLAB, Simulink and the common toolboxes listed in $Editions below

    Steps:
      1. Download MATLAB Package Manager (mpm.exe) from MathWorks and check that MathWorks
         signed it.
      2. Run mpm to download and install the edition's products into
         C:\Program Files\MATLAB\R2026b. mpm skips products that are already there, so running
         the Toolboxes edition on a device with the Simulink edition just adds the toolboxes.
      3. Write licenses\network.lic, pointing MATLAB at -LicenseServer (port@host).
      4. Add a Start menu shortcut and put MATLAB's bin folder on the system PATH, unless mpm
         already did.
      5. Record the installed products in IntuneProducts.txt for the detection scripts.

    Example:
      Install.ps1 -Edition Toolboxes -LicenseServer 27000@license.example.edu

    Logs: C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\MATLAB-R2026b-Install.log
          (this script), MATLAB-R2026b-mpm.log and MATLAB-R2026b-mpm.err.log (mpm's output)
#>
param(
    [string]$Edition,
    [string]$LicenseServer
)
$ErrorActionPreference = 'Stop'

# The Intune Management Extension can start a 32-bit PowerShell. Relaunch as 64-bit so that
# Program Files and HKLM are not redirected to their WOW64 copies.
if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
    $powershell64 = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
    $forward = foreach ($key in $PSBoundParameters.Keys) { "-$key"; $PSBoundParameters[$key] }
    & $powershell64 -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @forward
    exit $LASTEXITCODE
}

# Product names as mpm spells them (underscores for spaces). mpm adds required products itself.
# Detect-Simulink.ps1 and Detect-Toolboxes.ps1 check the same lists; keep them in sync.
$Editions = @{
    Simulink  = @('MATLAB', 'Simulink')
    Toolboxes = @('MATLAB', 'Simulink', 'Statistics_and_Machine_Learning_Toolbox', 'Optimization_Toolbox',
        'Signal_Processing_Toolbox', 'Image_Processing_Toolbox', 'Control_System_Toolbox',
        'Symbolic_Math_Toolbox', 'Curve_Fitting_Toolbox')
}

# mpm installs the latest update of the release. To pin an update level, use e.g. 'R2026bU1'.
$MpmRelease = 'R2026b'
$MatlabRoot = Join-Path $env:ProgramFiles 'MATLAB\R2026b'
# Always serves the latest mpm. Newer MATLAB releases need a recent mpm, so it isn't pinned.
$MpmUrl = 'https://www.mathworks.com/mpm/win64/mpm'
$WorkDir = Join-Path ([IO.Path]::GetTempPath()) 'MATLAB-R2026b-Install'

$LogDir = Join-Path $env:ProgramData 'Microsoft\IntuneManagementExtension\Logs'
$MpmLog = Join-Path $LogDir 'MATLAB-R2026b-mpm.log'
$MpmErrorLog = Join-Path $LogDir 'MATLAB-R2026b-mpm.err.log'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'MATLAB-R2026b-Install.log') -Append | Out-Null

$exitCode = 0
try {
    if (-not $Edition -or -not $Editions.ContainsKey($Edition)) {
        throw "Pass -Edition $(($Editions.Keys | Sort-Object) -join ' or ')."
    }
    if ($LicenseServer -notmatch '^(\d+)@([A-Za-z0-9.-]+)$') {
        throw 'Pass -LicenseServer as port@host, for example 27000@license.example.edu.'
    }
    $port, $serverHost = $Matches[1], $Matches[2]
    $products = $Editions[$Edition]
    $matlabExe = Join-Path $MatlabRoot 'bin\matlab.exe'
    $alreadyInstalled = Test-Path -LiteralPath $matlabExe
    Write-Output "Edition ${Edition}: $($products -join ', ')"

    # --- 1. mpm -------------------------------------------------------------------------------
    Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null
    $mpm = Join-Path $WorkDir 'mpm.exe'
    Write-Output "Downloading $MpmUrl"
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $ProgressPreference = 'SilentlyContinue'  # the progress bar makes Invoke-WebRequest very slow
    Invoke-WebRequest -Uri $MpmUrl -OutFile $mpm -UseBasicParsing
    # No fixed hash to check against, so check MathWorks' code signature instead.
    $signature = Get-AuthenticodeSignature -FilePath $mpm
    $signer = $signature.SignerCertificate.Subject
    if ($signature.Status -ne 'Valid' -or $signer -notmatch '(^|,\s*)O="?(The )?MathWorks,? Inc\.?"?(,|$)') {
        throw "mpm.exe from $MpmUrl is not validly signed by MathWorks (status: $($signature.Status), signer: '$signer')"
    }
    Write-Output "mpm.exe signed by: $signer"

    # --- 2. Products --------------------------------------------------------------------------
    # mpm downloads into TEMP. Point it at the work folder, which is deleted at the end.
    $env:TEMP = $WorkDir
    $env:TMP = $WorkDir
    $mpmArgs = "install --release=$MpmRelease `"--destination=$MatlabRoot`" --products $($products -join ' ')"
    Write-Output "Running: `"$mpm`" $mpmArgs"
    $process = Start-Process -FilePath $mpm -ArgumentList $mpmArgs -Wait -PassThru -NoNewWindow `
        -RedirectStandardOutput $MpmLog -RedirectStandardError $MpmErrorLog
    Write-Output "Exit code: $($process.ExitCode)"
    if ($process.ExitCode -ne 0) {
        Get-Content -LiteralPath $MpmErrorLog -Tail 20 -ErrorAction SilentlyContinue
        if (-not $alreadyInstalled) {
            # Remove the partial install, so the next attempt starts clean.
            Remove-Item -LiteralPath $MatlabRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw "mpm failed with exit code $($process.ExitCode). See $MpmLog and $MpmErrorLog."
    }
    if (-not (Test-Path -LiteralPath $matlabExe)) {
        throw "mpm finished but '$matlabExe' is missing"
    }

    # --- 3. Network license -------------------------------------------------------------------
    $licenseDir = Join-Path $MatlabRoot 'licenses'
    New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $licenseDir 'network.lic') -Encoding ASCII -Value @(
        "SERVER $serverHost ANY $port"
        'USE_SERVER'
    )
    Write-Output "License: $licenseDir\network.lic points at $port@$serverHost"

    # --- 4. Start menu shortcut and PATH ------------------------------------------------------
    $startMenu = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'
    $shell = New-Object -ComObject WScript.Shell
    $shortcuts = Get-ChildItem -LiteralPath $startMenu -Filter *.lnk -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $shell.CreateShortcut($_.FullName).TargetPath -like "$MatlabRoot\*" }
    if (-not $shortcuts) {
        $shortcut = $shell.CreateShortcut((Join-Path $startMenu 'MATLAB R2026b.lnk'))
        $shortcut.TargetPath = $matlabExe
        $shortcut.Save()
        Write-Output 'Start menu: added MATLAB R2026b shortcut'
    }

    # Read and write the raw value, so entries like %SystemRoot% stay unexpanded.
    $binDir = Join-Path $MatlabRoot 'bin'
    $envKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment', $true)
    try {
        $path = $envKey.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
        if (($path -split ';' | ForEach-Object { $_.TrimEnd('\') }) -notcontains $binDir) {
            $envKey.SetValue('Path', "$($path.TrimEnd(';'));$binDir", 'ExpandString')
            Write-Output "PATH: added $binDir"
        }
    } finally {
        $envKey.Close()
    }

    # --- 5. Products for the detection scripts ------------------------------------------------
    # Merge with earlier runs, so installing the Simulink edition after the Toolboxes edition
    # doesn't make the Toolboxes edition look uninstalled.
    $marker = Join-Path $MatlabRoot 'IntuneProducts.txt'
    $recorded = if (Test-Path -LiteralPath $marker) { @(Get-Content -LiteralPath $marker) } else { @() }
    $allProducts = @($recorded + $products | Where-Object { $_ } | Sort-Object -Unique)
    Set-Content -LiteralPath $marker -Encoding ASCII -Value $allProducts
    Write-Output "Recorded products: $($allProducts -join ', ')"

    Write-Output 'Install complete.'
} catch {
    Write-Error $_ -ErrorAction Continue
    $exitCode = 1
} finally {
    Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    Stop-Transcript | Out-Null
}
exit $exitCode
