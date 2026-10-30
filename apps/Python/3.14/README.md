# Python 3.14.7 (Intune Win32 app)

Installs 64-bit Python 3.14.7 for all users in `C:\Program Files\Python314`, adds it to the
system PATH, and installs the `py` launcher. Other apps can depend on it, such as
[PyCharm (Python 3.14)](../../PyCharm/2026.2-Python3.14/).

There are no scripts. Intune runs the Python installer directly, since its command-line options
cover everything and its exit codes are the standard ones Intune already understands.

| Component | Source | SHA-256 |
|---|---|---|
| `python-3.14.7-amd64.exe` | https://www.python.org/ftp/python/3.14.7/python-3.14.7-amd64.exe | `9d9eb2709ef81bf5cd30db3c2096bdbc4ea10087c22e62f27d356b36f6ae9649` |

The hash matches the `sha256_sum` python.org publishes for this file.

Logo ([`logo.png`](logo.png)): `PC/icons/logo.svg` from CPython's `v3.14.7` tag, the Python logo that `python.exe`'s icon is made from, rendered at 256×256, retrieved 2026-10-30.

## Build the package

```sh
python3 tools/build.py Python/3.14
# -> out/Python/3.14/python-3.14.7-amd64.intunewin
```

GitHub Actions also builds it whenever a push changes this folder, and publishes it as the
**Python-3.14.7** artifact. See the [repo README](../../../README.md).

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `python-3.14.7-amd64.intunewin` |
| Name | Python 3.14.7 |
| Publisher | Python Software Foundation |
| Install command | `python-3.14.7-amd64.exe /quiet InstallAllUsers=1 TargetDir="C:\Program Files\Python314" PrependPath=1 Include_launcher=1 InstallLauncherAllUsers=1 Include_test=0 /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Install.log"` |
| Uninstall command | `python-3.14.7-amd64.exe /quiet /uninstall /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.14.7-Uninstall.log"` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | Windows 10 21H2 or later |
| Disk space required | 500 MB |
| Detection rules | Registry rule, below |

### Detection rule

| Field | Value |
|---|---|
| Rule type | Registry |
| Key path | `HKEY_LOCAL_MACHINE\SOFTWARE\Python\PythonCore\3.14` |
| Value name | `Version` (Intune doesn't require this field, but leave it blank and the rule checks the key's empty default value, so detection fails even though Python installed) |
| Detection method | String comparison |
| Operator | Equals |
| Value | `3.14.7` |
| Associated with a 32-bit app on 64-bit clients | No |

The installer writes this key for all-users installs (PEP 514). It's in the 64-bit registry,
because the installer's registration component is flagged 64-bit, so the 32-bit setting must
be **No**.

### Assignments

Apps that depend on Python, such as PyCharm, install it automatically on the devices they
target, so Python doesn't strictly need its own assignment. Give it a **Required** assignment
anyway when it supersedes an older Python (below), so supersedence clearly applies and its
status shows on its own.

### What the install options do

| Option | Effect |
|---|---|
| `/quiet` | No UI |
| `InstallAllUsers=1` | Installs for everyone, not just the account running it |
| `TargetDir="C:\Program Files\Python314"` | The folder PyCharm is configured to use. Patch releases install to the same folder. |
| `PrependPath=1` | Adds Python and its `Scripts` folder to the system PATH |
| `Include_launcher=1 InstallLauncherAllUsers=1` | Installs the `py` launcher for all users |
| `Include_test=0` | Leaves out the standard library's test suite |
| `/log "..."` | Writes the installer log where Intune's "Collect diagnostics" picks it up |

pip, file associations and Start menu shortcuts are included by default.

## Updating to a new 3.14 patch release

Patch releases install over this one in the same folder, so apps that point at
`C:\Program Files\Python314\python.exe` keep working.

