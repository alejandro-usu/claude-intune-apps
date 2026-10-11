# MATLAB R2026b (Intune Win32 app)

Installs MATLAB R2026b for all users in `C:\Program Files\MATLAB\R2026b` and licenses it from
a network license server. One package serves two Intune apps, the two editions below.

The package holds only scripts. During the install, MATLAB Package Manager (`mpm`) downloads the
products from MathWorks, so devices need internet access then. Nothing licensed is in the
package or this repo: the license server is passed in the install command.

| Edition | Products | Detection script |
|---|---|---|
| `Simulink` | MATLAB, Simulink | [`Detect-Simulink.ps1`](Detect-Simulink.ps1) |
| `Toolboxes` | MATLAB, Simulink, Statistics and Machine Learning, Optimization, Signal Processing, Image Processing, Control System, Symbolic Math, Curve Fitting | [`Detect-Toolboxes.ps1`](Detect-Toolboxes.ps1) |

The product lists are in `$Editions` in [`source/Install.ps1`](source/Install.ps1). The
detection scripts check the same lists. To change one, update both files. mpm adds any
products that a listed product requires.

| Component | Source | SHA-256 |
|---|---|---|
| `mpm.exe` | https://www.mathworks.com/mpm/win64/mpm, downloaded during the install | not pinned |
| MATLAB and toolboxes | downloaded by mpm from MathWorks | checked by mpm |

The mpm URL always serves the latest version, and newer releases need a recent mpm, so there
is no fixed hash to pin. Instead, `Install.ps1` stops unless `mpm.exe` has a valid Authenticode
signature from MathWorks.

### Why mpm, not the MathWorks installer

The installer (`matlab_R2026b_Windows.exe`) only runs unattended from products downloaded
beforehand with **I want to download without installing**, and it needs a File Installation
Key. mpm downloads straight from MathWorks without signing in or a key. MathWorks documents
both for noninteractive installs.

The trade-off is that every device downloads its products from MathWorks during the install.
To ship the products inside the package instead, `mpm download --platforms=win64` can fetch
them at build time. That isn't set up here: the package would be several GB.

## Build the package

```sh
python3 tools/build.py MATLAB
# -> out/MATLAB/Install.intunewin
```

GitHub Actions also builds it whenever a push changes this folder, and publishes it as the
**MATLAB-R2026b** artifact. See the [repo README](../../README.md).

## Intune app settings

Add the package to Intune twice, once per edition. Both use the same settings except for the
rows marked **per edition**.

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name (**per edition**) | MATLAB R2026b (MATLAB and Simulink) / MATLAB R2026b (with toolboxes) |
| Publisher | MathWorks |
| Install command (**per edition**) | below |
| Uninstall command | `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Installation time required (mins) | 120 (the products download during the install) |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | Windows 10 22H2 or later |
| Disk space required (**per edition**) | 15,000 MB / 20,000 MB (estimates: the installed products plus mpm's downloads) |
| Detection rules (**per edition**) | Custom script: [`Detect-Simulink.ps1`](Detect-Simulink.ps1) / [`Detect-Toolboxes.ps1`](Detect-Toolboxes.ps1), "Run script as 32-bit process" = **No** |

Install commands. Replace `27000@<license-server>` with the license server's port and host
name, as in the `SERVER` line of your network license file:

```
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Edition Simulink -LicenseServer 27000@<license-server>
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Edition Toolboxes -LicenseServer 27000@<license-server>
```

Logs, in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`:
- `MATLAB-R2026b-Install.log` and `MATLAB-R2026b-Uninstall.log` from the scripts
- `MATLAB-R2026b-mpm.log` and `MATLAB-R2026b-mpm.err.log` from mpm (latest run only)

### Assigning the editions

Assign one edition to each device. Both install into the same folder, so:
- A device that gets both ends up with the Toolboxes edition. The second install adds only
  what's missing.
- To move devices from the Simulink edition to the Toolboxes edition, make the Toolboxes app
  supersede the Simulink app, with **Uninstall previous version** set to **No**.
- Uninstalling either edition removes MATLAB R2026b completely.

## What the install does

[`source/Install.ps1`](source/Install.ps1), running as SYSTEM:

1. **mpm**: downloads `mpm.exe` into a temporary folder and checks MathWorks' signature on it.
2. **Products**: `mpm install --release=R2026b --destination="C:\Program Files\MATLAB\R2026b" --products <edition's products>`.
   This installs the latest R2026b update. To install the same update on every device, set
   `$MpmRelease` to an update level such as `R2026bU1`. If a first install fails, the script
   removes the partial folder so the next attempt starts clean.
3. **License**: writes `licenses\network.lic`:
   ```
   SERVER <host> ANY <port>
   USE_SERVER
   ```
   MATLAB checks out a license from that server each time it starts, so devices need to reach
   it (on campus, or over VPN). There's no activation step and no sign-in.
4. **Start menu and PATH**: adds a **MATLAB R2026b** shortcut to the all-users Start menu,
   unless one already points into the install folder, and adds `C:\Program Files\MATLAB\R2026b\bin`
   to the system PATH if it's not there.
5. **Detection marker**: adds the edition's products to `IntuneProducts.txt` in the install
   folder. The detection scripts read it, so a device only counts as installed after mpm
   finished.

If the script is invoked on a 32-bit PowerShell (which the Intune Management Extension can
do), it relaunches itself as 64-bit so `Program Files` and `HKLM` aren't redirected.

## Changing the license server

Detection doesn't check which server `network.lic` names, so changing the install command
doesn't reach devices that already have MATLAB. Replace
`C:\Program Files\MATLAB\R2026b\licenses\network.lic` on them, for example with a
platform script, or uninstall and reinstall.

## Updating to a new release

Each release installs side by side in its own folder (`R2027a`, ...). Change `R2026b` in
`app.json`, both scripts and both detection scripts, build it, and add it to Intune as new apps.
To replace R2026b on devices, set the new apps to supersede the R2026b ones with **Uninstall
previous version** set to **Yes**.

## Uninstall

[`source/Uninstall.ps1`](source/Uninstall.ps1) stops any MATLAB processes running from the
install folder, runs `bin\win64\MathWorksProductUninstaller.exe --mode silent`, then removes
what's left: the folder, Start menu shortcuts into it, and its PATH entry. Other MATLAB releases
and users' own settings in `%APPDATA%\MathWorks` are left alone.
