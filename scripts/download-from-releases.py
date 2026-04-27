#!/usr/bin/env python3
"""
Bing Wallpaper - Download Images from GitHub Releases
Cross-platform: Windows, macOS, Linux
Build executable: pip install pyinstaller && pyinstaller --onefile download-from-releases.py
"""

import os
import sys
import argparse
import json
import time
import urllib.request
import urllib.error
import ssl

# Defaults
DEFAULT_REPO = "wafy80/wafy80.github.io"
DEFAULT_PREFIX = "wallpapers"
DEFAULT_DIR = "docs/img"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Download Bing wallpapers from GitHub releases"
    )
    parser.add_argument(
        "-d", "--dir", default=DEFAULT_DIR, help=f"Destination (default: {DEFAULT_DIR})"
    )
    parser.add_argument(
        "-r",
        "--repo",
        default=DEFAULT_REPO,
        help=f"Repository (default: {DEFAULT_REPO})",
    )
    parser.add_argument(
        "-a", "--all", action="store_true", help="Download all releases"
    )
    parser.add_argument(
        "--delay",
        type=float,
        default=0.5,
        help="Delay between requests in seconds (default: 0.5)",
    )
    return parser.parse_args()


def download_file(url, output_path):
    if os.path.exists(output_path):
        print(f"  [SKIP] {os.path.basename(output_path)} (exists)")
        return True
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(
            url, headers={"User-Agent": "BingWallpaper-Downloader"}
        )
        with urllib.request.urlopen(req, context=ctx, timeout=30) as response:
            with open(output_path, "wb") as f:
                f.write(response.read())
        print(f"  [OK] {os.path.basename(output_path)}")
        return True
    except Exception as e:
        print(f"  [FAIL] {os.path.basename(output_path)}: {e}")
        return False


def fetch_json(url):
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(
            url, headers={"User-Agent": "BingWallpaper-Downloader"}
        )
        with urllib.request.urlopen(req, context=ctx, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception as e:
        print(f"Error: {e}")
        return None


def download_release(repo, tag, dest_dir, delay=0.5):
    url = f"https://api.github.com/repos/{repo}/releases/tags/{tag}"
    data = fetch_json(url)
    if not data:
        return 0, 0
    assets = data.get("assets", [])
    print(f"Release: {tag} ({len(assets)} files)")
    os.makedirs(dest_dir, exist_ok=True)
    downloaded = skipped = 0
    for asset in assets:
        download_url = asset.get("browser_download_url", "")
        filename = asset.get("name", "")
        if not download_url or not filename:
            continue
        output_path = os.path.join(dest_dir, filename)
        if os.path.exists(output_path):
            skipped += 1
            print(f"  [SKIP] {filename}")
            continue
        if download_file(download_url, output_path):
            downloaded += 1
        time.sleep(delay)
    return downloaded, skipped


def download_from_manifest(dest_dir, repo, delay=0.5):
    manifest_path = os.path.join(dest_dir, "releases-manifest.json")
    if not os.path.exists(manifest_path):
        print(f"Manifest not found: {manifest_path}")
        return
    with open(manifest_path) as f:
        manifest = json.load(f)
    months = manifest.get("months", {})
    print(f"Found {len(months)} months")
    total_downloaded = total_skipped = 0
    for month, info in months.items():
        tag = info.get("tag", f"{DEFAULT_PREFIX}-{month}")
        print(f"\n--- {tag} ---")
        d, s = download_release(repo, tag, dest_dir, delay)
        total_downloaded += d
        total_skipped += s
    print(f"\n=== Total: {total_downloaded} downloaded, {total_skipped} skipped ===")


def download_all(dest_dir, repo, delay=0.5):
    print(f"Fetching releases from {repo}...")
    url = f"https://api.github.com/repos/{repo}/releases"
    data = fetch_json(url)
    if not data:
        print("No releases found")
        return
    releases = [
        item.get("tag_name", "")
        for item in data
        if item.get("tag_name", "").startswith(DEFAULT_PREFIX)
    ]
    print(f"Found {len(releases)} releases")
    total_downloaded = total_skipped = 0
    for tag in releases:
        print(f"\n--- {tag} ---")
        d, s = download_release(repo, tag, dest_dir, delay)
        total_downloaded += d
        total_skipped += s
        time.sleep(delay)
    print(f"\n=== Total: {total_downloaded} downloaded, {total_skipped} skipped ===")


def main():
    args = parse_args()
    script_dir = os.path.dirname(os.path.abspath(__file__))
    dest_dir = (
        os.path.abspath(args.dir)
        if os.path.isabs(args.dir)
        else os.path.join(script_dir, args.dir)
    )

    print("=" * 50)
    print("Bing Wallpaper - Download from GitHub Releases")
    print("=" * 50)
    print(f"Destination: {dest_dir}")
    print(f"Repository: {args.repo}")
    print()

    manifest_exists = os.path.exists(os.path.join(dest_dir, "releases-manifest.json"))
    delay = args.delay

    if args.all:
        download_all(dest_dir, args.repo, delay)
    elif manifest_exists:
        download_from_manifest(dest_dir, args.repo, delay)
    else:
        download_all(dest_dir, args.repo, delay)

    print("\nDone!")


if __name__ == "__main__":
    main()
