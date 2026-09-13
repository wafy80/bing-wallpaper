#!/usr/bin/env python3
"""
Bing Wallpaper - Download Images from GitHub Releases
Cross-platform: Windows, macOS, Linux
Build executable: pip install pyinstaller && pyinstaller --onefile download-from-releases.py
"""

import os
import re
import sys
import argparse
import json
import time
import urllib.request
import urllib.error
import ssl

# Defaults
DEFAULT_REPO = "wafy80/bing-wallpaper"
DEFAULT_PREFIX = "wallpapers"
DEFAULT_DIR = "docs"


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


def get_auth_headers():
    headers = {"User-Agent": "BingWallpaper-Downloader"}
    token = os.getenv("GITHUB_TOKEN")
    if token:
        headers["Authorization"] = f"token {token}"
    return headers


def extract_assets_from_html(html_path):
    """Estrae tutti gli URL completi degli asset dal file index.html."""
    with open(html_path, "r", encoding="utf-8") as f:
        content = f.read()
    # Cerca tutti gli attributi data-full
    urls = re.findall(r'data-full="([^"]+)"', content)
    assets = []
    for url in urls:
        # Filtra solo file immagine comuni
        if any(url.lower().endswith(ext) for ext in (".jpg", ".jpeg", ".png", ".webp")):
            filename = url.split("/")[-1]
            assets.append((filename, url))
    return assets


def download_from_html(dest_dir, repo, delay=0.5):
    html_path = os.path.join(dest_dir, "index.html")
    if not os.path.exists(html_path):
        print(f"HTML not found: {html_path}")
        return
    assets = extract_assets_from_html(html_path)
    print(f"Found {len(assets)} wallpapers in HTML")
    os.makedirs(dest_dir, exist_ok=True)
    total_downloaded = total_skipped = total_failed = 0
    for i, (filename, url) in enumerate(assets, start=1):
        output_path = os.path.join(dest_dir, filename)
        # print(f"Processing {i}: {url}")
        if os.path.exists(output_path):
            total_skipped += 1
            print(f"  [SKIP] {filename}")
        else:
            if download_file(url, output_path):
                total_downloaded += 1
                time.sleep(delay)
            else:
                total_failed += 1
    print(f"\n=== Total: {total_downloaded} downloaded, {total_skipped} skipped, {total_failed} failed ===")


def download_file(url, output_path, force=False):
    if os.path.exists(output_path) and not force:
        print(f"  [SKIP] {os.path.basename(output_path)} (exists)")
        return True
    try:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
        req = urllib.request.Request(
            url, headers=get_auth_headers()
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
            url, headers=get_auth_headers()
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
    url = f"https://api.github.com/repos/{repo}/releases?per_page=100"
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
    # Se l'utente non specifica -d, usa la directory docs/ nella root del progetto
    if args.dir == DEFAULT_DIR:
        dest_dir = os.path.abspath(os.path.join(script_dir, "..", "docs"))
    else:
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
    html_exists = os.path.exists(os.path.join(dest_dir, "index.html"))
    delay = args.delay

    if args.all:
        download_all(dest_dir, args.repo, delay)
    elif html_exists:
        download_file("https://wafy80.github.io/bing-wallpaper/index.html", os.path.join(dest_dir, "index.html"), force=True)
        download_from_html(dest_dir, args.repo, delay)
    elif manifest_exists:
        download_file("https://wafy80.github.io/bing-wallpaper/releases-manifest.json", os.path.join(dest_dir, "releases-manifest.json"), force=True)
        download_from_manifest(dest_dir, args.repo, delay)
    else:
        download_all(dest_dir, args.repo, delay)

    print("\nDone!")


if __name__ == "__main__":
    main()