Update this Intune app in place rather than adding a new app that supersedes it. PyCharm
depends on this app, and Intune reports a conflict when an app's dependency is superseded
by another app ("A depends on B, C supersedes B" in Microsoft's
[supersedence docs](https://learn.microsoft.com/en-us/intune/app-management/deployment/configure-win32-supersedence)).

1. Change the URL, hash, version and `setupFile` in `app.json`, and build it.
2. In Intune, edit the existing Python app:
   - **App information:** upload the new `.intunewin`, and update the version (and the name, if
     it includes the patch version).
   - **Program:** change the installer file name in the install and uninstall commands.
   - **Detection rules:** change the `Version` value to the new version.
3. Devices then fail the new detection rule, and Intune installs the update over the old
   version. Apps that depend on Python keep their dependency.

Moving to a new minor version (3.15) is different, because the install folder changes. That
app is [Python 3.15](../3.15/): add it to Intune as a new app, and follow
[Moving PyCharm to a new Python version](../../PyCharm/2026.2-Python3.14/README.md#moving-pycharm-to-a-new-python-version).
Supersede the old Python app only after nothing depends on it.

## Replacing an older Python

Each minor version installs side by side in its own folder (`Python313`, `Python314`). If an
older Python was deployed through Intune:

1. Check the older app's **Relationship viewer**. If another app depends on it, move that app
   to this one first. Superseding an app that something depends on is a conflict.
2. In this app, go to **Supersedence → Add**, pick the older Python app, and set **Uninstall
   previous version** to **Yes**.
3. Assign this app (**Required**) to the same groups, and remove the older app's assignments,
   or Intune reinstalls it.

Intune then removes the older Python and installs this one, only on devices that had it. The
uninstaller also removes the old version's PATH entries.

Watch out for:
- **Virtual environments:** a venv built on the old Python breaks when it's removed, and has
  to be recreated. On devices with persistent user profiles, do this at a term break. On
  devices without persistent profiles (testing centers, kiosks) there's nothing to lose, so
  any time is fine.
- **Exams:** on shared devices, avoid having the swap run mid-session.
- **Pre-installed packages:** anything installed into the old Python machine-wide goes with it.

Afterwards, on a device: `py --list` should show only 3.14, and `python --version` should
report 3.14.7.

## Troubleshooting

| Symptom | Check |
|---|---|
| Install shows as failed | Open `Python-3.14.7-Install.log`. If it ends with `Exit code: 0x0` and `Apply complete, result: 0x0`, Python installed and the **detection rule** is wrong, most often a blank Value name. Fix the rule and sync; no reinstall needed. |
| Is Python registered? | `reg query "HKLM\SOFTWARE\Python\PythonCore\3.14" /v Version` should print `3.14.7` |
| A component failed | The installer writes one log per component next to the main log (`Python-3.14.7-Install_000_core_AllUsers.log` and so on). Find the one with a non-zero result. |
| `python` runs the wrong version | An older Python earlier in PATH. Remove the older version (above) or fix PATH. `py --list` shows what's installed. |

## Future: Python 3.16 and the install manager

Checked September 2026 against [PEP 773](https://peps.python.org/pep-0773/) and the
[Python 3.14 Windows docs](https://docs.python.org/3.14/using/windows.html):

- The installer this app uses is deprecated since 3.14 and "will not be produced for Python
  3.16 or later". Python 3.15 still ships it (3.15.0rc2 has `python-3.15.0rc2-amd64.exe`).
- Its replacement, the Python install manager (`py install`), "does not support installing
  runtimes per-machine". It installs Python separately for each signed-in user. The docs
  suggest emulating a per-machine install by running `py install --target=<shared location>`
  as an administrator and adding PATH, registry and Start menu entries yourself.
- The `py` launcher this app installs (`Include_launcher=1`) is deprecated too; the install
  manager replaces it.

So this app can stay as it is through Python 3.15. For 3.16, it will likely become a scripted
app: install the install manager, run `py install --target="C:\Program Files\Python316"` as
SYSTEM, and add PATH and detection by hand. Keeping a fixed path means PyCharm's
default-interpreter setup keeps working. Check the docs again before then, since
machine-wide support may improve. The [Python 3.15](../3.15/) README has the latest notes.

## Uninstall

The uninstall command runs the same installer with `/uninstall`. Packages installed with pip
into `C:\Program Files\Python314` go with it. Apps that depend on Python stay installed.
