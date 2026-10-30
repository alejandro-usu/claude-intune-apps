#!/usr/bin/env python3
"""Build Intune Win32 packages for the apps in apps/.

Apps live in apps/<Product>/<version series>/, for example apps/Python/3.14, and are named by
that path ("Python/3.14"). Any folder under apps/ that holds an app.json is an app; folders
starting with "_" or "." (such as apps/_template) are skipped.

Each app folder has an app.json manifest:

    {
      "name": "Display name",
      "version": "1.2.3",
      "setupFile": "Install.ps1",          file Intune runs: a script in source/, or one of
                                            the downloads when its command line is enough
      "dependsOn": "Python/3.15",          optional: the app this one depends on in Intune,
                                            named like any other app. Its product and version
                                            are added to the CI artifact name.
      "release": true,                     optional: CI on main also attaches the package to a
                                            public GitHub Release, for permanent downloads. Only
                                            for installers whose license allows redistribution.
      "downloads": [                        installers to fetch into the package
        {"url": "https://...", "sha256": "...", "file": "optional-name.exe"}
      ]
    }

For each app, this script:
  1. downloads every file in "downloads" into .cache/downloads/ (reused on later runs)
     and stops if a SHA-256 doesn't match
  2. stages source/ (optional) plus the downloads in out/<app>/staging/
  3. writes out/<app>/<setupFile stem>.intunewin and verifies it
  4. puts what Intune needs next to it, so out/<app>/ is everything to upload: Detect.ps1 (if
     the app has one), "Intune logo.png" (logo-intune.png, if the app has a logo) and
     "Intune settings.txt" (the README's Intune app settings and detection rule tables, as
     plain text)

Usage:
    python3 tools/build.py Python/3.14         build one app (its path under apps/)
    python3 tools/build.py --all               build every app
    python3 tools/build.py --list              list apps, versions and CI artifact names
    python3 tools/build.py --check             validate every manifest, download nothing
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPS = os.path.join(REPO, "apps")
CACHE = os.path.join(REPO, ".cache", "downloads")
OUT = os.path.join(REPO, "out")
CHUNK = 4 * 1024 * 1024

sys.path.insert(0, os.path.join(REPO, "tools"))


def app_names():
    """Every folder under apps/ with an app.json, as a path relative to apps/ ("Python/3.14")."""
    names = []
    for root, dirs, files in os.walk(APPS):
        dirs[:] = sorted(d for d in dirs if not d.startswith(("_", ".")))
        if "app.json" in files and root != APPS:
            names.append(os.path.relpath(root, APPS).replace(os.sep, "/"))
            dirs[:] = []  # an app's own subfolders (source/) are not apps
    return sorted(names)


def load_manifest(app):
    """Read and validate apps/<app>/app.json. Returns the manifest; exits with a message on error."""
    app_dir = os.path.join(APPS, app)
    path = os.path.join(app_dir, "app.json")
    if not os.path.isfile(path):
        sys.exit(f"{app}: no app.json (known apps: {', '.join(app_names())})")
    with open(path, encoding="utf-8") as f:
        manifest = json.load(f)

    errors = []
    for key in ("name", "version", "setupFile"):
        if not isinstance(manifest.get(key), str) or not manifest[key]:
            errors.append(f'"{key}" must be a non-empty string')
    names = set()
    for i, dl in enumerate(manifest.get("downloads", [])):
        if not str(dl.get("url", "")).startswith("https://"):
            errors.append(f"downloads[{i}].url must be an https URL")
        if not re.fullmatch(r"[0-9a-f]{64}", str(dl.get("sha256", ""))):
            errors.append(f"downloads[{i}].sha256 must be 64 lowercase hex characters")
        name = download_name(dl)
        if name in names or os.path.exists(os.path.join(app_dir, "source", name)):
            errors.append(f"downloads[{i}] file name '{name}' clashes with another file")
        names.add(name)
    if "dependsOn" in manifest:
        dep = manifest["dependsOn"]
        if not isinstance(dep, str) or dep == app or dep not in app_names():
            errors.append(f'"dependsOn" must name another app ({", ".join(app_names())})')
    if "release" in manifest and not isinstance(manifest["release"], bool):
        errors.append('"release" must be true or false')
    if os.path.isfile(os.path.join(app_dir, "logo.png")) != os.path.isfile(os.path.join(app_dir, "logo-intune.png")):
        errors.append("logo.png and logo-intune.png go together (see App logos in the README)")
    setup = manifest.get("setupFile")
    if isinstance(setup, str) and setup not in names and not os.path.isfile(os.path.join(app_dir, "source", setup)):
        errors.append(f'setupFile "{setup}" is neither in source/ nor one of the downloads')
    if "<" in json.dumps(manifest) or "0" * 64 in json.dumps(manifest):
        errors.append("still has template placeholders (<...> or an all-zero sha256)")
    if errors:
        sys.exit(f"{app}/app.json:\n  " + "\n  ".join(errors))
    return manifest


def artifact_name(app, manifest):
    """CI artifact name: <Product>-<version>, plus _<Product>-<version> of the app it depends on,
    for example "PyCharm-2026.2.3-3_Python-3.15.2". Artifact names can't contain "/"."""
    name = f"{app.split('/')[0]}-{manifest['version']}"
    dep = manifest.get("dependsOn")
    if dep:
        name += f"_{dep.split('/')[0]}-{load_manifest(dep)['version']}"
    return name


