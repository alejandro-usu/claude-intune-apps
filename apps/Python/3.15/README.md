# Python 3.15.2 (Intune Win32 app)

Installs 64-bit Python 3.15.2 for all users in `C:\Program Files\Python315`, adds it to the
system PATH, and installs the `py` launcher. Other apps can depend on it, such as
[PyCharm (Python 3.15)](../../PyCharm/2026.2-Python3.15/).

There are no scripts. Intune runs the Python installer directly, since its command-line options
cover everything and its exit codes are the standard ones Intune already understands.

| Component | Source | SHA-256 |
|---|---|---|
| `python-3.15.2-amd64.exe` | https://www.python.org/ftp/python/3.15.2/python-3.15.2-amd64.exe | `06e225a228191b0f4d1dcf6905fbb21bf9f6970d13a2ec63137ab9bee76f15aa` |

The hash matches the `sha256_sum` python.org publishes for this file.

Logo ([`logo.png`](logo.png)): `PC/icons/logo.svg` from CPython's `v3.15.2` tag, the Python logo that `python.exe`'s icon is made from, rendered at 256×256, retrieved 2026-10-30.

## Build the package

```sh
python3 tools/build.py Python/3.15
# -> out/Python/3.15/python-3.15.2-amd64.intunewin
```

GitHub Actions also builds it whenever a push changes this folder, and publishes it as the
**Python-3.15.2** artifact. See the [repo README](../../../README.md).

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `python-3.15.2-amd64.intunewin` |
| Name | Python 3.15.2 |
| Publisher | Python Software Foundation |
| Install command | `python-3.15.2-amd64.exe /quiet InstallAllUsers=1 TargetDir="C:\Program Files\Python315" PrependPath=1 Include_launcher=1 InstallLauncherAllUsers=1 Include_test=0 /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.15.2-Install.log"` |
| Uninstall command | `python-3.15.2-amd64.exe /quiet /uninstall /log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\Python-3.15.2-Uninstall.log"` |
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
| Key path | `HKEY_LOCAL_MACHINE\SOFTWARE\Python\PythonCore\3.15` |
| Value name | `Version` (Intune doesn't require this field, but leave it blank and the rule checks the key's empty default value, so detection fails even though Python installed) |
| Detection method | String comparison |
| Operator | Equals |
| Value | `3.15.2` |
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
| `TargetDir="C:\Program Files\Python315"` | The folder [PyCharm (Python 3.15)](../../PyCharm/2026.2-Python3.15/) is configured to use. Patch releases install to the same folder. |
| `PrependPath=1` | Adds Python and its `Scripts` folder to the system PATH |
| `Include_launcher=1 InstallLauncherAllUsers=1` | Installs the legacy `py` launcher for all users (see below; this is **not** the Python install manager) |
| `Include_test=0` | Leaves out the standard library's test suite |
| `/log "..."` | Writes the installer log where Intune's "Collect diagnostics" picks it up |

pip, file associations and Start menu shortcuts are included by default.

### `Include_launcher` installs the legacy `py` launcher

The [Python 3.15 Windows docs](https://docs.python.org/3.15/using/windows.html#installing-without-ui)
describe `Include_launcher` as "Install Python install manager". That wording comes from a
cross-reference, not from a change to the installer. The docs source says
``Install :ref:`launcher`.``, and since 3.14 the `launcher` label sits on the "Python install
manager" heading, so Sphinx prints that heading's title. The 3.14 docs say the same thing.

What the 3.15.2 installer actually does (checked in the `v3.15.2` tag's
`Tools/msi/bundle/packagegroups/launcher.wxs`, and in the bundle manifest inside
`python-3.15.2-amd64.exe` itself):

- `Include_launcher=1 InstallLauncherAllUsers=1` installs the embedded `launcher.msi`, shown in
  Programs and Features as **Python Launcher** (version 3.15.2150.0). That is the legacy
  `py.exe`, installed to `C:\Windows`, the same launcher the 3.14 app installs. It is not
  pymanager and doesn't download anything.
- The launcher is a separate, **permanent** package: Python's own uninstall leaves it in place,
  which is what the docs mean by "with the exception of the Python install manager, which has
  its own entry in Programs and Features". This was already true for 3.14.
- If a device already has the 3.14 app's launcher (3.14.7150.0), this one upgrades it. If it has
  a newer launcher, the installer skips the launcher and logs "Higher version launcher has been
  detected", but Python itself still installs.
- If the Python install manager is also installed on a device, the legacy launcher's `py`
  command takes priority over pymanager's (see the docs' troubleshooting section). Remove the
  "Python Launcher" entry on that device if users want pymanager's `py`.

