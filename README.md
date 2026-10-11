# Claude Intune Apps

Intune Win32 app packages. Each app is a folder of scripts plus a manifest that pins its installers
by URL and SHA-256. A shared build script downloads the installers, checks their hashes and builds
the `.intunewin`. Installers and packages are never committed.

## Apps

| Folder | Installs |
|---|---|
| [Python-3.14](apps/Python-3.14/) | Python 3.14.7, all users, on PATH, with the `py` launcher |
| [PyCharm](apps/PyCharm/) | PyCharm 2026.2.3, with Python 3.14 as the default interpreter and first-run prompts pre-answered. Depends on Python-3.14. |
| [MATLAB](apps/MATLAB/) | MATLAB R2026b, licensed from a network license server. One package for two Intune apps: MATLAB + Simulink, or MATLAB + Simulink + common toolboxes. The package has no installers; mpm downloads the products from MathWorks during the install. |

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

To update an app, change the version and hashes in `app.json` and the version strings in its
scripts, then push.

## Building

### Locally

Needs Python 3.9+ and `pip install cryptography`.

```sh
python3 tools/build.py --list              # apps and versions
python3 tools/build.py PyCharm             # -> out/PyCharm/Install.intunewin
python3 tools/build.py --all
python3 tools/build.py --check             # validate every app.json, no downloads
```

Downloads are cached in `.cache/downloads/`, so rebuilding doesn't fetch them again. A hash
mismatch stops the build.

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
