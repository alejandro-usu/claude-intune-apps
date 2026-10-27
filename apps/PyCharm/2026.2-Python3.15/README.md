# PyCharm 2026.2.3, default Python 3.15 (Intune Win32 app)

Installs PyCharm 2026.2.3 for all users and makes Python 3.15 the default interpreter in
PyCharm for every user on the device. Users don't see PyCharm's first-run User Agreement or
Data Sharing dialogs, or the Windows Firewall prompt.

Python comes from the separate [Python 3.15](../../Python/3.15/) app. Set it up as a dependency
(below), so Intune installs Python first.

This is one of two variants of the same PyCharm. The other,
[PyCharm (Python 3.14)](../2026.2-Python3.14/), defaults to Python 3.14 instead. Only one of
them can be on a device; see
[Moving devices from PyCharm (Python 3.14) to this app](#moving-devices-from-pycharm-python-314-to-this-app).

| Component | Source | SHA-256 |
|---|---|---|
| `pycharm-2026.2.3.exe` (build 262.10968.92) | https://download.jetbrains.com/python/pycharm-2026.2.3.exe | `f47b0e48ce06a903b94245bbe8a312f2196205a12264ee47b0cf1595a1443362` |

The hash matches JetBrains' published `pycharm-2026.2.3.exe.sha256`.

## Build the package

```sh
python3 tools/build.py PyCharm/2026.2-Python3.15
# -> out/PyCharm/2026.2-Python3.15/Install.intunewin
```

GitHub Actions also builds it whenever a push changes this folder, and publishes it as the
**PyCharm-2026.2.3-3_Python-3.15.2** artifact. `-3` is the package revision, and `Python-3.15.2` is
the version of the Python app it depends on (`dependsOn` in `app.json`), which is PyCharm's
default interpreter. A push that changes the Python app rebuilds this one too, so the name
stays current. See the [repo README](../../../README.md).

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name | PyCharm 2026.2.3 (Python 3.15) |
| Publisher | JetBrains |
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | Windows 10 21H2 or later (PyCharm 2026.2 requires 64-bit Windows 10+) |
| Disk space required | 4,000 MB |
| Detection rules | Custom script: [`Detect.ps1`](Detect.ps1), "Run script as 32-bit process" = **No** |
| Dependencies | **Python 3.15.2**, set to **Automatically install** |

Both commands use plain `powershell.exe`, because Intune doesn't expand environment variables
in the uninstall command. Intune starts it as 32-bit PowerShell, and the scripts relaunch
themselves as 64-bit. See [Intune conventions](../../../README.md#install-and-uninstall-commands).

Logs, in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`:
- `PyCharm-2026.2.3-Install.log` and `PyCharm-2026.2.3-Uninstall.log` from the scripts
- `PyCharm-2026.2.3-Setup.log` from the PyCharm installer

### Dependency on Python 3.15

1. Add the [Python 3.15](../../Python/3.15/) app to Intune first.
2. In this app, go to **Dependencies → Add** and pick Python 3.15.2.
3. Set **Automatically install** to **Yes**.

Intune then installs Python before PyCharm on every device PyCharm targets. Uninstalling
PyCharm leaves Python installed.

If the Python app also supersedes an older Python (for example 3.13), give it its own
**Required** assignment to the same groups as well. See the
[Python README](../../Python/3.15/README.md#replacing-an-older-python).

If Python is missing when PyCharm installs, the install still succeeds and logs a warning,
but users don't get Python 3.15 as their default interpreter. Active Setup only runs once per
user, so installing Python later doesn't fix that. You'd need to bump `$ActiveSetupVersion`
in `Install.ps1` and redeploy.

A Python patch release (for example 3.15.3) installs to the same `C:\Program Files\Python315`,
so only the Python app needs updating. A new minor version (3.16) changes the path; see
[Moving PyCharm to a new Python version](#moving-pycharm-to-a-new-python-version).

## What the install does

[`source/Install.ps1`](source/Install.ps1), running as SYSTEM:

1. **PyCharm 2026.2.3**: `pycharm-2026.2.3.exe /S /CONFIG=silent.config /D=C:\Program Files\JetBrains\PyCharm 2026.2.3`.
   [`silent.config`](source/silent.config) sets `mode=admin` (all users) and turns off the desktop
   shortcut, PATH change, context menu entry and `.py` association.
2. **Firewall**: adds an inbound rule for `bin\pycharm64.exe` (group `PyCharm 2026.2.3`), so
   Windows doesn't ask users whether to let PyCharm through. The rule **blocks** by default.
   PyCharm's own features (debugger, built-in web server) talk over localhost, which Windows
   Firewall doesn't filter, so they still work. Set `$FirewallAction = 'Allow'` in
   `Install.ps1` if users need to reach PyCharm from another computer.
3. **Per-user defaults, future logons**: copies
   [`Set-PyCharmUserDefaults.ps1`](source/Set-PyCharmUserDefaults.ps1) to
   `C:\Program Files\JetBrains\PyCharm-Python-Defaults\` (only admins can write there) and
   registers it with **Active Setup**, so Windows runs it once for each user at their next logon.
4. **Per-user defaults, now**: runs the same script as SYSTEM against every existing profile
   under `C:\Users`, so users who are already signed in don't need to log off.

Intune starts the script in 32-bit PowerShell. The script relaunches itself as 64-bit first,
so `Program Files` and `HKLM` aren't redirected.

## First-run prompts

`Set-PyCharmUserDefaults.ps1` stores the same answers PyCharm saves when a user clicks through
its first-run dialogs. The locations and formats were confirmed in the 2026.2.3 build
(`EndUserAgreement`, `ConsentOptions`, `com.intellij.ide.Prefs`).

| Prompt | What the script sets |
|---|---|
| JetBrains User Agreement | `HKCU\Software\JavaSoft\Prefs\jetbrains\privacy_policy`, value `eua_accepted_version` = `2.0`. PyCharm 2026.2 ships version 2.0 of the agreement; if a later build ships a newer one, users are asked again until `-AgreementVersion` is updated. |
| Data Sharing | Adds `rsch.send.usage.stat:1.1:0:<time>` ("Don't Send") to `%APPDATA%\JetBrains\consentOptions\accepted`. All JetBrains IDEs share this file, so an answer the user already gave is left alone. Pass `-UsageStatistics Allow` to opt in instead. |

Accepting the User Agreement this way accepts it on each user's behalf. Make sure your
organization is comfortable with that under its JetBrains licensing terms.

The registry part needs the user's registry hive. For users who are signed in during install,
it is loaded under `HKEY_USERS`, and the SYSTEM pass writes there. Everyone else gets it from
Active Setup at their next logon, before they can start PyCharm.

## How the default interpreter is set

PyCharm has no machine-wide interpreter setting. Interpreters live in each user's config
folder, `%APPDATA%\JetBrains\PyCharm2026.2\options\`. `Set-PyCharmUserDefaults.ps1` writes
three files there:

| File | What the script sets |
|---|---|
| `jdk.table.xml` | Adds a `Python SDK` entry named **Python 3.15** for `C:\Program Files\Python315\python.exe` (flavor `WinPythonSdkFlavor`). If an entry for that `python.exe` already exists, it reuses that entry. If another interpreter already uses the name, it picks `Python 3.15 (2)`. |
| `project.default.xml` | Points the default project's `ProjectRootManager` at that SDK, so new projects and projects opened without an interpreter get Python 3.15.2. |
| `pySdk.xml` | Sets `PySdkSettings.PREFERRED_VIRTUALENV_BASE_SDK` to that `python.exe`, so the New Project wizard picks Python 3.15.2 as the base interpreter when it creates a new venv. |

It edits these files in place and keeps the rest of their contents. Running it again changes
nothing.

**Keeping settings from older PyCharm versions.** The first time a user starts PyCharm 2026.2,
it offers to import settings from their previous version (for example `PyCharm2026.1`). Two
details of that import, confirmed in the 2026.2.3 build (`ConfigImportHelper`, `InitialConfigImportState`):

- PyCharm only treats the config folder as already set up, and skips the import, when
  `options\other.xml`, `options\ide.general.xml` or `options\options.xml` exists. The script
  never writes those files, so the import still happens.
- During the import, PyCharm skips any file that already exists in the new folder. On its own,
  that would mean the user's older interpreter list and new-project defaults were not brought
  across. So when the 2026.2 folder hasn't been set up yet, the script starts from the newest
  older `PyCharm*`/`PyCharmCE*` copy of each file and then adds Python 3.15.2. The user keeps
  their old interpreters and also gets the new default.

**Caveats**

- If PyCharm is running while the SYSTEM pass edits a user's files, PyCharm overwrites them
  when it exits. Active Setup runs at logon, before PyCharm can start, so it covers anyone
  this affects at their next logon. To make Active Setup run again for everyone, bump
  `$ActiveSetupVersion` in `Install.ps1`.
- With folder redirection of `AppData\Roaming`, the SYSTEM pass writes to the local profile
  path. Active Setup still writes to the user's real `%APPDATA%` at their next logon.
- Existing projects keep whatever interpreter they already use. The default only applies to
  new projects.

## Python packages for projects

Neither this app nor the Python app installs extra packages (numpy, pandas and so on). Users
install what they need into each project. By default, PyCharm's New Project wizard creates a
virtual environment (`.venv`) for each project, and packages go there, so no admin rights are
needed. Packages in the system Python wouldn't be visible inside these environments anyway.

In PyCharm, open the project, open the **Terminal** tab (it starts with the project's
environment active), and run, for example:

```
python -m pip install numpy matplotlib pandas scipy dataretrieval
```

Other ways to do the same:
- **Python Packages** tool window (**View → Tool Windows → Python Packages**): search for a
  package and click **Install**.
- A `requirements.txt` in the project folder, one package per line. PyCharm offers to install
  everything in it, or run `python -m pip install -r requirements.txt`. Instructors can hand
  out one file so every student gets the same set.
- From a regular Command Prompt in the project folder:
  `.venv\Scripts\python -m pip install <packages>`

Notes:
- The device needs internet access to reach PyPI.
- Running pip against the system Python (`C:\Program Files\Python315`) fails with a permission
  error for standard users. That's expected; install into the project instead.
- Projects created with PyCharm's **uv** option may not include pip. Use
  `uv pip install <packages>` there.

## Moving PyCharm to a new Python version

PyCharm doesn't install or pick Python itself. Three things decide which Python users get:

1. **Intune installs it:** this app's dependency names one Python app.
2. **This package sets the default:** `Set-PyCharmUserDefaults.ps1` registers one fixed
   `python.exe` path in PyCharm and makes it the default for new projects and new venvs.
3. **PyCharm finds the rest:** it lists any other Python it finds on PATH or in the registry,
   so users can still pick those by hand. They just aren't the default.

A Python patch release (3.15.2 → 3.15.3) keeps the same folder, so nothing here changes.

This package was made from [PyCharm (Python 3.14)](../2026.2-Python3.14/) with that README's
checklist. Compared with it, only these change: `$PythonExe`, `$PythonVersion` and `$SdkName`
in `Set-PyCharmUserDefaults.ps1`; `$PythonExe` and `$ActiveSetupVersion` (`2026,2,3,3`) in
`Install.ps1`; the version check in `Detect.ps1`; the revision (`2026.2.3-3`) and `dependsOn`
(`Python/3.15`) in `app.json`; and the Python version in comments and this README. The PyCharm installer, install folder,
firewall rule and Active Setup key are the same.

The Active Setup key name (`...PyCharm2026.2-Python3.14-Interpreter`) still says 3.14 on
purpose. It's only an ID; renaming it would leave the old key behind on devices, and keeping
it is what lets the version bump make Active Setup run again for users who already got the
3.14 default.

For the next minor version, Python 3.16, the Python app itself has to change first, since
python.org no longer ships the installer it uses (see the
[Python 3.15 README](../../Python/3.15/README.md#python-316-and-the-install-manager)). Once
there is a Python 3.16 app that installs to a fixed `C:\Program Files\Python316`, copy this
folder to `apps/PyCharm/<series>-Python3.16` and repeat the same steps.

### Moving devices from PyCharm (Python 3.14) to this app

The two PyCharm apps install the same PyCharm into the same folder and share the firewall
rule and Active Setup key. They differ only in the Active Setup version their detection
expects, so a device can only have one of them. **Never assign both to the same device**:
each would fail detection after the other installed, and Intune would keep reinstalling them
in turn.

**In Intune, in this order:**
1. Add the [Python 3.15](../../Python/3.15/) app.
2. Either update the existing PyCharm app in place: change its dependency from Python 3.14 to
   Python 3.15 (**Automatically install** = Yes), upload this package and `Detect.ps1`, and
   rename it to **PyCharm 2026.2.3 (Python 3.15)**. All its devices move at once.
   Or, to move groups one at a time, add this as a new app with the Python 3.15 dependency,
   assign it to a group, and remove that group from the PyCharm (Python 3.14) app's
   assignments in the same change. It installs over the existing PyCharm, so no uninstall
   is needed. Don't use supersedence with **Uninstall previous version** = Yes for this: it
   would uninstall PyCharm only to install the same files again.
3. Once nothing depends on Python 3.14 any more, set the Python 3.15 app to supersede it
   (**Uninstall previous version** = Yes), if you want 3.14 removed. Doing this while a PyCharm
   (Python 3.14) app still depends on 3.14 is a conflict.

**What users see:**
- PyCharm gains a "Python 3.15" interpreter, which becomes the default for new projects.
- The "Python 3.14" entry stays in their list. After 3.14 is uninstalled, it shows as
  invalid, and users can remove it.
- Existing projects keep their 3.14 virtual environments. Those break when 3.14 is removed
  and have to be recreated.

**Going back to PyCharm (Python 3.14)** on a device that had this app: the SYSTEM pass resets
the default for existing profiles, but Active Setup won't run again at logon, because that
package's `2026,2,3,2` is lower than this one's `2026,2,3,3`. Bump `$ActiveSetupVersion` in that
package's `Install.ps1` and `Detect.ps1` above `2026,2,3,3` first.

## Replacing PyCharm Community Edition

JetBrains merged PyCharm Community and Professional into one PyCharm; without a license it runs
the free features. To replace an Intune-deployed Community Edition:

1. In this app, go to **Supersedence → Add**, pick the Community Edition app, and set
   **Uninstall previous version** to **Yes**. The two install side by side in different
   folders, so the old one must be uninstalled.
2. Check the old app's uninstall command on a device that has it. Community Edition's
   installer defaults to `C:\Program Files\JetBrains\PyCharm Community Edition <version>`, so
   a command pointing at `...\PyCharm <version>\bin\Uninstall.exe` fails.
3. The old app's `Uninstall.exe /S` returns before it finishes (see
   [Uninstall scripts](../../../README.md#uninstall-scripts)). If Intune reports the old app's
   uninstall as failed, give it a wrapper script that waits, like this app's `Uninstall.ps1`.
4. Assign this app where the old one was assigned, then remove the old app's assignments.

On first launch, PyCharm 2026.2 offers to import the user's Community Edition settings. The
per-user script reads `PyCharmCE*` config folders too, so interpreters carry over.

## Uninstall

[`source/Uninstall.ps1`](source/Uninstall.ps1):
1. Stops PyCharm and runs `bin\Uninstall.exe /S`.
2. Waits for `bin\pycharm64.exe` to disappear, since the uninstaller returns early.
3. Deletes what's left of the install folder.
4. Checks that `bin\pycharm64.exe` and `product-info.json` are gone. If either remains, it stops
   and exits 1, leaving the firewall rule and Active Setup entry in place. Detection still sees
   PyCharm, so Intune reports the failure instead of a false success.
5. Removes the firewall rule, the Active Setup entry and the defaults script.

Python 3.15 stays installed, and users' own PyCharm settings in `%APPDATA%` are left alone.

## Troubleshooting

| Symptom | Check |
|---|---|
| Install or uninstall failed | `PyCharm-2026.2.3-Install.log` / `-Uninstall.log` in the Intune logs folder. The `Host Application` line should show `C:\Windows\Sysnative\...\powershell.exe` (the 64-bit relaunch). |
| PyCharm installer itself failed | `PyCharm-2026.2.3-Setup.log` |
| Install log warns "Python not found" | The Python dependency is missing or not set to **Automatically install**. Users won't get the default interpreter; fix the dependency, then bump `$ActiveSetupVersion` and redeploy. |
| User Agreement or Data Sharing dialog appears | Either the per-user script didn't run for this user, or a newer PyCharm build ships a newer agreement version (update `-AgreementVersion`). To rerun the script, sign out and back in. Active Setup runs it once per user per `$ActiveSetupVersion`. |
| Windows Firewall prompt appears | The firewall rule is missing: check the install log, and `Get-NetFirewallRule -Group 'PyCharm 2026.2.3'`. |
| PyCharm reinstalls at every check-in | Both PyCharm apps are assigned to the device. They install the same PyCharm, and each fails detection after the other runs. Remove one assignment. |