## Updating to a new 3.15 patch release

Patch releases install over this one in the same folder, so apps that point at
`C:\Program Files\Python315\python.exe` keep working.

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

Moving to a new minor version (3.16) is different; see
[Python 3.16 and the install manager](#python-316-and-the-install-manager) below.

## Replacing an older Python

Each minor version installs side by side in its own folder (`Python314`, `Python315`). If an
older Python was deployed through Intune:

1. Check the older app's **Relationship viewer**. If another app depends on it, move that app
   to this one first. For PyCharm, that means switching devices from
   [PyCharm (Python 3.14)](../../PyCharm/2026.2-Python3.14/) to
   [PyCharm (Python 3.15)](../../PyCharm/2026.2-Python3.15/). Superseding an app that something
   depends on is a conflict.
2. In this app, go to **Supersedence → Add**, pick the older Python app, and set **Uninstall
   previous version** to **Yes**.
3. Assign this app (**Required**) to the same groups, and remove the older app's assignments,
   or Intune reinstalls it.

Intune then removes the older Python and installs this one, only on devices that had it. The
uninstaller also removes the old version's PATH entries. The `py` launcher stays, since it's
permanent (above).

Watch out for:
- **Virtual environments:** a venv built on the old Python breaks when it's removed, and has
  to be recreated. On devices with persistent user profiles, do this at a term break. On
  devices without persistent profiles (testing centers, kiosks) there's nothing to lose, so
  any time is fine.
- **Exams:** on shared devices, avoid having the swap run mid-session.
- **Pre-installed packages:** anything installed into the old Python machine-wide goes with it.

Afterwards, on a device: `py --list` should show only 3.15, and `python --version` should
report 3.15.2.

## Troubleshooting

| Symptom | Check |
|---|---|
| Install shows as failed | Open `Python-3.15.2-Install.log`. If it ends with `Exit code: 0x0` and `Apply complete, result: 0x0`, Python installed and the **detection rule** is wrong, most often a blank Value name. Fix the rule and sync; no reinstall needed. |
| Is Python registered? | `reg query "HKLM\SOFTWARE\Python\PythonCore\3.15" /v Version` should print `3.15.2` |
| A component failed | The installer writes one log per component next to the main log (`Python-3.15.2-Install_000_core_AllUsers.log` and so on). Find the one with a non-zero result. |
| `python` runs the wrong version | An older Python earlier in PATH. Remove the older version (above) or fix PATH. `py --list` shows what's installed. |
| `py` behaves like pymanager, or the other way round | Both the legacy launcher and the Python install manager are installed; the legacy one wins. See [`Include_launcher` installs the legacy `py` launcher](#include_launcher-installs-the-legacy-py-launcher). |

## Python 3.16 and the install manager

Checked October 2026 against [PEP 773](https://peps.python.org/pep-0773/) and the
[Python 3.15 Windows docs](https://docs.python.org/3.15/using/windows.html):

- The installer this app uses is deprecated since 3.14 and "will not be produced for Python
  3.16 or later". **3.15 is the last series with it**, so this is the last Python app in this
  repo that can work this way.
- Its replacement, the Python install manager (`py install`), "does not support installing
  runtimes per-machine". It installs Python separately for each signed-in user. The docs
  suggest emulating a per-machine install by running `py install --target=<shared location>`
  as an administrator and adding PATH, registry and Start menu entries yourself.
- The `py` launcher this app installs (`Include_launcher=1`) is deprecated too; the install
  manager replaces it.

For 3.16, the Python app will likely become a scripted app: install the install manager, run
`py install --target="C:\Program Files\Python316"` as SYSTEM, and add PATH and detection by
hand. Keeping a fixed path means PyCharm's default-interpreter setup keeps working. Check the
docs again before then, since machine-wide support may improve.

## Uninstall

The uninstall command runs the same installer with `/uninstall`. Packages installed with pip
into `C:\Program Files\Python315` go with it, including the
[Python 3.15 packages](../../PythonPackages/3.15/) app's. The `py` launcher stays (it's
permanent), and apps that depend on Python stay installed.
