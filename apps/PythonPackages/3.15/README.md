# Python 3.15 packages 2026.10.30 (Intune Win32 app)

Installs these packages, and everything they need, into the machine-wide Python 3.15
(`C:\Program Files\Python315`), for every user on the device:

| Package | Version | For |
|---|---|---|
| numpy | 2.5.4 | arrays and numerical computing |
| matplotlib | 3.11.2 | plotting |
| pandas | 3.1.0 | tables and data analysis |
| scipy | 1.18.1 | scientific computing |
| sympy | 1.14.0 | symbolic math |
| dataretrieval | 1.4.0 | USGS water data |
| ipykernel | 7.4.0 | running Jupyter notebooks with this Python, including PyCharm's **New Notebook** |

With their dependencies that's 48 packages, about 104 MB. The exact list, with each file's
SHA-256, is [`source/requirements.txt`](source/requirements.txt); the packages it was resolved
from are [`requirements.in`](requirements.in).

Python comes from the separate [Python 3.15](../../Python/3.15/) app, which this one depends on.

The install is offline: every wheel is in the package, pinned by URL and SHA-256 in `app.json`
like any other download, and pip installs only those (`--no-index --require-hashes`). Devices
don't need to reach PyPI, and every device gets the same versions.

Logo ([`logo.png`](logo.png)): the PyPI logo, `https://pypi.org/static/images/logo-small.0e0855d0.svg`, rendered at 256×256, retrieved 2026-10-30. The packages come from PyPI, and it keeps this app's card distinct from Python's.

## Where users get these packages

PyCharm 2026.2 creates a separate virtual environment (venv) for each new project by default,
and a venv doesn't see packages installed in the system Python. Its New Project wizard has an
**Inherit packages from base interpreter** checkbox, but it always starts unticked and isn't
saved (confirmed in the 2026.2.3 build, `VenvViewModel.inheritSitePackages`), so it can't be
turned on for users.

| Where | Has these packages? |
|---|---|
| PyCharm's welcome screen: **New Script**, **New Notebook** (they use the system Python 3.15, see [PyCharm (Python 3.15)](../../PyCharm/2026.2-Python3.15/README.md#how-the-default-interpreter-is-set)) | Yes |
| `python` in a terminal, IDLE | Yes |
| A PyCharm project using the **Python 3.15** interpreter itself | Yes |
| A new PyCharm project with a venv (the default) | Only if **Inherit packages from base interpreter** is ticked when creating it |

Notebooks: PyCharm 2026.2.3 runs notebook code through the interpreter's `ipykernel`
(`IPyKernelSessionFactory`, which installs `ipykernel` only when it's missing), so notebooks on
the system Python work without users installing anything. Users couldn't install it themselves
anyway: standard users can't write to `C:\Program Files\Python315`.

## Build the package

```sh
python3 tools/build.py PythonPackages/3.15
# -> out/PythonPackages/3.15/Install.intunewin
```

GitHub Actions also builds it whenever a push changes this folder or the Python 3.15 app, and
publishes it as the **PythonPackages-2026.10.30_Python-3.15.2** artifact and release. See the
[repo README](../../../README.md).

## Intune app settings

| Setting | Value |
|---|---|
| App type | Windows app (Win32) |
| Package file | `Install.intunewin` |
| Name | Python 3.15 packages 2026.10.30 |
| Publisher | Python package maintainers (open source) |
| Install command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1` |
| Uninstall command | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1` |
| Install behavior | System |
| Device restart behavior | Determine behavior based on return codes |
| Return codes | defaults |
| OS architecture | x64 |
| Minimum OS | Windows 10 21H2 or later |
| Disk space required | 1,000 MB |
| Detection rules | Custom script: [`Detect.ps1`](Detect.ps1), "Run script as 32-bit process" = **No** |
| Dependencies | **Python 3.15.2**, set to **Automatically install** |

Logs, in `C:\ProgramData\Microsoft\IntuneManagementExtension\Logs\`:
`Python-3.15-Packages-Install.log` and `Python-3.15-Packages-Uninstall.log`, with pip's full output.

### Assignments

Assign it **Required** to the same groups as [PyCharm (Python 3.15)](../../PyCharm/2026.2-Python3.15/).
To make sure it always comes with PyCharm, you can also add it to that PyCharm app's
**Dependencies** (**Automatically install** = Yes) next to Python 3.15. Intune allows more than
one dependency. The repo's `dependsOn` only records the one that names the CI artifact, so this
doesn't change anything here.

## What the install does

[`source/Install.ps1`](source/Install.ps1), running as SYSTEM:

1. Checks that `C:\Program Files\Python315\python.exe` exists, and fails if it doesn't (the
   Python dependency is missing).
2. Runs `python -m pip install --isolated --no-index --find-links <package folder>
   --require-hashes --only-binary :all: --requirement requirements.txt`. pip uses only the
   wheels in the package, checks each one's SHA-256, and ignores any pip configuration on the
   device (`--isolated`).
3. Imports all seven packages, and checks each one's exact version is installed. Either failing
   fails the install.

pip installs into `C:\Program Files\Python315\Lib\site-packages`, and command-line tools such as
`jupyter-kernel` into `C:\Program Files\Python315\Scripts`, which is already on PATH.

**Detection** ([`Detect.ps1`](Detect.ps1)) checks for each of the seven packages' version
folders that pip creates in `site-packages`, for example `numpy-2.5.4.dist-info`. A device with
older versions fails detection and gets this install, which upgrades them.

## Updating the packages

Pinned versions only change when this app does. To move to newer versions (once per term is
plenty):

1. Edit [`requirements.in`](requirements.in) if the list of packages changes.
2. Run `python3 tools/pin_wheels.py PythonPackages/3.15` (needs `pip install uv` and internet
   access). It resolves everything for 64-bit Python 3.15 on Windows, picks each wheel, checks
   its hash, and rewrites `source/requirements.txt` and the `downloads` in `app.json`.
3. Copy the versions it prints into `$Expected` in `Detect.ps1`, `source/Install.ps1` and
   `source/Uninstall.ps1`, and update the table at the top of this README.
4. Bump `version` (and the name) in `app.json` to the date, for example `2027.01.15`, and update
   this README's version strings.
5. Push. CI builds it and publishes a new release. In Intune, update this app in place: upload
   the new package and `Detect.ps1`. Devices fail the old detection and upgrade.

A Python patch release (3.15.2 → 3.15.3) installs over the same folder and keeps
`site-packages`, so these packages stay installed and nothing here changes. CI rebuilds this
app anyway, because its artifact name includes the Python version.

## Uninstall

[`source/Uninstall.ps1`](source/Uninstall.ps1) runs `pip uninstall` for every package in
`requirements.txt`, then checks the seven are gone (and fails if not, so detection still sees
them). Python and pip stay. Uninstalling Python 3.15 removes these packages too.

## Troubleshooting

| Symptom | Check |
|---|---|
| Install failed | `Python-3.15-Packages-Install.log`. "Python not found" means the Python 3.15 dependency is missing. Otherwise pip's output shows which package failed. |
| `ModuleNotFoundError` in a PyCharm project | The project uses a venv without inherited packages. Use the **Python 3.15** interpreter, or recreate the venv with **Inherit packages from base interpreter** ticked. |
| A user's `pip install` fails with a permission error | Expected for the system Python. Install into a project venv instead. |
| Is it installed? | `python -m pip list` in a terminal lists the packages and versions. |
