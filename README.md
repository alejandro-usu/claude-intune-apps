# Claude Intune Apps

Intune Win32 app packages. Each app is a folder of scripts plus a manifest that pins its installers
by URL and SHA-256. A shared build script downloads the installers, checks their hashes and builds
the `.intunewin`. Installers and packages are never committed.

## Apps

| Folder | Installs |
|---|---|
| [Python-3.14](apps/Python-3.14/) | Python 3.14.7, all users, on PATH, with the `py` launcher |
| [PyCharm](apps/PyCharm/) | PyCharm 2026.2.3, with Python 3.14 as the default interpreter and first-run prompts pre-answered. Depends on Python-3.14. |

## Layout

```
apps/
  <App>/
    app.json          name, version, setup file, installer URLs + SHA-256
    README.md         Intune app settings and what the install does
    Detect.ps1        custom detection script, if the app needs one (uploaded to Intune
                      separately, not packaged)
    source/           scripts and config packaged with the installers, if the app needs them
      Install.ps1
      Uninstall.ps1
      ...
  _template/          starting point for a new app (never built)
tools/
  build.py            builds one or all apps
  intunewin.py        creates and verifies .intunewin files on any OS
.github/workflows/
  build.yml           checks every app and builds the ones a push changed
```

Build output and the download cache are git-ignored:
- `out/<App>/<setup file>.intunewin`, for example `out/PyCharm/Install.intunewin`
- `.cache/downloads/`

## Adding an app

First decide whether the app needs scripts:

- **No scripts:** the installer's own command line does everything, and Intune can detect it
  with a built-in rule (MSI product code, file version or registry value). Most MSIs and
  well-behaved EXE installers fit here. [Python-3.14](apps/Python-3.14/) is an example: just
  `app.json` and a README.
- **Scripts:** the install needs more than one step, such as extra configuration, firewall
  rules or per-user settings, or detection needs logic. [PyCharm](apps/PyCharm/) is an example.

Then:

1. Copy `apps/_template` to `apps/<App>`. Use a product name without the version, such as
   `Zoom` or `VSCode`, so version bumps don't rename the folder. For an app without scripts,
   delete `source/` and `Detect.ps1`.
2. Fill in `app.json`:
   - **`downloads`:** each installer's URL and SHA-256. Take the hash from the vendor's
     published checksum where there is one. Downloaded files land at the top of the package,
     under the URL's file name, or under `file` if you set it.
   - **`version`:** used in the CI artifact name.
   - **`setupFile`:** the file Intune runs. For an app without scripts, that's the installer
     (one of the downloads). With scripts, it's normally `Install.ps1`.
3. With scripts, write `source/Install.ps1`, `source/Uninstall.ps1` and `Detect.ps1`. The
   template already handles the 64-bit relaunch, logging to the Intune logs folder, and exit
   codes. Detection should check for the exact version this package installs.
4. Fill in `README.md` with the Intune settings: the install and uninstall commands, and the
   detection rule.
5. Build it locally (below), or push and let CI build it.

Before assigning a new app widely, test it on one pilot device: install, detection, uninstall,
and anything that should happen for users (sign in as a test user). The conventions below
come from what went wrong, or nearly did, while piloting the apps in this repo.

## Intune conventions

### Install and uninstall commands

