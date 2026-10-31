#!/usr/bin/env python3
"""Refresh package/honk/Makefile from the latest daeuniverse/honk release.

The package intentionally ships a prebuilt aarch64 musl "stock-full" binary.
This helper is meant to run in CI (and locally) before a build so that manual
builds follow the newest honk release, including prereleases/betas.

It rewrites only these Makefile fields:
  PKG_VERSION, PKG_RELEASE, PKG_SOURCE, PKG_SOURCE_URL, PKG_HASH,
  HONK_EXTRACT_DIR

If GitHub is unreachable or the expected asset is missing, it leaves the
committed pinned version untouched and exits 0, so a transient API failure
does not break the build. Use --strict to fail instead.

Usage:
  python3 scripts/hg5585f/update-honk.py            # apply
  python3 scripts/hg5585f/update-honk.py --dry-run  # print only
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tarfile
import tempfile
import urllib.request

API_URL = "https://api.github.com/repos/daeuniverse/honk/releases?per_page=30"
ASSET_SUFFIX = "aarch64-unknown-linux-musl-stock-full.tar.gz"
DEFAULT_MAKEFILE = "package/honk/Makefile"


def http_get(url: str, token: str | None = None, timeout: int = 120) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "hg5585f-build"})
    if token:
        req.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def download(url: str, dest: str, timeout: int = 180) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "hg5585f-build"})
    digest = hashlib.sha256()
    with urllib.request.urlopen(req, timeout=timeout) as resp, open(dest, "wb") as fh:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            fh.write(chunk)
    return digest.hexdigest()


def choose_release(releases: list[dict]) -> tuple[dict, dict] | tuple[None, None]:
    for rel in releases:
        if rel.get("draft"):
            continue
        for asset in rel.get("assets", []):
            name = asset.get("name", "")
            if name.startswith("honk-core-") and name.endswith(ASSET_SUFFIX):
                return rel, asset
    return None, None


def pkg_version(tag: str) -> str:
    version = tag[1:] if tag.startswith("v") else tag
    version = version.replace("-", "_")
    # 0.1.0-beta.4 -> 0.1.0_beta4 (same style as the committed beta3 pin)
    version = re.sub(r"\.(?=\d+$)", "", version)
    return version


def replace_field(text: str, key: str, value: str) -> str:
    pattern = re.compile(r"(?m)^" + re.escape(key) + r":=.*$")
    new_text, count = pattern.subn(lambda _m: f"{key}:={value}", text)
    if count != 1:
        raise RuntimeError(f"expected exactly one {key}:= line, found {count}")
    return new_text


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--makefile", default=DEFAULT_MAKEFILE)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    try:
        releases = json.loads(http_get(API_URL, token))
        if not isinstance(releases, list):
            raise RuntimeError("unexpected GitHub API response")
        release, asset = choose_release(releases)
        if not release or not asset:
            raise RuntimeError("no release with aarch64 musl stock-full asset")

        tag = release["tag_name"]
        asset_name = asset["name"]
        asset_url = asset["browser_download_url"]
        version = pkg_version(tag)
        source_url = f"https://github.com/daeuniverse/honk/releases/download/{tag}"

        with tempfile.TemporaryDirectory(prefix="honk-") as tmpdir:
            archive = os.path.join(tmpdir, asset_name)
            digest = download(asset_url, archive)
            with tarfile.open(archive, "r:gz") as tf:
                names = [m.name for m in tf.getmembers() if m.name and not m.name.startswith("./")]
            if not names:
                raise RuntimeError("asset archive is empty")
            top = names[0].split("/")[0]
            if not all(n == top or n.startswith(top + "/") for n in names):
                raise RuntimeError("asset archive does not have a single top-level directory")

        with open(args.makefile, "r", encoding="utf-8") as fh:
            text = fh.read()
        updated = text
        for key, value in (
            ("PKG_VERSION", version),
            ("PKG_RELEASE", "1"),
            ("PKG_SOURCE", asset_name),
            ("PKG_SOURCE_URL", source_url),
            ("PKG_HASH", digest),
            ("HONK_EXTRACT_DIR", top),
        ):
            updated = replace_field(updated, key, value)

        print(f"honk latest: {tag} ({asset_name})")
        print(f"  version={version} sha256={digest}")
        print(f"  extract_dir={top}")
        if args.dry_run:
            print("dry-run: Makefile not modified")
        elif updated == text:
            print(f"no change: {args.makefile} already current")
        else:
            with open(args.makefile, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(updated)
            print(f"updated {args.makefile}")

        env_file = os.environ.get("GITHUB_ENV")
        if env_file:
            with open(env_file, "a", encoding="utf-8") as fh:
                fh.write(f"HONK_VERSION={tag}\n")
                fh.write(f"HONK_ASSET={asset_name}\n")
        return 0
    except Exception as exc:
        msg = f"honk auto-update skipped: {exc}"
        print(f"::warning::{msg}" if os.environ.get("GITHUB_ACTIONS") else msg, file=sys.stderr)
        return 1 if args.strict else 0


if __name__ == "__main__":
    sys.exit(main())
