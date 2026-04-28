#!/bin/bash
# =============================================================================
# Bing Wallpaper - Upload Images to GitHub Releases (Monthly Archive)
# Uses GitHub CLI (gh) - no token needed, authenticates via git credentials
# Creates monthly releases: wallpapers-2026-04, wallpapers-2026-05, etc.
# =============================================================================

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
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}🚀 Upload Images to GitHub Releases (Monthly)${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Check gh CLI is installed
if ! command -v gh &>/dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) not found${NC}"
    echo "   Install: sudo apt install gh  (Debian/Ubuntu)"
    echo "            brew install gh      (macOS)"
    exit 1
fi

# Authenticate for CI (GitHub Actions)
if [ -n "$GITHUB_TOKEN" ]; then
    echo "   Using GITHUB_TOKEN for CI authentication..."
    echo "$GITHUB_TOKEN" | gh auth login --with-token
fi

# Check authenticated
if ! gh auth status &>/dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub${NC}"
    echo "   Run: gh auth login"
    echo "   Or set GITHUB_TOKEN environment variable"
    exit 1
fi

echo -e "${GREEN}✅ Authenticated as: $(gh api user --jq '.login')${NC}"

# Count metadata files (images may not be local)
TXT_COUNT=$(find "$WALLPAPER_DIR" -maxdepth 1 \( -name "bing_*.txt" -o -name "bing-*.txt" \) -type f 2>/dev/null | wc -l)

if [ "$TXT_COUNT" -eq 0 ]; then
    echo -e "${RED}❌ No images found${NC}"
    exit 1
fi

echo -e "${GREEN}📸 Images to process: $TXT_COUNT${NC}"
echo ""

