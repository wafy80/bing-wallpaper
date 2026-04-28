#!/bin/bash
# =============================================================================
# Bing Wallpaper - Download Images from GitHub Releases
# Cross-platform: Linux, macOS, Windows (Git Bash/WSL)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.conf" ]; then
    source "$SCRIPT_DIR/config.conf"
fi

WALLPAPER_DIR="${WALLPAPER_DIR:-docs/img}"
RELEASE_PREFIX="wallpapers"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

REPO_OWNER="wafy80"
REPO_NAME="wafy80.github.io"
REPO="${REPO_OWNER}/${REPO_NAME}"

MODE="auto"

show_help() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Download images from GitHub releases.

OPTIONS:
    -m, --manifest    Use releases-manifest.json (default if exists)
    -a, --all         Download all releases (ignores manifest)
    -d, --dir PATH    Set destination directory (default: docs/img)
    -r, --repo USER/REPO  Set GitHub repository (default: wafy80/wafy80.github.io)
    -h, --help        Show this help message

EXAMPLES:
    $(basename "$0")                      # Auto mode
    $(basename "$0") -a                  # Download all releases
    $(basename "$0") -d ~/Pictures/Bing   # Custom output dir
    WALLPAPER_DIR=~/Pics $(basename "$0") # Via env variable

ENVIRONMENT:
    WALLPAPER_DIR    Output directory
    GITHUB_TOKEN     GitHub token for rate limits (optional)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--manifest) MODE="manifest"; shift ;;
        -a|--all) MODE="all"; shift ;;
        -d|--dir) WALLPAPER_DIR="$2"; shift 2 ;;
        -r|--repo) REPO="$2"; shift 2 ;;
        -h|--help) show_help; exit 0 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

if [ -n "$GITHUB_TOKEN" ]; then
    AUTH_HEADER="-HAuthorization: token $GITHUB_TOKEN"
fi

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}📥 Download Images from GitHub Releases${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

detect_os() {
    case "$OSTYPE" in
        msys*|mingw*|cygwin*) echo "windows" ;;
        darwin*) echo "macos" ;;
        linux*) echo "linux" ;;
        *) echo "linux" ;;
    esac
}

check_dependencies() {
    local os=$(detect_os)
    
    if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        echo -e "${RED}❌ curl or wget not found${NC}"
        exit 1
    fi
    
    if ! command -v jq &>/dev/null; then
        echo -e "${YELLOW}⚠️  jq not found - will use fallback parsing${NC}"
    fi
}

download_file() {
    local url="$1"
    local output="$2"
    local name="$3"
    
    if command -v curl &>/dev/null; then
        curl -sL --fail --retry 3 --retry-delay 2 $AUTH_HEADER -o "$output" "$url" 2>/dev/null
    else
        wget -q -O "$output" "$url" 2>/dev/null
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "  ✅ $name"
        return 0
    else
        echo -e "  ❌ $name"
        return 1
    fi
}

download_release_assets() {
    local tag="$1"
    local dest_dir="$2"
    
    mkdir -p "$dest_dir"
    
    local api_url="https://api.github.com/repos/${REPO}/releases/tags/${tag}"
    local assets_json
    
    if command -v curl &>/dev/null; then
        assets_json=$(curl -sL $AUTH_HEADER "$api_url" 2>/dev/null)
    else
        assets_json=$(wget -qO- "$api_url" 2>/dev/null)
    fi
    
    if [ -z "$assets_json" ]; then
        echo -e "${RED}   ❌ Failed to fetch release info${NC}"
        return 1
    fi
    
    if command -v jq &>/dev/null; then
        local asset_count=$(echo "$assets_json" | jq -r '.assets | length' 2>/dev/null || echo "0")
        echo -e "${CYAN}   📦 Assets: $asset_count${NC}"
        
        echo "$assets_json" | jq -r '.assets[] | "\(.browser_download_url) \(.name)"' 2>/dev/null | while read url name; do
            [ -z "$url" ] && continue
            local output="$dest_dir/$name"
            
            if [ -f "$output" ]; then
                echo -e "  ⏭️  $name (exists)"
            else
                download_file "$url" "$output" "$name"
            fi
        done
    else
        echo "$assets_json" | grep -o '"browser_download_url": "[^"]*"' | cut -d'"' -f4 | while read url; do
            [ -z "$url" ] && continue
            local name=$(basename "$url")
            local output="$dest_dir/$name"
            
            if [ -f "$output" ]; then
                echo -e "  ⏭️  $name (exists)"
            else
                download_file "$url" "$output" "$name"
            fi
        done
    fi
}

