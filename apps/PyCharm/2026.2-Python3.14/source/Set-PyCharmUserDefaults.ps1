<#
.SYNOPSIS
    Sets PyCharm 2026.2 defaults for one user profile: accepts the JetBrains User Agreement,
    declines anonymous usage statistics, and makes Python 3.14 the default interpreter.

.DESCRIPTION
    First-run prompts. Both answers are what PyCharm itself saves when the user clicks through:

      User Agreement  HKCU\Software\JavaSoft\Prefs\jetbrains\privacy_policy
                      value eua_accepted_version = 2.0 (PyCharm 2026.2 ships version 2.0 of the
                      "eua" document; a newer agreement in a later build prompts again)
      Data Sharing    %APPDATA%\JetBrains\consentOptions\accepted
                      rsch.send.usage.stat:1.1:0:<time> (0 = Don't Send). Shared by all JetBrains
                      IDEs, so an answer the user already gave is left alone.

    Default interpreter. PyCharm keeps interpreter settings per user, in
    %APPDATA%\JetBrains\PyCharm2026.2\options:

      jdk.table.xml        the list of interpreters (SDKs) PyCharm knows about
      project.default.xml  settings for new projects, including their interpreter
      pySdk.xml            the base interpreter the New Project wizard uses for a new venv

    This script adds (or reuses) a "Python SDK" entry for the given python.exe and points
    the other two files at it. Existing content in all three files is kept.

    If PyCharm 2026.2 has never been started for this user, its first launch would normally
    import settings from an older PyCharm version. PyCharm skips any file that already exists
    in the new config folder during that import, so this script starts from the older version's
    copy of each file instead. That keeps the user's older interpreters and new-project
    defaults as well as adding Python 3.14. The files PyCharm uses to tell whether a config
    folder is already set up (options\other.xml, ide.general.xml, options.xml) are never
    created here, so the import still runs for everything else.

    The same script runs in two ways:
      - as SYSTEM from Install.ps1, once for each existing profile (-ConfigRoot given, and
        -RegistryRoot when that user's registry hive is loaded because they are signed in)
      - as the user from Active Setup at each user's next logon (no parameters)

    It is safe to run more than once.

.PARAMETER ConfigRoot
    The user's roaming AppData folder. Defaults to $env:APPDATA.

.PARAMETER RegistryRoot
    The user's HKEY_CURRENT_USER, as a PowerShell registry path. Defaults to HKCU:. Pass an
    empty string to skip the User Agreement setting (its registry hive isn't available).
#>
[CmdletBinding()]
param(
    [string]$ConfigRoot = $env:APPDATA,
    [string]$RegistryRoot = 'HKCU:',
    [string]$PythonExe = "$env:ProgramFiles\Python314\python.exe",
    [string]$PythonVersion = '3.14.7',
    [string]$SdkName = 'Python 3.14',
    [string]$ConfigDirName = 'PyCharm2026.2',
    [string]$AgreementVersion = '2.0',
    [ValidateSet('Decline', 'Allow')]
    [string]$UsageStatistics = 'Decline'
)

$ErrorActionPreference = 'Stop'

$SdkType = 'Python SDK'
# Files whose presence tells PyCharm the config folder is already set up (InitialConfigImportState.OPTIONS).
$ConfigMarkers = @('options\other.xml', 'options\ide.general.xml', 'options\options.xml')

function Get-NormalizedPath([string]$Path) {
    if (-not $Path) { return '' }
    return $Path.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
}

function ConvertTo-FileUrl([string]$Path) {
    return 'file://' + $Path.Replace('\', '/')
}

function Read-XmlOrNew([string]$Path) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.PreserveWhitespace = $false
    if (Test-Path -LiteralPath $Path) {
        try {
            $doc.Load($Path)
            return $doc
        } catch {
            Write-Warning "Could not parse '$Path', replacing it: $($_.Exception.Message)"
            Copy-Item -LiteralPath $Path -Destination "$Path.bak" -Force
            $doc = New-Object System.Xml.XmlDocument
        }
    }
    [void]$doc.AppendChild($doc.CreateElement('application'))
    return $doc
}

function Save-Xml([System.Xml.XmlDocument]$Doc, [string]$Path) {
    $settings = New-Object System.Xml.XmlWriterSettings
    $settings.Indent = $true
    $settings.IndentChars = '  '
    $settings.OmitXmlDeclaration = $true
    $settings.Encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = [System.Xml.XmlWriter]::Create($Path, $settings)
    try { $Doc.Save($writer) } finally { $writer.Close() }
}

function Get-Component([System.Xml.XmlDocument]$Doc, [string]$Name) {
    $component = $Doc.DocumentElement.SelectSingleNode("component[@name='$Name']")
    if (-not $component) {
        $component = $Doc.CreateElement('component')
        $component.SetAttribute('name', $Name)
        [void]$Doc.DocumentElement.AppendChild($component)
    }
    return $component
}

function Add-Element([System.Xml.XmlNode]$Parent, [string]$Name, [hashtable]$Attributes = @{}) {
    $element = $Parent.OwnerDocument.CreateElement($Name)
    foreach ($key in $Attributes.Keys) { $element.SetAttribute($key, $Attributes[$key]) }
    [void]$Parent.AppendChild($element)
    return $element
}

function Find-PreviousOptionsFile([string]$JetBrainsDir, [string]$FileName) {
    # Newest older PyCharm / PyCharm CE config folder that has this file.
    $candidates = @()
    foreach ($dir in Get-ChildItem -LiteralPath $JetBrainsDir -Directory -ErrorAction SilentlyContinue) {
        if ($dir.Name -ne $ConfigDirName -and $dir.Name -match '^PyCharm(CE)?(\d{4})\.(\d+)$') {
            $candidates += [pscustomobject]@{
                Dir     = $dir.FullName
                Version = [version]"$($Matches[2]).$($Matches[3])"
            }
        }
    }
    foreach ($candidate in ($candidates | Sort-Object Version -Descending)) {
        $file = Join-Path $candidate.Dir "options\$FileName"
        if (Test-Path -LiteralPath $file) { return $file }
    }
    return $null
}

if (-not $ConfigRoot) { throw 'No ConfigRoot given and APPDATA is not set.' }
$jetBrainsDir = Join-Path $ConfigRoot 'JetBrains'

# --- JetBrains User Agreement ------------------------------------------------------------------
# PyCharm reads this through java.util.prefs, which keeps a user's preferences under
# HKCU\Software\JavaSoft\Prefs. Node and value names are all lowercase, so Java stores them as-is.
if ($RegistryRoot) {
    $prefsKey = Join-Path $RegistryRoot 'Software\JavaSoft\Prefs\jetbrains\privacy_policy'
    # Only create the key when missing: New-Item -Force on an existing registry key recreates it,
    # which would delete what other JetBrains IDEs have stored there.
    if (-not (Test-Path -LiteralPath $prefsKey)) { New-Item -Path $prefsKey -Force | Out-Null }
    Set-ItemProperty -Path $prefsKey -Name 'eua_accepted_version' -Value $AgreementVersion
    Write-Verbose "User Agreement $AgreementVersion marked as accepted in $prefsKey"
}

# --- Data Sharing (anonymous usage statistics) -------------------------------------------------
$consentFile = Join-Path $jetBrainsDir 'consentOptions\accepted'
$usageConsentId = 'rsch.send.usage.stat'
$consents = @()
if (Test-Path -LiteralPath $consentFile) {
    $consents = @((Get-Content -LiteralPath $consentFile -Raw) -split ';' | Where-Object { $_.Trim() })
}
if (-not ($consents | Where-Object { $_.StartsWith("${usageConsentId}:") })) {
    $accepted = if ($UsageStatistics -eq 'Allow') { '1' } else { '0' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $consents += "${usageConsentId}:1.1:${accepted}:$now"
    New-Item -ItemType Directory -Path (Split-Path -Parent $consentFile) -Force | Out-Null
    [System.IO.File]::WriteAllText($consentFile, ($consents -join ';'), (New-Object System.Text.UTF8Encoding($false)))
    Write-Verbose "Usage statistics set to $UsageStatistics in $consentFile"
}

# --- Default interpreter -----------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $PythonExe)) {
    Write-Warning "Python not found at '$PythonExe'; skipping the default interpreter."
    return
}

$configDir = Join-Path $jetBrainsDir $ConfigDirName
$optionsDir = Join-Path $configDir 'options'
$isFreshConfig = -not ($ConfigMarkers | Where-Object { Test-Path -LiteralPath (Join-Path $configDir $_) })

New-Item -ItemType Directory -Path $optionsDir -Force | Out-Null

foreach ($fileName in 'jdk.table.xml', 'project.default.xml', 'pySdk.xml') {
    $target = Join-Path $optionsDir $fileName
    if ($isFreshConfig -and -not (Test-Path -LiteralPath $target)) {
        $previous = Find-PreviousOptionsFile $jetBrainsDir $fileName
        if ($previous) {
            Write-Verbose "Seeding $fileName from $previous"
            Copy-Item -LiteralPath $previous -Destination $target
        }
    }
}

# --- jdk.table.xml: make sure there is an SDK entry for this python.exe -----------------------
$jdkTablePath = Join-Path $optionsDir 'jdk.table.xml'
$jdkTable = Read-XmlOrNew $jdkTablePath
$sdkTable = Get-Component $jdkTable 'ProjectJdkTable'

$wantedHome = Get-NormalizedPath $PythonExe
$existing = $null
$namesInUse = @{}
foreach ($jdk in $sdkTable.SelectNodes('jdk')) {
    $name = $jdk.SelectSingleNode('name/@value').Value
    $namesInUse[$name] = $true
    $type = $jdk.SelectSingleNode('type/@value').Value
    $homePath = $jdk.SelectSingleNode('homePath/@value').Value
    if ($type -eq $SdkType -and (Get-NormalizedPath $homePath) -eq $wantedHome) { $existing = $jdk }
}

if ($existing) {
    $SdkName = $existing.SelectSingleNode('name/@value').Value
    Write-Verbose "Reusing existing SDK '$SdkName'"
} else {
    $baseName = $SdkName
    $suffix = 1
    while ($namesInUse.ContainsKey($SdkName)) {
        $suffix++
        $SdkName = "$baseName ($suffix)"
    }

    $pythonHome = Split-Path -Parent $PythonExe
    $jdk = Add-Element $sdkTable 'jdk' @{ version = '2' }
    [void](Add-Element $jdk 'name' @{ value = $SdkName })
    [void](Add-Element $jdk 'type' @{ value = $SdkType })
    [void](Add-Element $jdk 'version' @{ value = "Python $PythonVersion" })
    [void](Add-Element $jdk 'homePath' @{ value = $PythonExe })
    $roots = Add-Element $jdk 'roots'
    $classPath = Add-Element (Add-Element $roots 'classPath') 'root' @{ type = 'composite' }
    foreach ($dir in 'DLLs', 'Lib', '', 'Lib\site-packages') {
        $path = if ($dir) { Join-Path $pythonHome $dir } else { $pythonHome }
        [void](Add-Element $classPath 'root' @{ url = (ConvertTo-FileUrl $path); type = 'simple' })
    }
    [void](Add-Element (Add-Element $roots 'sourcePath') 'root' @{ type = 'composite' })
    $additional = Add-Element $jdk 'additional' @{ SDK_UUID = [guid]::NewGuid().ToString() }
    [void](Add-Element $additional 'setting' @{ name = 'FLAVOR_ID'; value = 'WinPythonSdkFlavor' })
    [void](Add-Element $additional 'setting' @{ name = 'FLAVOR_DATA'; value = '{}' })
    Write-Verbose "Added SDK '$SdkName'"
}
Save-Xml $jdkTable $jdkTablePath

# --- project.default.xml: interpreter for new projects -----------------------------------------
$defaultProjectPath = Join-Path $optionsDir 'project.default.xml'
$defaultProject = Read-XmlOrNew $defaultProjectPath
$projectManager = Get-Component $defaultProject 'ProjectManager'
$template = $projectManager.SelectSingleNode('defaultProject')
if (-not $template) { $template = Add-Element $projectManager 'defaultProject' }
$rootManager = $template.SelectSingleNode("component[@name='ProjectRootManager']")
if (-not $rootManager) { $rootManager = Add-Element $template 'component' @{ name = 'ProjectRootManager' } }
$rootManager.SetAttribute('version', '2')
$rootManager.SetAttribute('project-jdk-name', $SdkName)
$rootManager.SetAttribute('project-jdk-type', $SdkType)
Save-Xml $defaultProject $defaultProjectPath

# --- pySdk.xml: base interpreter the New Project wizard picks for a new virtualenv -------------
$pySdkPath = Join-Path $optionsDir 'pySdk.xml'
$pySdk = Read-XmlOrNew $pySdkPath
$pySdkSettings = Get-Component $pySdk 'PySdkSettings'
$option = $pySdkSettings.SelectSingleNode("option[@name='PREFERRED_VIRTUALENV_BASE_SDK']")
if (-not $option) { $option = Add-Element $pySdkSettings 'option' @{ name = 'PREFERRED_VIRTUALENV_BASE_SDK' } }
$option.SetAttribute('value', $PythonExe)
Save-Xml $pySdk $pySdkPath

Write-Output "PyCharm defaults applied; default interpreter '$SdkName' ($PythonExe) in $optionsDir"