# Extract date from metadata file
# Returns YYYY-MM or empty if not found
get_image_month() {
    local txt_file="$1"
    local date_str
    
    date_str=$(grep "^Date:" "$txt_file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -z "$date_str" ]; then
        return 1
    fi
    
    # Date format: YYYYMMDD -> YYYY-MM
    if [[ "$date_str" =~ ^([0-9]{4})([0-9]{2})[0-9]{2}$ ]]; then
        echo "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
        return 0
    fi
    
    return 1
}

# Collect all unique months from metadata
declare -A MONTH_IMAGES
declare -A MONTH_FILES

while IFS= read -r txt_file; do
    [ -f "$txt_file" ] || continue
    
    month=$(get_image_month "$txt_file")
    if [ -n "$month" ]; then
        MONTH_IMAGES["$month"]=$(( ${MONTH_IMAGES["$month"]:-0} + 1 ))
        MONTH_FILES["$month"]+="$txt_file"$'\n'
    else
        echo -e "${RED}   ⚠️  Cannot determine month: $(basename "$txt_file")${NC}"
    fi
done < <(find "$WALLPAPER_DIR" -maxdepth 1 \( -name "bing_*.txt" -o -name "bing-*.txt" \) -type f 2>/dev/null)

# Sort months
SORTED_MONTHS=($(printf '%s\n' "${!MONTH_IMAGES[@]}" | sort))

echo -e "${YELLOW}📅 Found ${#SORTED_MONTHS[@]} month(s):${NC}"
for month in "${SORTED_MONTHS[@]}"; do
    echo -e "   ${BLUE}$month${NC}: ${MONTH_IMAGES[$month]} images"
done
echo ""

# Global counters
TOTAL_UPLOADED=0
TOTAL_SKIPPED=0
TOTAL_ERRORS=0

# Process each month
for month in "${SORTED_MONTHS[@]}"; do
    RELEASE_TAG="${RELEASE_PREFIX}-${month}"
    
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📦 Processing: $RELEASE_TAG${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════${NC}"
    
    # Get or create release
    RELEASE_URL=$(gh release view "$RELEASE_TAG" --json url --jq '.url' 2>/dev/null || echo "")
    
    if [ -z "$RELEASE_URL" ]; then
        echo "   Creating new release..."
        if gh release create "$RELEASE_TAG" \
            --title "Bing Wallpapers - $month" \
            --notes "Daily Bing wallpapers for $month - auto updated" \
            --latest=false 2>/dev/null; then
            echo -e "${GREEN}   ✅ Release created${NC}"
            RELEASE_URL="https://github.com/wafy80/wafy80.github.io/releases/download/$RELEASE_TAG"
        else
            echo -e "${RED}   ❌ Failed to create release${NC}"
            continue
        fi
    else
        echo -e "${GREEN}   ✅ Release exists${NC}"
    fi
    
    # Load existing assets from cache
    MONTH_CACHE="$SCRIPT_DIR/.release-${month}.json"
    declare -A ASSET_MAP=()

    if [ -f "$MONTH_CACHE" ]; then
        echo "   Loading from local cache..."
        while IFS= read -r name; do
            [ -n "$name" ] && ASSET_MAP["$name"]=1
        done < <(jq -r '.[]' "$MONTH_CACHE" 2>/dev/null)
        echo -e "${GREEN}   Cache: ${#ASSET_MAP[@]} files${NC}"
    else
        echo "   Loading from remote release..."
        EXISTING_ASSETS=$(gh release view "$RELEASE_TAG" --json assets --jq '.assets[].name' 2>/dev/null || echo "")
        while IFS= read -r asset; do
            [ -n "$asset" ] && ASSET_MAP["$asset"]=1
        done <<< "$EXISTING_ASSETS"
        echo -e "${GREEN}   Remote: ${#ASSET_MAP[@]} files${NC}"
    fi

    # Preliminary check: count how many files we need vs how many are already present
    MONTH_TOTAL_FILES=0
    MONTH_ALREADY_PRESENT=0

    while IFS= read -r txt_file; do
        [ -z "$txt_file" ] && continue
        [ -f "$txt_file" ] || continue

        jpg_file="${txt_file%.txt}.jpg"
        [ -f "$jpg_file" ] || continue

        MONTH_TOTAL_FILES=$((MONTH_TOTAL_FILES + 1))
        filename=$(basename "$jpg_file")
        [[ -n "${ASSET_MAP[$filename]}" ]] && MONTH_ALREADY_PRESENT=$((MONTH_ALREADY_PRESENT + 1))
    done <<< "${MONTH_FILES[$month]}"

    if [ "$MONTH_ALREADY_PRESENT" -eq "$MONTH_TOTAL_FILES" ] && [ "$MONTH_TOTAL_FILES" -gt 0 ]; then
        echo -e "${GREEN}   ✅ All $MONTH_TOTAL_FILES files already uploaded - skipping month${NC}"
        echo ""
        TOTAL_SKIPPED=$((TOTAL_SKIPPED + MONTH_TOTAL_FILES))
        unset ASSET_MAP
        continue
    fi

    if [ "$MONTH_TOTAL_FILES" -eq 0 ]; then
        echo -e "${YELLOW}   ⚠️  No image files found locally - skipping month${NC}"
        echo ""
        unset ASSET_MAP
        continue
    fi

    echo -e "${GREEN}   📤 Need to upload: $((MONTH_TOTAL_FILES - MONTH_ALREADY_PRESENT)) file(s)${NC}"
    echo ""

    # Upload function for this month
    upload_asset() {
        local file="$1"
        local name="$2"

        if [[ -n "${ASSET_MAP[$name]}" ]]; then
            echo -e "  ⏭️  $name (exists)"
            return 2
        fi

        if gh release upload "$RELEASE_TAG" "$file" --clobber 2>/dev/null; then
            ASSET_MAP["$name"]=1
            echo -e "  ✅ $name"
            return 0
        else
            echo -e "  ❌ $name"
            return 1
        fi
    }

    MONTH_UPLOADED=0
    MONTH_SKIPPED=0
    MONTH_ERRORS=0

    echo -e "${YELLOW}📤 Uploading images for $month...${NC}"
    
    while IFS= read -r txt_file; do
        [ -z "$txt_file" ] && continue
        [ -f "$txt_file" ] || continue
        
        jpg_file="${txt_file%.txt}.jpg"
        
        if [ ! -f "$jpg_file" ]; then
            echo -e "  ⚠️  Image not found: $(basename "$jpg_file")"
            MONTH_ERRORS=$((MONTH_ERRORS + 1))
            continue
        fi
        
        filename=$(basename "$jpg_file")
        
        upload_asset "$jpg_file" "$filename"
        result=$?
        
        if [ $result -eq 0 ]; then
            MONTH_UPLOADED=$((MONTH_UPLOADED + 1))
        elif [ $result -eq 2 ]; then
            MONTH_SKIPPED=$((MONTH_SKIPPED + 1))
        else
            MONTH_ERRORS=$((MONTH_ERRORS + 1))
        fi
        
        sleep 0.5
    done <<< "${MONTH_FILES[$month]}"
    
    # Save cache
    printf '%s\n' "${!ASSET_MAP[@]}" | jq -R -s 'split("\n") | map(select(length > 0))' > "$MONTH_CACHE"
    
    echo ""
    echo -e "${GREEN}📊 $RELEASE_TAG Summary:${NC}"
    echo -e "   Uploaded: $MONTH_UPLOADED"
    echo -e "   Skipped: $MONTH_SKIPPED"
    echo -e "   Errors: $MONTH_ERRORS"
    echo -e "${BLUE}   🔗 $RELEASE_URL${NC}"
    echo ""
    
    TOTAL_UPLOADED=$((TOTAL_UPLOADED + MONTH_UPLOADED))
    TOTAL_SKIPPED=$((TOTAL_SKIPPED + MONTH_SKIPPED))
    TOTAL_ERRORS=$((TOTAL_ERRORS + MONTH_ERRORS))
    
    # Clear ASSET_MAP for next iteration
    unset ASSET_MAP
done

# Generate global manifest
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW}📝 Generating manifest...${NC}"

cat > "$WALLPAPER_DIR/releases-manifest.json" << EOF
{
  "version": 2,
  "release_prefix": "$RELEASE_PREFIX",
  "base_url_pattern": "https://github.com/wafy80/wafy80.github.io/releases/download/{release_tag}/{filename}",
  "months": {
EOF

FIRST=true
for month in "${SORTED_MONTHS[@]}"; do
    RELEASE_TAG="${RELEASE_PREFIX}-${month}"
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$WALLPAPER_DIR/releases-manifest.json"
    fi
    
    # Get asset count from cache
    MONTH_CACHE="$SCRIPT_DIR/.release-${month}.json"
    ASSET_COUNT=0
    if [ -f "$MONTH_CACHE" ]; then
        ASSET_COUNT=$(jq 'length' "$MONTH_CACHE" 2>/dev/null || echo "0")
    fi
    
    cat >> "$WALLPAPER_DIR/releases-manifest.json" << EOF
    "$month": {
      "tag": "$RELEASE_TAG",
      "url": "https://github.com/wafy80/wafy80.github.io/releases/download/$RELEASE_TAG",
      "assets": $ASSET_COUNT
    }
EOF
done

cat >> "$WALLPAPER_DIR/releases-manifest.json" << 'EOF'

  }
}
EOF

echo -e "${GREEN}✅ Manifest saved${NC}"

echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}📊 Global Summary:${NC}"
echo -e "   Uploaded: $TOTAL_UPLOADED"
echo -e "   Skipped: $TOTAL_SKIPPED"
echo -e "   Errors: $TOTAL_ERRORS"
echo -e "   Months: ${#SORTED_MONTHS[@]}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"

exit 0
