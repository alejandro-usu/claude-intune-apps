# <APP NAME> <VERSION> (Intune Win32 app)

One or two sentences on what this installs and anything it configures.

<!-- For an app without scripts: set the install and uninstall commands to the installer's own
command line, use a built-in detection rule instead of Detect.ps1, and delete source/ and
Detect.ps1. See apps/Python-3.14/README.md. -->

| Component | Source | SHA-256 |
|---|---|---|
| `example-<VERSION>-x64.msi` | https://vendor.example.com/downloads/example-<VERSION>-x64.msi | `<sha256>` |

Say where the hash was checked (the vendor's published checksum, a signed release page, etc.).

## Build

```sh
python3 tools/build.py <APP-FOLDER>
# -> out/<APP-FOLDER>/Install.intunewin
```

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name | <APP NAME> <VERSION> |
| Publisher | <Vendor> |
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | |
| Disk space required | |
| Detection rules | Custom script: [`Detect.ps1`](Detect.ps1), "Run script as 32-bit process" = **No** |

Intune doesn't expand environment variables such as `%SystemRoot%` in the uninstall command,
so both commands use plain `powershell.exe`. Intune starts that as 32-bit PowerShell; the
scripts relaunch themselves as 64-bit.

Logs: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<APP-FOLDER>-*.log`

## What the install does

1. ...

## Uninstall

...
