# Claude Intune Apps

Intune Win32 app packages. Each app is a folder of scripts plus a manifest that pins its installers
by URL and SHA-256. A shared build script downloads the installers, checks their hashes and builds
the `.intunewin`. Installers and packages are never committed.

**Website: https://alejandro-usu.github.io/claude-intune-apps/** lists every app with its
download, install and uninstall commands, and detection rule or script, ready to copy into
Intune. See [Website](#website).

## Apps

| App | Installs |
|---|---|
| [Python/3.14](apps/Python/3.14/) | Python 3.14.7, all users, on PATH, with the `py` launcher |
| [Python/3.15](apps/Python/3.15/) | Python 3.15.2, all users, on PATH, with the `py` launcher |
| [PythonPackages/3.15](apps/PythonPackages/3.15/) | numpy, matplotlib, pandas, scipy, sympy, dataretrieval and ipykernel, pinned and installed offline into Python 3.15. Depends on Python/3.15. |
| [PyCharm/2026.2-Python3.14](apps/PyCharm/2026.2-Python3.14/) | PyCharm 2026.2.3, with Python 3.14 as the default interpreter and first-run prompts pre-answered. Depends on Python/3.14. |
| [PyCharm/2026.2-Python3.15](apps/PyCharm/2026.2-Python3.15/) | The same PyCharm 2026.2.3, with Python 3.15 as the default interpreter. Depends on Python/3.15. Assign only one of the two PyCharm apps to a device. |

## Layout

```
apps/
  <Product>/          for example Python, PyCharm
    <Series>/         one folder per version series, for example 3.14, 2026.2
                      (plus a suffix when one version comes in variants, for example
                      2026.2-Python3.14 and 2026.2-Python3.15)
      app.json        name, version, setup file, installer URLs + SHA-256
      README.md       Intune app settings and what the install does
      logo.png        optional: the app's logo, transparent, for the website (see App logos)
      logo-intune.png the same logo on a square colored from it, for Intune (tools/intune_logo.py)
      Detect.ps1      custom detection script, if the app needs one (uploaded to Intune
                      separately, not packaged)
      source/         scripts and config packaged with the installers, if the app needs them
        Install.ps1
        Uninstall.ps1
        ...
  _template/          starting point for a new app (never built)
tools/
  build.py            builds one or all apps
  intunewin.py        creates and verifies .intunewin files on any OS
site/
  build.py            generates the website from apps/ (template.html is its page)
.github/workflows/
  build.yml           checks every app, builds the ones a push changed, publishes releases
                      and the website
```

An app is named by its path under `apps/`, such as `Python/3.14`. That's the name `build.py`
and the CI workflow use.

- **Patch releases** (3.14.7 → 3.14.8, 2026.2.3 → 2026.2.4) update their series folder in place.
- **A new series** (Python 3.15, PyCharm 2026.3) gets a new folder next to the old one, usually
  a copy of it. Delete the old folder once that version is retired in Intune.
- **Variants** of the same version get a suffix on the series folder that says how they
  differ, such as `PyCharm/2026.2-Python3.15` (PyCharm 2026.2, defaulting to Python 3.15).

Build output and the download cache are git-ignored:
- `out/<Product>/<Series>/`: everything to upload to Intune for that app: the
  `<setup file>.intunewin`, `Detect.ps1` (if the app has one) and `Intune settings.txt` (the
  README's settings and detection rule as plain text). For example
  `out/PyCharm/2026.2-Python3.15/Install.intunewin`.
- `.cache/downloads/`

## Adding an app

First decide whether the app needs scripts:

- **No scripts:** the installer's own command line does everything, and Intune can detect it
  with a built-in rule (MSI product code, file version or registry value). Most MSIs and
  well-behaved EXE installers fit here. [Python/3.14](apps/Python/3.14/) is an example: just
  `app.json` and a README.
- **Scripts:** the install needs more than one step, such as extra configuration, firewall
  rules or per-user settings, or detection needs logic. [PyCharm/2026.2-Python3.15](apps/PyCharm/2026.2-Python3.15/) is an example.

Then:

1. Copy `apps/_template` to `apps/<Product>/<Series>`, for example `apps/Zoom/6.5`. The product
   folder has no version in its name; the series folder is the version line you'll update in
   place. For an app without scripts, delete `source/` and `Detect.ps1`.
2. Fill in `app.json`:
   - **`downloads`:** each installer's URL and SHA-256. Take the hash from the vendor's
     published checksum where there is one. Downloaded files land at the top of the package,
     under the URL's file name, or under `file` if you set it.
   - **`version`:** used in the CI artifact name.
   - **`setupFile`:** the file Intune runs. For an app without scripts, that's the installer
     (one of the downloads). With scripts, it's normally `Install.ps1`.
   - **`dependsOn`** (optional): the app this one depends on in Intune, by its name here, for
     example `"Python/3.15"`. Its product and version are added to the CI artifact name.
   - **`release`** (optional): `true` to also publish the package as a public GitHub Release,
     for a permanent download on the website. Only set it when the installer's license allows
     redistributing it. The Python apps have it; PyCharm doesn't, because JetBrains' installer
     isn't ours to redistribute.
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

**Patch release, same series folder:**
1. Change the version, URLs and hashes in `app.json`.
2. Change the version strings in the app's scripts, `Detect.ps1` and README.
3. Push. CI checks and builds it.
4. Update the existing Intune app in place, as above.

**New series:**
1. Copy the current series folder, for example `apps/Python/3.14` to `apps/Python/3.15`.
2. Update the copy as for a patch release, plus anything tied to the series, such as install
   folders and registry keys.
3. Add it to Intune as a new app.
4. Point dependent apps at it, then supersede the old one (see above and the app's README).

## Building

### Locally

Needs Python 3.9+ and `pip install cryptography`.

```sh
python3 tools/build.py --list              # apps and versions
python3 tools/build.py PyCharm/2026.2-Python3.15
                                           # -> out/PyCharm/2026.2-Python3.15/Install.intunewin
python3 tools/build.py --all
python3 tools/build.py --check             # validate every app.json, no downloads
```

`build.py` takes app names as `--list` shows them (`Python/3.14`), not file system paths.
Downloads are cached in `.cache/downloads/`, so rebuilding doesn't fetch them again. A hash
mismatch stops the build.

`tools/intunewin.py` writes the same format as Microsoft's Win32 Content Prep Tool. To use
Microsoft's tool on Windows instead, put the downloaded installers in a folder with the app's
`source\` files and run `IntuneWinAppUtil.exe -c <folder> -s <setupFile> -o out`.

### With GitHub Actions

On every push that touches `apps/`, `tools/`, `site/` or the workflow, `build.yml`:
1. checks every `app.json` and every `.ps1` for syntax errors
2. builds the apps whose folders changed, plus the apps that depend on them (`dependsOn`), or
   all of them when `tools/` or the workflow changed
3. on `main` only: publishes a release for each built app with `"release": true`, then
   rebuilds the [website](#website)

To build on demand, open **Actions → Build Intune packages → Run workflow** and enter an app
name (`Python/3.14`) or `all`. The button only appears once the workflow is on the default branch.

Each package becomes an artifact named `<Product>-<version>`, followed by
`_<Product>-<version>` of the app it depends on, if any. For example `Python-3.15.2`, or
`PyCharm-2026.2.3-4_Python-3.15.2` for PyCharm with Python 3.15.2 as its default
interpreter. `python3 tools/build.py --list` shows each app's artifact name.
- it's the whole `out/<Product>/<Series>/` folder: the `.intunewin`, `Detect.ps1` (if any) and
  `Intune settings.txt`
- download it from the run page; GitHub delivers it as a .zip, so extract it, then upload the
  `.intunewin` to Intune
- the run summary lists each package's SHA-256
- artifacts are kept for 14 days

Apps with `"release": true` are also published, on `main`, as a GitHub Release with the same
name (for example `Python-3.15.2`), holding the `.intunewin` and `<release name>.zip`, the same
bundle as the artifact. Releases don't expire and anyone can download them. A release that
already exists keeps its files (a missing bundle is added, using the published `.intunewin`),
so publish a changed package under a new version or revision.

## Website

https://alejandro-usu.github.io/claude-intune-apps/ is generated by `site/build.py` on every
run of `build.yml` on `main`. It opens with one card per app, newest first by when their current
version was committed. Clicking a card shows that app's section and clicking it again hides it;
select several to compare them side by side. The selection is kept in the URL
(`…/claude-intune-apps/#python-3-15,python-3-14`), so a comparison can be bookmarked or shared.
The tab icon is the banner's sun (`site/favicon.svg`; `favicon.png` and `apple-touch-icon.png`
are renders of it). For each app it shows:
- the download, one bundle with the `.intunewin`, `Detect.ps1` (if any) and
  `Intune settings.txt`: the release's `.zip` for apps with `"release": true`, otherwise the
  newest CI build from `main` (GitHub sign-in needed; it expires after 14 days, and the site
  then says how to rebuild it)
- the **Intune app settings** table from the app's README; clicking a command selects it for
  Ctrl+C (the page never writes to the clipboard, so ClickFix protections stay quiet)
- the **Detection rule** table from the README, or `Detect.ps1` in full, with download
- the app's `logo.png`, if it has one

Nothing on the site is written separately, so keep those README tables in their current
format: the `## Intune app settings` and `### Detection rule` headings, each followed by a
two-column table.

To preview it locally (downloads show as unavailable without GitHub's data):

```sh
python3 site/build.py      # -> _site/index.html
```

One-time setup: in the repo's **Settings → Pages**, set **Source** to **GitHub Actions**.

## App logos

An app with a logo has two files in its folder, both 256×256 PNGs:

- **`logo.png`**, with a transparent background, for the website (which is dark).
- **`logo-intune.png`**, the same logo on a full-bleed square colored from the logo itself, for
  the Intune app's **Logo** (**App information → Select image**). Company Portal draws a light
  gray tile behind every app icon, and transparent pixels let it show through, so a transparent
  logo sits in a gray square; a fully colored square covers it. `tools/intune_logo.py` makes it
  from `logo.png`: the background is a deep radial gradient of the darkest of the logo's main
  saturated colors (Python's blue becomes navy, PyCharm's green a deep teal), with a soft halo
  behind the logo. It's in each download bundle as `Intune logo.png`, and on the website as
  **Intune logo**.

`tools/build.py --check` fails if an app has one without the other.

### Finding a logo (instructions for an AI agent)

Work through these sources in order and stop at the first that gives the real, current logo.
They're ordered by how reliably they give the vendor's own artwork.

1. **The app's own files.** The icon ships with the app, so it's the exact current logo, and
   using it to label that app is what it's for.
   - Look for image files in what the package installs or downloads. For example, PyCharm's
     build has `bin\pycharm.svg` and `bin\pycharm.ico` (in the `pycharm-<version>.win.zip`
     download, or open the `.exe` installer with 7-Zip).
   - Otherwise take the icon from the main program: `pip install icoextract pillow`, then
     `icoextract <app>.exe app.ico`.
2. **The vendor's brand or press page**, on the vendor's own domain. Search for
   "<vendor> brand assets" or "<product> logo press kit", and download the SVG or the largest
   PNG straight from that site.
3. **Wikimedia Commons** for the official mark only, after reading the file page's license and
   trademark notes. **Simple Icons** (simpleicons.org, CC0) has single-color SVGs if a
   monochrome mark is enough.

Don't use image-search results, logo aggregator sites, favicon scrapers or AI-generated
look-alikes. They're often outdated, low-resolution, altered or unlicensed.

Then make the 256×256 PNG with Pillow. For an SVG, render it first: `pip install cairosvg` and
`cairosvg.svg2png(url="logo.svg", write_to="big.png", output_width=512)`, or, if cairo isn't
installed, load it into Chromium with Playwright as a `data:image/svg+xml;base64,...` image at
256×256 and take an element screenshot with `omit_background=True` (that gives the finished PNG
directly). This repo's logos were made that way.

```python
from PIL import Image

im = Image.open("big.png")              # a PNG, or an .ico from step 1
if im.format == "ICO":
    im.size = max(im.info["sizes"])     # the largest icon in the file
im = im.convert("RGBA")
im.thumbnail((256, 256), Image.LANCZOS)
logo = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
logo.paste(im, ((256 - im.width) // 2, (256 - im.height) // 2), im)
logo.save("apps/<Product>/<Series>/logo.png")
```

Then make the Intune version from it (needs Pillow):

```sh
python3 tools/intune_logo.py apps/<Product>/<Series>/logo.png    # -> logo-intune.png
```

Before committing, open both PNGs and look at them:
- it's this product's current logo (for example PyCharm's, not PyCharm Community Edition's or
  an older design)
- it's sharp at 256×256, with a transparent background
- it reads on both the website's dark background and Company Portal's light one

Logos are the vendors' trademarks. Resize them, but don't recolor or edit them. Add a line to
the app's README saying where the logo came from, for example
`Logo: bin\pycharm.svg from pycharm-2026.2.3.win.zip, retrieved 2026-10-30.`