download_from_manifest() {
    local manifest_path="$WALLPAPER_DIR/releases-manifest.json"
    
    if [ ! -f "$manifest_path" ]; then
        echo -e "${RED}❌ Manifest not found: $manifest_path${NC}"
        echo "   Run upload-to-releases.sh first to create releases"
        return 1
    fi
    
    echo -e "${GREEN}📋 Reading manifest...${NC}"
    echo ""
    
    if command -v jq &>/dev/null; then
        local months=$(jq -r '.months | keys[]' "$manifest_path" 2>/dev/null)
    else
        local months=$(grep -o '"[0-9]\{4\}-[0-9]\{2\}"' "$manifest_path" | tr -d '"')
    fi
    
    if [ -z "$months" ]; then
        echo -e "${RED}❌ No months found in manifest${NC}"
        return 1
    fi
    
    local month_list=()
    while IFS= read -r month; do
        [ -n "$month" ] && month_list+=("$month")
    done <<< "$months"
    
    echo -e "${YELLOW}📅 Found ${#month_list[@]} month(s):${NC}"
    for month in "${month_list[@]}"; do
        echo -e "   ${BLUE}$month${NC}"
    done
    echo ""
    
    local total_downloaded=0
    local total_skipped=0
    local total_errors=0
    
    for month in "${month_list[@]}"; do
        local tag="${RELEASE_PREFIX}-${month}"
        
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"
        echo -e "${YELLOW}📦 Downloading: $tag${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"
        
        if command -v jq &>/dev/null; then
            local url=$(jq -r ".months.\"$month\".url" "$manifest_path" 2>/dev/null)
        else
            local url="https://github.com/${REPO}/releases/download/${tag}"
        fi
        
        download_release_assets "$tag" "$WALLPAPER_DIR"
        
        echo ""
    done
    
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}📊 Download complete${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
}

download_all_releases() {
    echo -e "${GREEN}🔍 Fetching all releases...${NC}"
    
    local api_url="https://api.github.com/repos/${REPO}/releases"
    local releases_json
    
    if command -v curl &>/dev/null; then
        releases_json=$(curl -sL $AUTH_HEADER "$api_url" 2>/dev/null)
    else
        releases_json=$(wget -qO- "$api_url" 2>/dev/null)
    fi
    
    if [ -z "$releases_json" ]; then
        echo -e "${RED}❌ Failed to fetch releases${NC}"
        exit 1
    fi
    
    if command -v jq &>/dev/null; then
        local tags=$(echo "$releases_json" | jq -r ".[].tag_name" 2>/dev/null | grep "^${RELEASE_PREFIX}-")
    else
        local tags=$(echo "$releases_json" | grep -o "\"tag_name\": *\"${RELEASE_PREFIX}-[^\"]*\"" | cut -d'"' -f4)
    fi
    
    if [ -z "$tags" ]; then
        echo -e "${RED}❌ No ${RELEASE_PREFIX} releases found${NC}"
        exit 1
    fi
    
    local tag_list=()
    while IFS= read -r tag; do
        [ -n "$tag" ] && tag_list+=("$tag")
    done <<< "$tags"
    
    echo -e "${YELLOW}📅 Found ${#tag_list[@]} release(s):${NC}"
    for tag in "${tag_list[@]}"; do
        local month=$(echo "$tag" | sed "s/${RELEASE_PREFIX}-//")
        echo -e "   ${BLUE}$month${NC}"
    done
    echo ""
    
    for tag in "${tag_list[@]}"; do
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"
        echo -e "${YELLOW}📦 Downloading: $tag${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════${NC}"
        
        download_release_assets "$tag" "$WALLPAPER_DIR"
        echo ""
    done
    
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${GREEN}📊 Download complete${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
}

main() {
    check_dependencies
    
    if [ "$MODE" = "all" ]; then
        download_all_releases
    elif [ "$MODE" = "manifest" ] || [ -f "$WALLPAPER_DIR/releases-manifest.json" ]; then
        download_from_manifest
    else
        download_all_releases
    fi
}

main "$@"