def section_table(markdown, heading):
    """Rows of the first two-column table after `heading` in a README, as (key, value) markdown."""
    lines = markdown.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if line.strip() == heading)
    except StopIteration:
        return []
    rows, in_table = [], False
    for line in lines[start + 1:]:
        stripped = line.strip()
        if stripped.startswith("|"):
            in_table = True
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            key, value = cells[0], "|".join(cells[1:]).strip()
            if set(key) <= set("-: ") or (not rows and key in ("Setting", "Field")):
                continue  # separator or header row
            rows.append((key, value))
        elif in_table or stripped.startswith("#"):
            break
    return rows


def plain(markdown):
    """Inline markdown as plain text: [text](url) -> text, `code` -> code, **bold** -> bold."""
    text = re.sub(r"\[((?:[^\]`]|`[^`]*`)+)\]\([^)\s]+\)", r"\1", markdown)
    return text.replace("`", "").replace("**", "")


def intune_settings_text(app, manifest):
    """The app README's Intune settings and detection rule, as plain text to ship with the package."""
    with open(os.path.join(APPS, app, "README.md"), encoding="utf-8") as f:
        readme = f.read()
    lines = [f"{manifest['name']}: Intune settings", f"From apps/{app}/README.md, which has the details.", ""]
    for heading, title in (("## Intune app settings", "INTUNE APP SETTINGS"), ("### Detection rule", "DETECTION RULE")):
        rows = section_table(readme, heading)
        if rows:
            lines += [title, ""]
            for key, value in rows:
                lines += [f"{plain(key)}:", f"    {plain(value)}"]
            lines.append("")
    if os.path.isfile(os.path.join(APPS, app, "Detect.ps1")):
        lines += ["DETECTION SCRIPT", "", "Detect.ps1 (in this folder). Upload it as a custom detection script, with",
                  '"Run script as 32-bit process on 64-bit clients" set to No.', ""]
    if os.path.isfile(os.path.join(APPS, app, "logo-intune.png")):
        lines += ["LOGO", "", '"Intune logo.png" (in this folder): App information > Logo > Select image.',
                  "It has a white background on purpose; see App logos in the repo README.", ""]
    return "\r\n".join(lines)


def download_name(dl):
    return dl.get("file") or str(dl.get("url", "")).rsplit("/", 1)[-1]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(CHUNK), b""):
            h.update(block)
    return h.hexdigest()


def fetch(dl):
    """Return the path of the cached, hash-checked download."""
    os.makedirs(CACHE, exist_ok=True)
    # Key the cache by hash, so two apps can use different files with the same name.
    path = os.path.join(CACHE, f"{dl['sha256'][:12]}-{download_name(dl)}")
    if os.path.isfile(path) and sha256(path) == dl["sha256"]:
        print(f"  have {download_name(dl)} (hash OK)")
        return path

    print(f"  downloading {dl['url']}")
    part = path + ".part"
    with urllib.request.urlopen(dl["url"]) as response, open(part, "wb") as f:
        shutil.copyfileobj(response, f, CHUNK)
    actual = sha256(part)
    if actual != dl["sha256"]:
        os.remove(part)
        sys.exit(f"SHA-256 mismatch for {dl['url']}\n  expected {dl['sha256']}\n  got      {actual}")
    os.replace(part, path)
    print(f"  downloaded {download_name(dl)} (hash OK)")
    return path


def link_or_copy(src, dst):
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


def build(app):
    # Imported here, not at the top: intunewin needs the cryptography package, and site/build.py
    # imports this module for app_names() and artifact_name() without it.
    import intunewin

    if app not in app_names():
        sys.exit(f"Unknown app '{app}'. Pass its path under apps/: {', '.join(app_names())}")
    manifest = load_manifest(app)
    print(f"== {app}: {manifest['name']} ({manifest['version']})")
    app_out = os.path.join(OUT, app)
    # Belt and braces: everything this function deletes must be inside out/.
    if os.path.commonpath([os.path.realpath(app_out), os.path.realpath(OUT)]) != os.path.realpath(OUT):
        sys.exit(f"Refusing to build outside {OUT}: {app_out}")
    staging = os.path.join(app_out, "staging")
    shutil.rmtree(app_out, ignore_errors=True)
    source = os.path.join(APPS, app, "source")
    if os.path.isdir(source):
        shutil.copytree(source, staging)
    else:
        os.makedirs(staging)
    for dl in manifest.get("downloads", []):
        link_or_copy(fetch(dl), os.path.join(staging, download_name(dl)))

    package = intunewin.pack(staging, manifest["setupFile"], app_out)
    intunewin.verify(package)
    shutil.rmtree(staging)

    detect = os.path.join(APPS, app, "Detect.ps1")
    if os.path.isfile(detect):
        shutil.copyfile(detect, os.path.join(app_out, "Detect.ps1"))
    intune_logo = os.path.join(APPS, app, "logo-intune.png")
    if os.path.isfile(intune_logo):
        shutil.copyfile(intune_logo, os.path.join(app_out, "Intune logo.png"))
    with open(os.path.join(app_out, "Intune settings.txt"), "w", encoding="utf-8", newline="") as f:
        f.write(intune_settings_text(app, manifest))
    print(f"Wrote {app_out}: {', '.join(sorted(os.listdir(app_out)))}")
    return package


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("apps", nargs="*", help="app folder names under apps/")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--all", action="store_true", help="build every app")
    group.add_argument("--list", action="store_true", help="list apps and versions")
    group.add_argument("--check", action="store_true", help="validate manifests only")
    args = parser.parse_args()

    if args.list or args.check:
        for app in app_names():
            manifest = load_manifest(app)
            print(f"{app}\t{manifest['version']}\t{artifact_name(app, manifest)}\t{manifest['name']}")
        return
    apps = app_names() if args.all else args.apps
    if not apps:
        parser.error("name an app, or pass --all / --list / --check")
    for app in apps:
        build(app)


if __name__ == "__main__":
    main()
