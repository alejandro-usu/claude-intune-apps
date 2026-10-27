# <APP NAME> <VERSION> (Intune Win32 app)

One or two sentences on what this installs and anything it configures.

<!-- For an app without scripts: set the install and uninstall commands to the installer's own
command line, use a built-in detection rule instead of Detect.ps1, and delete source/ and
Detect.ps1. See apps/Python/3.14/README.md.
Copy this folder to apps/<Product>/<Series>/; the relative links below assume that depth.
Read "Intune conventions" in the repo README before filling this in. -->

| Component | Source | SHA-256 |
|---|---|---|
| `example-<VERSION>-x64.msi` | https://vendor.example.com/downloads/example-<VERSION>-x64.msi | `<sha256>` |

Say where the hash was checked (the vendor's published checksum, a signed release page, etc.).

## Build

```sh
python3 tools/build.py <Product>/<Series>
# -> out/<Product>/<Series>/Install.intunewin
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
| Dependencies | None, or the app and **Automatically install** = Yes |
| Supersedence | None, or the app it replaces and **Uninstall previous version** = Yes / No |

Both commands use plain `powershell.exe`, because Intune doesn't expand environment variables
in the uninstall command. Intune starts it as 32-bit PowerShell, and the scripts relaunch
themselves as 64-bit. See [Intune conventions](../../../README.md#intune-conventions).

Logs: `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<APP-FOLDER>-*.log`

## What the install does

1. ...

## Uninstall

... (What it removes and what it leaves. The script must confirm the app is gone before
removing anything `Detect.ps1` checks.)

## Pilot test

Tested on <device>, <date>:
- [ ] Install from Intune succeeds, and the transcript's `Host Application` is the `Sysnative` PowerShell
- [ ] Detection reports installed afterwards
- [ ] A test user signs in and sees what they should (no prompts, settings applied)
- [ ] Uninstall from Intune succeeds, and detection reports not installed
- [ ] Reinstall works