- **No environment variables in the uninstall command.** Intune doesn't expand them there
  ([Microsoft docs](https://learn.microsoft.com/en-us/intune/app-management/deployment/add-win32)),
  so `%SystemRoot%`, `%ProgramData%` and the like must not appear. Use literal paths, for example
  `/log "C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\<App>-Uninstall.log"`. Keep
  the install command the same way for consistency.
- **Scripts:** use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` (and
  `.\Uninstall.ps1`). The Intune agent is 32-bit, so this starts 32-bit PowerShell.
  `%SystemRoot%\System32\...\powershell.exe` doesn't help: Windows redirects a 32-bit
  process's `System32` to `SysWOW64`. Instead, the scripts check for this and relaunch
  themselves through `C:\Windows\Sysnative\...\powershell.exe`, the 64-bit PowerShell, so
  Program Files, HKLM and firewall changes land in the right place. Don't put the `Sysnative`
  path in the command itself; it only exists for 32-bit callers and would break if the agent
  ever became 64-bit.
- **To confirm the relaunch,** open the script's transcript in the Intune logs folder. The
  `Host Application` line should show `C:\Windows\Sysnative\WindowsPowerShell\v1.0\powershell.exe`.
- **Installers run directly** (no script) don't involve PowerShell. A 64-bit MSI writes to the
  64-bit registry and Program Files even when a 32-bit process starts it. For an EXE installer,
  confirm where it installed on the pilot device. The Python installer was checked and is fine.
- **Logs** go to `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`, so Intune's
  "Collect diagnostics" picks them up.

### Detection

- **Check for the exact version the package installs,** so devices with an older version count
  as not installed and get the update.
- **Registry rules: always fill in Value name.** Intune doesn't require it, but if it's blank
  the rule compares against the key's empty default value and never matches. The install
  then shows as failed even though it worked.
- **64-bit apps:** set "Associated with a 32-bit app on 64-bit clients" (rules) and "Run script as
  32-bit process" (custom scripts) to **No**. Otherwise Intune looks under `WOW6432Node` and
  the 32-bit Program Files.
- **"Failed" right after a successful install usually means detection.** Check the installer's
  own log for a success exit code, then
  `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\AppWorkload.log` for what the
  detection rule checked. Intune runs detection before every install attempt, so after fixing
  the rule a sync is enough (Company Portal → Settings → Sync, or restart the Microsoft Intune
  Management Extension service). Nothing needs reinstalling.

### Uninstall scripts

- **Verify the app is gone before removing anything detection checks** (firewall rules,
  registry keys, marker files). Otherwise a failed uninstall makes detection report "not
  installed", and Intune records success.
- **NSIS uninstallers** (`Uninstall.exe /S`, used by JetBrains and many others) copy themselves
  to `%TEMP%` and return before the uninstall finishes, with a meaningless exit code. Wait for
  the app's files to disappear instead of trusting the exit code.

### Dependencies

- Set **Automatically install** to **Yes** on the dependency. Intune then installs it before
  the app on every device the app targets. It doesn't need its own assignment just for that.
- **Do give the dependency its own Required assignment when it supersedes something** (for
  example Python 3.14 replacing 3.13). Supersedence acts on assigned apps; an explicit
  assignment removes any doubt and shows its status separately.
- Company Portal doesn't offer **Uninstall** for an app that has, or is, a dependency.

### Supersedence and updates

- **Never supersede an app that another app depends on.** Microsoft documents this as a
  conflict ("A depends on B, C supersedes B. A will report a conflict state",
  [supersedence docs](https://learn.microsoft.com/en-us/intune/app-management/deployment/configure-win32-supersedence)).
  Update that app in place instead: edit it, upload the new `.intunewin`, and change the
  commands and detection rule. Devices fail the new detection rule and get the update.
- **Replacing a different product, or a version that installs side by side** (Python 3.13 →
  3.14, PyCharm Community Edition → PyCharm): supersede with **Uninstall previous version =
  Yes**. Intune runs the old app's uninstall command first, so check that command works,
  including its folder path. Then remove the old app's Required assignments, or Intune
  reinstalls it.
- **A new version that installs over the old one:** **Uninstall previous version = No**.
- **Package-only changes** (a fixed script, same product version): bump the revision in
  `app.json` (`2026.2.3` → `2026.2.3-2`) so the CI artifact is distinguishable. Upload it to the
  existing Intune app. Change detection only if devices must reinstall.
- **Shared devices** (labs, testing centers): Intune installs and uninstalls in the background
  whenever a device checks in, including during sessions. Roll out to a few devices first, or
  outside opening hours.

### Updating an app in this repo

1. Change the version, URLs and hashes in `app.json`.
2. Change the version strings in the app's scripts, `Detect.ps1` and README.
3. Push. CI checks and builds it.
4. Update the Intune app as above.

## Building

### Locally

Needs Python 3.9+ and `pip install cryptography`.

```sh
python3 tools/build.py --list              # apps and versions
python3 tools/build.py PyCharm             # -> out/PyCharm/Install.intunewin
python3 tools/build.py --all
python3 tools/build.py --check             # validate every app.json, no downloads
```

`build.py` takes app folder names only (as listed by `--list`), not paths. Downloads are cached in
`.cache/downloads/`, so rebuilding doesn't fetch them again. A hash mismatch stops the build.

`tools/intunewin.py` writes the same format as Microsoft's Win32 Content Prep Tool. To use
Microsoft's tool on Windows instead, put the downloaded installers in a folder with the app's
`source\` files and run `IntuneWinAppUtil.exe -c <folder> -s <setupFile> -o out`.

### With GitHub Actions

On every push that touches `apps/`, `tools/` or the workflow, `build.yml`:
1. checks every `app.json` and every `.ps1` for syntax errors
2. builds the apps whose folders changed, or all of them when `tools/` or the workflow changed

To build on demand, open **Actions → Build Intune packages → Run workflow** and enter an app
folder name or `all`. The button only appears once the workflow is on the default branch.

Each package becomes an artifact named `<App>-<version>`:
- download it from the run page
- GitHub wraps it in a .zip, so extract it before uploading to Intune
- the run summary lists each package's SHA-256
- artifacts are kept for 14 days
