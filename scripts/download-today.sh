#!/bin/bash
# =============================================================================
# Bing Wallpaper - Download Wallpapers (Today + History)
# Universal: Linux / macOS / Windows (Git Bash, WSL, Cygwin)
#
# Usage:
#   ./download-today.sh              # Download today's wallpapers (all markets)
#   ./download-today.sh --history N  # Download N days before the oldest date
#                                    # currently in docs/img/index.html
# =============================================================================

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.conf" ]; then
    source "$SCRIPT_DIR/config.conf"
fi

# Parse arguments
HISTORY_DAYS=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --history|-h)
            HISTORY_DAYS="${2:-8}"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# If --history specified, override to that many days; otherwise just today
DAYS_COUNT=$((HISTORY_DAYS > 0 ? HISTORY_DAYS : 1))

# Archive URLs - GitHub primary
ARCHIVE_GITHUB="https://raw.githubusercontent.com/npanuhin/Bing-Wallpaper-Archive/refs/heads/master/api"

# Defaults (always set)
WALLPAPER_DIR="${WALLPAPER_DIR:-docs/img}"
SAVE_METADATA="${SAVE_METADATA:-true}"
GENERATE_GALLERY="${GENERATE_GALLERY:-true}"
FILENAME_FORMAT="${FILENAME_FORMAT:-}"
[ -z "$FILENAME_FORMAT" ] && FILENAME_FORMAT='bing-{date}.jpg'
ARCHIVE_LANG="${ARCHIVE_LANG:-US/en}"

# Markets in priority order
MARKETS=("en-US" "en-GB" "en-CA" "en-AU" "en-IN" "it-IT" "es-ES" "pt-BR" "fr-FR" "fr-CA" "de-DE" "ja-JP" "zh-CN")

# Market display names
declare -A MARKET_NAMES
MARKET_NAMES["en-US"]="United States"
MARKET_NAMES["en-GB"]="United Kingdom"
MARKET_NAMES["en-CA"]="Canada (EN)"
MARKET_NAMES["en-AU"]="Australia"
MARKET_NAMES["en-IN"]="India"
MARKET_NAMES["it-IT"]="Italy"
MARKET_NAMES["es-ES"]="Spain"
MARKET_NAMES["pt-BR"]="Brazil"
MARKET_NAMES["fr-FR"]="France"
MARKET_NAMES["fr-CA"]="Canada (FR)"
MARKET_NAMES["de-DE"]="Germany"
MARKET_NAMES["ja-JP"]="Japan"
MARKET_NAMES["zh-CN"]="China"

# Create folder if it doesn't exist
mkdir -p "$WALLPAPER_DIR"

if [ "$DAYS_COUNT" -gt 1 ]; then
    echo "🖼️  Bing Wallpaper - Download History ($DAYS_COUNT days before oldest in gallery)"
else
    echo "🖼️  Bing Wallpaper - Daily Download (All Markets)"
fi
echo "📁 Destination: $WALLPAPER_DIR"
echo "🌐 Markets: ${#MARKETS[@]} configured"
echo ""

# Extract wallpaper key from bing_url (e.g., "SeattleSunrise" from "OHR.SeattleSunrise_EN-US...")
extract_key() {
    local url="$1"
    local basename
    basename=$(basename "$url")
    # Pattern: OHR.KeyName_MARKET... (capture up to first underscore)
    if [[ "$basename" =~ OHR\.([^_]+)_ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "$url"
    fi
}

# Parse docs/img/index.html to find the oldest date currently in the gallery
# Returns date in YYYY-MM-DD format (index.html uses DD/MM/YYYY)
find_oldest_date() {
    local index_file="$WALLPAPER_DIR/index.html"
    if [ ! -f "$index_file" ]; then
        echo ""
        return
    fi

    # Extract all data-date attributes, convert DD/MM/YYYY -> YYYY-MM-DD, find minimum
    local oldest=""
    local oldest_epoch=999999999999

    while IFS= read -r date_str; do
        [ -z "$date_str" ] && continue
        # Convert DD/MM/YYYY to YYYY-MM-DD
        if [[ "$date_str" =~ ^([0-9]{2})/([0-9]{2})/([0-9]{4})$ ]]; then
            local day="${BASH_REMATCH[1]}"
            local month="${BASH_REMATCH[2]}"
            local year="${BASH_REMATCH[3]}"
            local iso_date="${year}-${month}-${day}"

            # Use date command to get epoch for comparison
            local epoch
            epoch=$(date -d "$iso_date" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$iso_date" +%s 2>/dev/null || echo "0")

            if [ "$epoch" -lt "$oldest_epoch" ]; then
                oldest_epoch="$epoch"
                oldest="$iso_date"
            fi
        fi
    done < <(grep -oP 'data-date="\K[0-9]{2}/[0-9]{2}/[0-9]{4}' "$index_file" | sort -u)

    echo "$oldest"
}

# Download a single wallpaper from archive JSON entry
download_from_archive() {
    local entry="$1"
    local market="$2"

    local TITLE COPYRIGHT DATE BING_URL
    TITLE=$(echo "$entry" | jq -r '.title // .caption // .subtitle // "No title available"')
    COPYRIGHT=$(echo "$entry" | jq -r '.copyright // "© No copyright info available"')
    DATE=$(echo "$entry" | jq -r '.date')  # YYYY-MM-DD
    BING_URL=$(echo "$entry" | jq -r '.bing_url // ""')

    if [ -z "$BING_URL" ] || [ "$BING_URL" = "null" ]; then
        echo "   ⚠️  No bing_url available for $DATE"
        return 1
    fi

    # Extract wallpaper key from bing_url
    local WALLPAPER_KEY
    WALLPAPER_KEY=$(extract_key "$BING_URL")
    echo "   Key: $WALLPAPER_KEY"

    # Check if already downloaded
    if [ -n "${DOWNLOADED_KEYS[$WALLPAPER_KEY]+x}" ]; then
        echo "   ⏭️  Skipped (duplicate of ${DOWNLOADED_KEYS[$WALLPAPER_KEY]})"
        return 2
    fi

    # Convert date format: YYYY-MM-DD -> YYYYMMDD
    local STARTDATE="${DATE//-/}"

    # Build filename - only key, no date (same image may appear on different dates across markets)
    local FILENAME="bing_${WALLPAPER_KEY}.jpg"
    local DEST="$WALLPAPER_DIR/$FILENAME"

    # Skip if file already exists
    if [ -f "$DEST" ]; then
        echo "   ✅ Already present: $DATE - $TITLE"
        echo "      File: $DEST"
        DOWNLOADED_KEYS[$WALLPAPER_KEY]="$market"
        return 0
    fi

    # Build image URLs - try UHD first, then original bing_url
    local FULL_URL
    FULL_URL="${BING_URL%_UHD.jpg}_UHD.jpg"  # Ensure UHD
    # If bing_url doesn't have UHD suffix, try to add it
    if [[ ! "$BING_URL" =~ UHD ]]; then
        FULL_URL="${BING_URL%.jpg}_UHD.jpg"
    else
        FULL_URL="$BING_URL"
    fi
    local FALLBACK_URL="$BING_URL"

    echo "   📥 Download: $DATE"
    echo "      Title: $TITLE"
    echo "      Copyright: $COPYRIGHT"
    echo "      File: $FILENAME"
    echo "      URL: $FULL_URL"

    # Download function
    local download_and_check
    download_and_check() {
        local url="$1"
        curl -sL "$url" -o "$DEST"
        if [ -s "$DEST" ]; then
            local size=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null || echo "0")
            if [ "$size" -gt 51200 ]; then
                return 0
            fi
        fi
        return 1
    }

    # Try UHD, then fallback to original bing_url
    download_and_check "$FULL_URL"
    if [ $? -ne 0 ]; then
        echo "      ⚠️  UHD not available, trying original URL..."
        rm -f "$DEST" 2>/dev/null
        download_and_check "$FALLBACK_URL"
    fi

    if [ ! -s "$DEST" ]; then
        echo "   ❌ Download error"
        rm -f "$DEST" 2>/dev/null
        return 1
    fi

    # Add watermark
    if command -v convert &>/dev/null && [ -n "$TITLE" ] && [ -n "$COPYRIGHT" ]; then
        echo "   🎨 Adding watermark..."

        # Check if title contains non-Latin characters
        local WATERMARK_TITLE="$TITLE"
        if echo "$TITLE" | grep -qP '[^\x00-\x7F\xC0-\xFF]'; then
            WATERMARK_TITLE="$WALLPAPER_KEY"
            echo "   ℹ️  Title has non-Latin characters, using key for watermark"
        fi

        local IMG_WIDTH FONT_SIZE
        IMG_WIDTH=$(identify -format "%w" "$DEST" 2>/dev/null || echo "3840")
        FONT_SIZE=$((IMG_WIDTH / 100))
        [ "$FONT_SIZE" -lt 6 ] && FONT_SIZE=6

        convert "$DEST" \
            -gravity NorthWest \
            -fill "rgba(255,255,255,0.9)" \
            -stroke "rgba(0,0,0,0.5)" \
            -strokewidth 1 \
            -pointsize "$FONT_SIZE" \
            -annotate +$((FONT_SIZE))+$((FONT_SIZE)) "$WATERMARK_TITLE" \
            -gravity SouthEast \
            -annotate +$((FONT_SIZE))+$((FONT_SIZE)) "$COPYRIGHT" \
            "$DEST.tmp" && mv "$DEST.tmp" "$DEST"
        echo "   ✅ Watermark added"
    fi

    # Save metadata
    if [ "$SAVE_METADATA" = "true" ]; then
        cat > "${DEST%.*}.txt" << EOF
Title: $TITLE
Copyright: $COPYRIGHT
Date: $STARTDATE
Full Date: $DATE
Hash: $HASH_SHORT
URL: $FULL_URL
Market: $market
Source: Bing Daily Wallpaper
EOF
        echo "   📝 Metadata saved"
    fi

    DOWNLOADED_KEYS[$WALLPAPER_KEY]="$market"
    echo "   ✅ Download complete"
    echo ""
    return 0
}

# Download a single wallpaper from Bing API JSON response
download_from_bing_api() {
    local JSON="$1"
    local market="$2"

    # Extract fields
    local IMG_PATH STARTDATE HASH FULLSTARTDATE COPYRIGHT_FULL TITLE COPYRIGHT
    IMG_PATH=$(echo "$JSON" | jq -r '.images[0].url')
    STARTDATE=$(echo "$JSON" | jq -r '.images[0].startdate')
    HASH=$(echo "$JSON" | jq -r '.images[0].hsh')
    FULLSTARTDATE=$(echo "$JSON" | jq -r '.images[0].fullstartdate')
    COPYRIGHT_FULL=$(echo "$JSON" | jq -r '.images[0].copyright')

    # Extract wallpaper key first (needed for fallback title)
    local WALLPAPER_KEY
    WALLPAPER_KEY=$(extract_key "$IMG_PATH")

    # Extract copyright and title
    local REGEX='^(.*)\(([^)]+)\)$'
    if [[ "$COPYRIGHT_FULL" =~ $REGEX ]]; then
        TITLE="${BASH_REMATCH[1]}"
        TITLE="${TITLE% }"
        COPYRIGHT="${BASH_REMATCH[2]}"
    else
        # Parsing failed: use key as title, full string as copyright
        TITLE=""
        COPYRIGHT="$COPYRIGHT_FULL"
    fi

    if [ -z "$IMG_PATH" ]; then
        echo "   ❌ Unable to extract image URL"
        return 1
    fi

    echo "   Key: $WALLPAPER_KEY"

    # Check if this wallpaper was already downloaded from a higher-priority market
    if [ -n "${DOWNLOADED_KEYS[$WALLPAPER_KEY]+x}" ]; then
        echo "   ⏭️  Skipped (duplicate of ${DOWNLOADED_KEYS[$WALLPAPER_KEY]})"
        return 2
    fi

    # Build filename - only key, no date (same image may appear on different dates across markets)
    local FILENAME="bing_${WALLPAPER_KEY}.jpg"
    local DEST="$WALLPAPER_DIR/$FILENAME"

    # Skip if file already exists
    if [ -f "$DEST" ]; then
        echo "   ✅ Already present: $STARTDATE - $TITLE"
        echo "      File: $DEST"
        DOWNLOADED_KEYS[$WALLPAPER_KEY]="$market"
        return 0
    fi

    # Build URLs
    local FULL_URL FALLBACK_URL HD_URL
    FULL_URL="https://www.bing.com${IMG_PATH//1920x1080/UHD}"
    FALLBACK_URL="https://www.bing.com${IMG_PATH//1920x1080/3840x2160}"
    HD_URL="https://www.bing.com$IMG_PATH"

    echo "   📥 Download: $STARTDATE"
    echo "      Title: $TITLE"
    echo "      Copyright: $COPYRIGHT"
    echo "      File: $FILENAME"
    echo "      URL (UHD): $FULL_URL"

    # Download function
    local download_and_check
    download_and_check() {
        local url="$1"
        curl -sL "$url" -o "$DEST"
        if [ -s "$DEST" ]; then
            local size=$(stat -c%s "$DEST" 2>/dev/null || stat -f%z "$DEST" 2>/dev/null || echo "0")
            if [ "$size" -gt 51200 ]; then
                return 0
            fi
        fi
        return 1
    }

    # Try UHD first, then 4K, then 1080p
    download_and_check "$FULL_URL"
    if [ $? -ne 0 ]; then
        echo "      ⚠️  UHD not available, trying 4K..."
        rm -f "$DEST" 2>/dev/null
        download_and_check "$FALLBACK_URL"
        if [ $? -ne 0 ]; then
            echo "      ⚠️  4K not available, using 1920x1080..."
            rm -f "$DEST" 2>/dev/null
            download_and_check "$HD_URL"
        fi
    fi

    if [ ! -s "$DEST" ]; then
        echo "   ❌ Download error"
        rm -f "$DEST" 2>/dev/null
        return 1
    fi

    # Add watermark
    if command -v convert &>/dev/null && [ -n "$COPYRIGHT" ]; then
        echo "   🎨 Adding watermark..."

        # Determine watermark title: use key if title is empty (parsing failed) or has non-Latin chars
        local WATERMARK_TITLE="$TITLE"
        if [ -z "$TITLE" ]; then
            WATERMARK_TITLE="$WALLPAPER_KEY"
            echo "   ℹ️  Title parsing failed, using key for watermark"
        elif echo "$TITLE" | grep -qP '[^\x00-\x7F\xC0-\xFF]'; then
            WATERMARK_TITLE="$WALLPAPER_KEY"
            echo "   ℹ️  Title has non-Latin characters, using key for watermark"
        fi

        local IMG_WIDTH FONT_SIZE
        IMG_WIDTH=$(identify -format "%w" "$DEST" 2>/dev/null || echo "3840")
        FONT_SIZE=$((IMG_WIDTH / 100))
        [ "$FONT_SIZE" -lt 6 ] && FONT_SIZE=6

        convert "$DEST" \
            -gravity NorthWest \
            -fill "rgba(255,255,255,0.9)" \
            -stroke "rgba(0,0,0,0.5)" \
            -strokewidth 1 \
            -pointsize "$FONT_SIZE" \
            -annotate +$((FONT_SIZE))+$((FONT_SIZE)) "$WATERMARK_TITLE" \
            -gravity SouthEast \
            -annotate +$((FONT_SIZE))+$((FONT_SIZE)) "$COPYRIGHT" \
            "$DEST.tmp" && mv "$DEST.tmp" "$DEST"
        echo "   ✅ Watermark added"
    fi

    # Save metadata
    if [ "$SAVE_METADATA" = "true" ]; then
        cat > "${DEST%.*}.txt" << EOF
Title: $TITLE
Copyright: $COPYRIGHT
Date: $STARTDATE
Full Date: $FULLSTARTDATE
Hash: $HASH
URL: $FULL_URL
Market: $market
Source: Bing Daily Wallpaper
EOF
        echo "   📝 Metadata saved"
    fi

    DOWNLOADED_KEYS[$WALLPAPER_KEY]="$market"
    echo "   ✅ Download complete"
    echo ""
    return 0
}

# Track downloaded keys to avoid duplicates
declare -A DOWNLOADED_KEYS

# Counters
DOWNLOADED=0
SKIPPED=0
ERRORS=0
TOTAL_PROCESSED=0

if [ "$DAYS_COUNT" -gt 1 ]; then
    # ── History mode: find N days before the oldest date in index.html ──

    # Step 1: Find the oldest date currently in the gallery
    OLDEST_DATE=$(find_oldest_date)

    if [ -z "$OLDEST_DATE" ]; then
        echo "⚠️  Cannot find index.html or no dates found in $WALLPAPER_DIR/index.html"
        echo "   Run a normal download first to bootstrap the gallery."
        exit 1
    fi

    echo "� Oldest date in gallery: $OLDEST_DATE"

    # Step 2: Calculate the date range: N days BEFORE the oldest date
    # start_date = oldest_date - DAYS_COUNT
    # end_date   = oldest_date - 1 day
    start_date=$(date -d "$OLDEST_DATE - $DAYS_COUNT days" +%Y-%m-%d 2>/dev/null || date -v-${DAYS_COUNT}d -j -f "%Y-%m-%d" "$OLDEST_DATE" +%Y-%m-%d 2>/dev/null)
    end_date=$(date -d "$OLDEST_DATE - 1 day" +%Y-%m-%d 2>/dev/null || date -v-1d -j -f "%Y-%m-%d" "$OLDEST_DATE" +%Y-%m-%d 2>/dev/null)

    echo "📡 Downloading archive: $start_date → $end_date"
    echo ""

    # Step 3: Collect all keys already downloaded
    declare -A EXISTING_KEYS
    for txt_file in "$WALLPAPER_DIR"/bing_*.txt "$WALLPAPER_DIR"/bing-*.txt; do
        [ -f "$txt_file" ] || continue
        key=$(basename "$txt_file" .txt)
        key="${key#bing-}"
        key="${key#bing_}"
        if [[ "$key" =~ ^[0-9]{8}_(.+) ]]; then
            key="${BASH_REMATCH[1]}"
        fi
        EXISTING_KEYS["$key"]=1
    done

    # Step 4: Fetch archive for primary market to find which keys correspond to target dates
    primary_github="${ARCHIVE_GITHUB}/US/en.json"
    ARCHIVE_JSON=$(curl -sL "$primary_github" 2>/dev/null)

    if [ -z "$ARCHIVE_JSON" ]; then
        echo "❌ Error: unable to fetch archive"
        exit 1
    fi

    # Build date→key map from archive
    declare -A DATE_TO_KEY
    while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        entry_date=$(echo "$entry" | jq -r '.date // ""')
        bing_url=$(echo "$entry" | jq -r '.bing_url // ""')
        [ -z "$entry_date" ] || [ "$entry_date" = "null" ] && continue
        [ -z "$bing_url" ] || [ "$bing_url" = "null" ] && continue
        DATE_TO_KEY["$entry_date"]=$(extract_key "$bing_url")
    done < <(echo "$ARCHIVE_JSON" | jq -c '.[] | select(.bing_url != null and .bing_url != "null")')

    # Step 5: Build the list of target dates (start_date → end_date)
    TARGET_DATES=()
    check_date="$start_date"
    while [[ "$check_date" < "$end_date" || "$check_date" == "$end_date" ]]; do
        TARGET_DATES+=("$check_date")
        check_date=$(date -d "$check_date + 1 day" +%Y-%m-%d 2>/dev/null || date -v+1d -j -f "%Y-%m-%d" "$check_date" +%Y-%m-%d 2>/dev/null)
    done

    if [ ${#TARGET_DATES[@]} -eq 0 ]; then
        echo "✅ No dates to download"
        echo "========================================="
        echo "✅ Done: 0 downloaded, 0 skipped, 0 errors"
        echo "========================================="
        exit 0
    fi

    echo "📅 Target dates (${#TARGET_DATES[@]} days):"
    for d in "${TARGET_DATES[@]}"; do
        day_key="${DATE_TO_KEY[$d]:-unknown}"
        echo "   - $d (key: $day_key)"
    done
    echo ""

    # Build jq date filter
    jq_dates=""
    for d in "${TARGET_DATES[@]}"; do
        [ -n "$jq_dates" ] && jq_dates+=" or "
        jq_dates+=".date == \"$d\""
    done

    # Step 6: For each market, fetch the archive and download target dates
    for market in "${MARKETS[@]}"; do
        market_name="${MARKET_NAMES[$market]:-$market}"

        echo "🔍 Checking archive: $market ($market_name)"

        IFS='-' read -r lang country <<< "$market"
        github_path="${country}/${lang}.json"

        MARKET_JSON=$(curl -sL "${ARCHIVE_GITHUB}/${github_path}" 2>/dev/null)

        if [ -z "$MARKET_JSON" ]; then
            echo "   ⚠️  Error fetching archive"
            SKIPPED=$((SKIPPED + 1))
            TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
            continue
        fi

        MARKET_DOWNLOADED=0
        MARKET_SKIPPED=0

        while IFS= read -r entry; do
            [ -z "$entry" ] && continue

            TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))

            bing_url=$(echo "$entry" | jq -r '.bing_url // ""')
            if [ -z "$bing_url" ] || [ "$bing_url" = "null" ]; then
                MARKET_SKIPPED=$((MARKET_SKIPPED + 1))
                continue
            fi

            entry_key=$(extract_key "$bing_url")

            if [ -n "${DOWNLOADED_KEYS[$entry_key]+x}" ] || [ -n "${EXISTING_KEYS[$entry_key]+x}" ]; then
                MARKET_SKIPPED=$((MARKET_SKIPPED + 1))
                continue
            fi

            download_from_archive "$entry" "$market"
            local_result=$?

            if [ $local_result -eq 0 ]; then
                DOWNLOADED=$((DOWNLOADED + 1))
                MARKET_DOWNLOADED=$((MARKET_DOWNLOADED + 1))
            elif [ $local_result -eq 1 ]; then
                ERRORS=$((ERRORS + 1))
            elif [ $local_result -eq 2 ]; then
                MARKET_SKIPPED=$((MARKET_SKIPPED + 1))
            fi
        done < <(echo "$MARKET_JSON" | jq -c "[.[] | select(.bing_url != null and .bing_url != \"null\" and ($jq_dates))] | reverse | .[]")

        echo "   📊 Market $market: $MARKET_DOWNLOADED downloaded, $MARKET_SKIPPED skipped"
        echo ""
    done
else
    # ── Daily mode (DAYS_COUNT == 1): use Bing API for today ──
    for market in "${MARKETS[@]}"; do
        API_URL="https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=$market"
        market_name="${MARKET_NAMES[$market]:-$market}"

        echo "🔍 Checking: $market ($market_name) [idx=0]"

        JSON=$(curl -s "$API_URL" 2>/dev/null)

        if [ -z "$JSON" ]; then
            echo "   ⚠️  Error connecting to Bing"
            SKIPPED=$((SKIPPED + 1))
            TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))
            continue
        fi

        download_from_bing_api "$JSON" "$market"
        local_result=$?

        TOTAL_PROCESSED=$((TOTAL_PROCESSED + 1))

        if [ $local_result -eq 0 ]; then
            DOWNLOADED=$((DOWNLOADED + 1))
        elif [ $local_result -eq 1 ]; then
            ERRORS=$((ERRORS + 1))
        elif [ $local_result -eq 2 ]; then
            SKIPPED=$((SKIPPED + 1))
        fi
    done
fi

echo "========================================="
echo "✅ Done: $DOWNLOADED downloaded, $SKIPPED skipped, $ERRORS errors (out of $TOTAL_PROCESSED total)"
echo "========================================="

exit 0
