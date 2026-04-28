#!/bin/bash
# =============================================================================
# Bing Wallpaper - HTML Gallery Generator
# Creates a responsive web gallery with all downloaded images
# Universal: Linux / macOS / Windows
# =============================================================================

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/config.conf" ]; then
    source "$SCRIPT_DIR/config.conf"
fi

WALLPAPER_DIR="${WALLPAPER_DIR:-docs/img}"
OUTPUT="$WALLPAPER_DIR/index.html"
THUMB_DIR="$WALLPAPER_DIR/thumbs"
THUMB_SIZE="${THUMB_SIZE:-300}"
LAST_UPDATED=$(date +"%d/%m/%Y, %H:%M")

# Month names for breadcrumbs
MONTH_NAMES=("January" "February" "March" "April" "May" "June" "July" "August" "September" "October" "November" "December")

# Release configuration
RELEASE_BASE_URL="https://github.com/wafy80/wafy80.github.io/releases/download/wallpapers-archive"

# Count metadata files (images may not be local, stored in Releases)
TXT_COUNT=$(find "$WALLPAPER_DIR" -maxdepth 1 \( -name "bing_*.txt" -o -name "bing-*.txt" \) -type f 2>/dev/null | wc -l)

# Calculate additional statistics
if [ "$TXT_COUNT" -gt 0 ]; then
    # Extract all dates from metadata files to calculate month count and date range
    DATES_TEMP=$(mktemp)
    find "$WALLPAPER_DIR" -maxdepth 1 \( -name "bing_*.txt" -o -name "bing-*.txt" \) -type f 2>/dev/null | while read txt_file; do
        date=$(grep "^Date:" "$txt_file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Extract date from filename if not found in metadata (old format fallback)
        if [ "$date" = "Unknown" ] || [ -z "$date" ]; then
            jpg_basename=$(basename "$txt_file" .txt).jpg
            date=$(echo "$jpg_basename" | grep -oP '[0-9]{8}' | head -1)
        fi
        # Format date as YYYYMM for easy sorting
        if [ ${#date} -eq 8 ]; then
            echo "${date:0:6}" >> "$DATES_TEMP"
        fi
    done
    
    # Calculate unique months count
    if [ -f "$DATES_TEMP" ]; then
        UNIQUE_MONTHS=$(sort -u "$DATES_TEMP" | wc -l)
        
        # Calculate date range (oldest and newest)
        OLDEST_MONTH=$(sort "$DATES_TEMP" | head -1)
        NEWEST_MONTH=$(sort -r "$DATES_TEMP" | head -1)
        
        # Format as MM/YYYY for display
        if [ -n "$OLDEST_MONTH" ] && [ -n "$NEWEST_MONTH" ]; then
            OLDEST_DISPLAY="${OLDEST_MONTH:4:2}/${OLDEST_MONTH:0:4}"
            NEWEST_DISPLAY="${NEWEST_MONTH:4:2}/${NEWEST_MONTH:0:4}"
            DATE_RANGE="$OLDEST_DISPLAY - $NEWEST_DISPLAY"
        else
            DATE_RANGE="N/A"
        fi
        
        rm -f "$DATES_TEMP"
    else
        UNIQUE_MONTHS=0
        DATE_RANGE="N/A"
    fi
else
    UNIQUE_MONTHS=0
    DATE_RANGE="N/A"
fi

if [ "$TXT_COUNT" -eq 0 ]; then
    echo "❌ No images found in $WALLPAPER_DIR"
    echo "   Run first: ./download-today.sh or ./sync-archive.sh"
    exit 1
fi

# Load releases manifest if exists
MANIFEST="$WALLPAPER_DIR/releases-manifest.json"
RELEASE_PREFIX="wallpapers"
MANIFEST_VERSION=1

if [ -f "$MANIFEST" ]; then
    # Check if manifest is v2 (monthly)
    manifest_version=$(jq -r '.version // 1' "$MANIFEST" 2>/dev/null)
    if [ "$manifest_version" = "2" ]; then
        RELEASE_PREFIX=$(jq -r '.release_prefix // "wallpapers"' "$MANIFEST" 2>/dev/null)
        MANIFEST_VERSION=2
        echo "📦 Using monthly release manifest (v2)"
    fi
fi

# Function to get release URL for a given date
# Args: date (YYYYMMDD), filename
get_release_url() {
    local date="$1"
    local filename="$2"
    
    # Extract YYYY-MM from date
    local year="${date:0:4}"
    local month="${date:4:2}"
    local month_key="${year}-${month}"
    
    if [ "$MANIFEST_VERSION" = "2" ]; then
        # Lookup from manifest
        local month_url
        month_url=$(jq -r ".months[\"$month_key\"].url // \"\"" "$MANIFEST" 2>/dev/null)
        
        if [ -n "$month_url" ]; then
            echo "${month_url}/${filename}"
            return
        fi
    fi
    
    # Fallback: costruisce URL mensile anche se non ancora nel manifest
    echo "https://github.com/wafy80/wafy80.github.io/releases/download/${RELEASE_PREFIX}-${month_key}/${filename}"
}

# Create thumbnail directory
mkdir -p "$THUMB_DIR"

echo "📸 Found $TXT_COUNT images. Generating gallery with monthly breadcrumbs..."
echo "🖼️  Generating thumbnails (${THUMB_SIZE}px)..."

# Generate thumbnails (from local .jpg files, skip if missing)
generate_thumbnails() {
    local count=0
    local skipped=0
    while IFS= read -r txt_file; do
        [ -f "$txt_file" ] || continue
        local jpg_file="${txt_file%.txt}.jpg"
        local thumb_file="$THUMB_DIR/$(basename "$jpg_file")"
        
        if [ -f "$jpg_file" ]; then
            if [ ! -f "$thumb_file" ] || [ "$jpg_file" -nt "$thumb_file" ]; then
                convert "$jpg_file" -resize "${THUMB_SIZE}x" -quality 85 "$thumb_file" 2>/dev/null && \
                    ((count++))
            else
                ((skipped++))
            fi
        else
            ((skipped++))
        fi
    done < <(find "$WALLPAPER_DIR" -maxdepth 1 \( -name "bing_*.txt" -o -name "bing-*.txt" \) -type f 2>/dev/null)

    echo "✅ Generated $count thumbnails ($skipped skipped - images may be on Releases)"
}

generate_thumbnails

# Generate cards grouped by month (from .txt files)
generate_cards_by_month() {
    local current_month=""

    while IFS= read -r txt_file; do
        [ -f "$txt_file" ] || continue

        local txt_basename=$(basename "$txt_file")
        local jpg_basename="${txt_basename%.txt}.jpg"
        local date="Unknown"
        local title="Bing Wallpaper"
        local copyright="N/A"

        # Read metadata from txt
        title=$(grep "^Title:" "$txt_file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        copyright=$(grep "^Copyright:" "$txt_file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        date=$(grep "^Date:" "$txt_file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        market=$(grep "^Market:" "$txt_file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Extract date from filename if not found in metadata (old format fallback)
        if [ "$date" = "Unknown" ] || [ -z "$date" ]; then
            date=$(echo "$jpg_basename" | grep -oP '[0-9]{8}' | head -1)
        fi

        # Format date and extract year-month
        if [ ${#date} -eq 8 ]; then
            date_fmt="${date:6:2}/${date:4:2}/${date:0:4}"
            year="${date:0:4}"
            month="${date:4:2}"
        else
            date_fmt="$date"
            year="unknown"
            month="00"
        fi

        month_year_key="${year}-${month}"

        # If month changed, output separator
        if [ "$month_year_key" != "$current_month" ]; then
            current_month="$month_year_key"
            month_num=$((10#$month))
            month_name="${MONTH_NAMES[$((month_num-1))]}"
            echo "<!--MONTH_SEPARATOR:${month_name} ${year}:${month_year_key}-->"
        fi

        # Fallback title: use wallpaper key from filename instead of generic placeholder
        if [ -z "$title" ]; then
            title="${jpg_basename#bing_}"
            title="${title%.jpg}"
        fi
        [ -z "$copyright" ] && copyright="Microsoft Bing"
        [ -z "$market" ] && market="Unknown"

        local thumb_filename="thumbs/$jpg_basename"
        local full_release_url
        full_release_url=$(get_release_url "$date" "$jpg_basename")

        cat << CARD
        <div class="card" data-title="$title" data-copyright="$copyright" data-date="$date_fmt" data-filename="$jpg_basename" data-full="$full_release_url" data-month="${month_year_key}" data-market="$market">
            <img src="$thumb_filename" alt="$title" class="card-img" loading="lazy" onclick="openLightboxFromCard(this)">
            <div class="card-info">
                <h3 class="card-title" title="$title">$title</h3>
                <p class="card-copyright">$copyright</p>
                <p class="card-date">📅 $date_fmt</p>
                <p class="card-market">🌐 $market</p>
            </div>
        </div>
CARD
    done < <(find "$WALLPAPER_DIR" -maxdepth 1 \( -name "bing_*.txt" -o -name "bing-*.txt" \) -type f -print0 2>/dev/null | \
        while IFS= read -r -d '' file; do
            # Extract date from metadata inside the txt file
            date=$(grep "^Date:" "$file" 2>/dev/null | cut -d':' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | head -1)
            [ -z "$date" ] && date="00000000"
            echo "$date $file"
        done | sort -rn | cut -d' ' -f2-)
}

# Create HTML
cat > "$OUTPUT" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Bing Wallpaper Gallery</title>
    <style>
        :root {
            --primary: #0078D4;
            --primary-dark: #005a9e;
            --bg: #1a1a2e;
            --card-bg: #16213e;
            --text: #eaeaea;
            --text-muted: #a0a0a0;
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: var(--bg);
            color: var(--text);
            min-height: 100vh;
            padding: 20px;
        }

        .header {
            max-width: 1400px;
            margin: 0 auto 30px;
            text-align: center;
            padding: 30px 20px;
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            border-radius: 16px;
            box-shadow: 0 8px 32px rgba(0,120,212,0.3);
        }

        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }

        .header p {
            color: rgba(255,255,255,0.9);
            font-size: 1.1em;
        }

        .stats {
            display: flex;
            justify-content: center;
            gap: 30px;
            margin-top: 20px;
            flex-wrap: wrap;
        }

        .stat-item {
            background: rgba(255,255,255,0.1);
            padding: 10px 20px;
            border-radius: 8px;
            font-size: 0.9em;
        }

        .search-container {
            max-width: 1400px;
            margin: 0 auto 30px;
            display: flex;
            gap: 12px;
            flex-wrap: wrap;
            align-items: center;
        }

        .market-select {
            padding: 14px 16px;
            border: 2px solid transparent;
            border-radius: 10px;
            font-size: 14px;
            background: var(--card-bg);
            color: var(--text);
            cursor: pointer;
            min-width: 180px;
            transition: border-color 0.3s;
        }

        .market-select:focus {
            outline: none;
            border-color: var(--primary);
        }

        .market-select option {
            background: var(--card-bg);
            color: var(--text);
        }

        .search-box {
            flex: 1;
            min-width: 280px;
            padding: 14px 20px;
            border: 2px solid transparent;
            border-radius: 10px;
            font-size: 16px;
            background: var(--card-bg);
            color: var(--text);
            transition: border-color 0.3s;
        }

        .search-box:focus {
            outline: none;
            border-color: var(--primary);
        }

        .search-btn, .filter-btn {
            padding: 14px 25px;
            background: var(--primary);
            color: white;
            border: none;
            border-radius: 10px;
            cursor: pointer;
            font-size: 16px;
            font-weight: 600;
            transition: all 0.3s;
        }

        .search-btn:hover, .filter-btn:hover {
            background: var(--primary-dark);
            transform: translateY(-2px);
        }

        .filter-btn {
            background: var(--card-bg);
            border: 2px solid var(--primary);
        }

        .filter-btn.active {
            background: var(--primary);
        }

        .gallery-info {
            max-width: 1400px;
            margin: 0 auto 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
            color: var(--text-muted);
            font-size: 14px;
        }

        .gallery {
            max-width: 1400px;
            margin: 0 auto;
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 25px;
        }

        .card {
            background: var(--card-bg);
            border-radius: 14px;
            overflow: hidden;
            transition: all 0.3s ease;
            cursor: pointer;
            box-shadow: 0 4px 15px rgba(0,0,0,0.3);
        }

        .card:hover {
            transform: translateY(-8px) scale(1.02);
            box-shadow: 0 12px 40px rgba(0,120,212,0.4);
        }

        .card-img {
            width: 100%;
            height: 200px;
            object-fit: cover;
            display: block;
        }

        .card-info {
            padding: 18px;
        }

        .card-title {
            font-size: 1.15em;
            font-weight: 600;
            margin-bottom: 8px;
            color: var(--text);
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .card-copyright {
            font-size: 0.88em;
            color: var(--text-muted);
            margin-bottom: 8px;
            display: -webkit-box;
            -webkit-line-clamp: 2;
            line-clamp: 2;
            -webkit-box-orient: vertical;
            overflow: hidden;
            line-height: 1.4;
        }

        .card-date {
            font-size: 0.82em;
            color: var(--primary);
            font-weight: 500;
        }

        .card-market {
            font-size: 0.82em;
            color: var(--text-muted);
        }

        .toast-notification {
            position: fixed;
            bottom: 30px;
            left: 50%;
            transform: translateX(-50%) translateY(20px);
            background: var(--primary);
            color: white;
            padding: 12px 24px;
            border-radius: 10px;
            font-size: 14px;
            font-weight: 500;
            box-shadow: 0 6px 20px rgba(0,120,212,0.4);
            opacity: 0;
            z-index: 100000;
            transition: opacity 0.3s ease, transform 0.3s ease;
            pointer-events: none;
        }

        .toast-notification.show {
            opacity: 1;
            transform: translateX(-50%) translateY(0);
        }

        .no-results {
            max-width: 1400px;
            margin: 50px auto;
            text-align: center;
            padding: 40px;
            background: var(--card-bg);
            border-radius: 14px;
            display: none;
        }

        .no-results.show {
            display: block;
        }

        .no-results h2 {
            color: var(--text-muted);
            margin-bottom: 10px;
        }

        /* Lightbox */
        .lightbox {
            display: none;
            position: fixed;
            z-index: 10000;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: rgba(0,0,0,0.95);
            backdrop-filter: blur(10px);
        }

        .lightbox.active {
            display: flex;
            justify-content: center;
            align-items: center;
            flex-direction: column;
        }

        .lightbox-img {
            max-width: 90%;
            max-height: 80vh;
            border-radius: 8px;
            box-shadow: 0 8px 64px rgba(0,0,0,0.5);
        }

        .lightbox-info {
            text-align: center;
            padding: 20px;
            max-width: 800px;
        }

        .lightbox-title {
            font-size: 1.8em;
            margin-bottom: 10px;
        }

        .lightbox-copyright {
            color: var(--text-muted);
            font-size: 1.1em;
            margin-bottom: 5px;
        }

        .lightbox-date {
            color: var(--primary);
            font-size: 0.95em;
        }

        .lightbox-market {
            color: var(--text-muted);
            font-size: 0.9em;
        }

        .lightbox-close {
            position: absolute;
            top: 20px;
            right: 30px;
            font-size: 3em;
            color: white;
            cursor: pointer;
            transition: transform 0.3s;
            line-height: 1;
        }

        .lightbox-close:hover {
            transform: scale(1.2);
            color: var(--primary);
        }

        .lightbox-nav {
            position: absolute;
            top: 50%;
            transform: translateY(-50%);
            font-size: 3em;
            color: white;
            cursor: pointer;
            padding: 20px;
            transition: all 0.3s;
            user-select: none;
        }

        .lightbox-nav:hover {
            color: var(--primary);
        }

        .lightbox-prev { left: 20px; }
        .lightbox-next { right: 20px; }

        .lightbox-actions {
            margin-top: 20px;
            display: flex;
            flex-wrap: wrap;
            gap: 12px;
            justify-content: center;
        }

        .lightbox-btn {
            padding: 10px 20px;
            background: var(--primary);
            color: white;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 600;
            transition: all 0.3s;
            white-space: nowrap;
            flex-shrink: 0;
            text-decoration: none;
            display: inline-block;
        }

        .lightbox-btn:hover {
            background: var(--primary-dark);
            transform: translateY(-2px);
        }

        footer {
            max-width: 1400px;
            margin: 50px auto 20px;
            text-align: center;
            padding: 20px;
            color: var(--text-muted);
            font-size: 0.9em;
            border-top: 1px solid var(--card-bg);
        }

        footer a {
            color: var(--primary);
            text-decoration: none;
        }

        footer a:hover {
            text-decoration: underline;
        }

        @media (max-width: 768px) {
            .header h1 { font-size: 1.8em; }
            .gallery { grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 15px; }
            .search-container { flex-direction: column; }
            .search-box { min-width: 100%; }
            .market-select { min-width: 100%; width: 100%; }
            .lightbox-nav { font-size: 2em; padding: 10px; }
            .lightbox-close { font-size: 2em; top: 10px; right: 15px; }
            .month-breadcrumbs { flex-wrap: wrap; }
            .month-breadcrumb { font-size: 12px; padding: 8px 12px; }
        }

        /* Monthly Breadcrumb Navigation */
        .month-navigation {
            max-width: 1400px;
            margin: 20px auto 30px;
            background: var(--card-bg);
            border-radius: 12px;
            padding: 15px 20px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }

        .month-navigation h3 {
            margin: 0 0 12px 0;
            color: var(--text-muted);
            font-size: 14px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .month-breadcrumbs {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
            align-items: center;
        }

        .month-breadcrumb {
            padding: 10px 18px;
            background: var(--bg);
            color: var(--text);
            border: 2px solid transparent;
            border-radius: 8px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-block;
        }

        .month-breadcrumb:hover {
            background: var(--primary);
            color: white;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,120,212,0.3);
        }

        .month-breadcrumb.active {
            background: var(--primary);
            color: white;
            border-color: var(--primary-dark);
            box-shadow: 0 4px 12px rgba(0,120,212,0.3);
        }

        .month-breadcrumb .month-count {
            font-size: 12px;
            opacity: 0.85;
            margin-left: 4px;
        }

        .month-section {
            margin-bottom: 40px;
        }

        .month-section-header {
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            color: white;
            padding: 15px 20px;
            border-radius: 10px;
            margin-bottom: 20px;
            display: flex;
            justify-content: space-between;
            align-items: center;
            box-shadow: 0 4px 15px rgba(0,120,212,0.3);
        }

        .month-section-header h2 {
            margin: 0;
            font-size: 1.5em;
        }

        .month-section-header .month-count {
            font-size: 0.9em;
            opacity: 0.9;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Bing Wallpaper Gallery</h1>
        <p>Your collection of Bing daily wallpapers</p>
        <div class="stats">
HTMLHEAD

# Add useful statistics
echo "            <div class=\"stat-item\">📸 $TXT_COUNT wallpapers</div>" >> "$OUTPUT"
echo "            <div class=\"stat-item\">📅 $UNIQUE_MONTHS months</div>" >> "$OUTPUT"
echo "            <div class=\"stat-item\">🗓️ $DATE_RANGE</div>" >> "$OUTPUT"

cat >> "$OUTPUT" << HTMLMID
        </div>
    </div>

    <div class="search-container">
        <select class="market-select" id="marketFilter" onchange="filterGallery()">
            <option value="all">🌐 All Markets</option>
        </select>
        <input type="text" class="search-box" id="searchInput" placeholder="Search by title, copyright, or date..." onkeyup="filterGallery()">
        <button class="search-btn" onclick="filterGallery()">🔍 Search</button>
        <button class="filter-btn" onclick="resetFilter()">🔄 Show All</button>
        <button class="filter-btn" onclick="document.getElementById('footer').scrollIntoView({behavior:'smooth'})">📅 Month list</button>
    </div>

    <div class="gallery-info">
        <span id="resultsCount"></span>
        <span>Last updated: $LAST_UPDATED</span>
    </div>

    <div class="no-results" id="noResults">
        <h2>😕 No images found</h2>
        <p>Try modifying your search terms</p>
    </div>

    <div class="gallery" id="gallery">
HTMLMID

# Generate cards by month
generate_cards_by_month >> "$OUTPUT"

cat >> "$OUTPUT" << 'HTMLMID2'
    </div>

    <!-- Monthly Breadcrumb Navigation -->
    <div class="month-navigation" id="monthNavigation">
    </div>

    <!-- Lightbox -->
    <div class="lightbox" id="lightbox">
        <span class="lightbox-close" onclick="closeLightbox()">&times;</span>
        <span class="lightbox-nav lightbox-prev" onclick="navigateLightbox(-1)">&#10094;</span>
        <span class="lightbox-nav lightbox-next" onclick="navigateLightbox(1)">&#10095;</span>

        <img src="" alt="" class="lightbox-img" id="lightboxImg">

        <div class="lightbox-info">
            <h2 class="lightbox-title" id="lightboxTitle"></h2>
            <p class="lightbox-copyright" id="lightboxCopyright"></p>
            <p class="lightbox-date" id="lightboxDate"></p>
            <p class="lightbox-market" id="lightboxMarket"></p>

            <div class="lightbox-actions">
                <a href="#" class="lightbox-btn" id="downloadBtn" download>📥 Download</a>
                <button class="lightbox-btn" onclick="openFullImage()">🔍 Open Full</button>
                <button class="lightbox-btn" onclick="copyImageUrl()">� Copy URL</button>
                <button class="lightbox-btn" onclick="copyImageInfo()">📝 Copy Info</button>
                <button class="lightbox-btn" onclick="shareImage()">🔗 Share</button>
            </div>
        </div>
    </div>

    <footer id="footer">
        <p>Generated with <strong>Bing Wallpaper Manager</strong></p>
        <p>Images © Microsoft Bing and respective authors</p>
        <p><a href="https://github.com/npanuhin/Bing-Wallpaper-Archive" target="_blank">Historical archive courtesy of npanuhin</a></p>
    </footer>

    <script>
        let currentImageIndex = 0;
        let images = [];
        let allCards = [];
        let currentMonth = 'all';
        let months = [];

        const MARKET_NAMES = {
            'en-US': 'United States', 'en-GB': 'United Kingdom', 'en-CA': 'Canada (EN)',
            'en-AU': 'Australia', 'en-IN': 'India', 'it-IT': 'Italy', 'es-ES': 'Spain',
            'pt-BR': 'Brazil', 'fr-FR': 'France', 'fr-CA': 'Canada (FR)',
            'de-DE': 'Germany', 'ja-JP': 'Japan', 'zh-CN': 'China'
        };

        const MARKET_FLAGS = {
            'en-US': '🇺🇸', 'en-GB': '🇬🇧', 'en-CA': '🇨🇦', 'en-AU': '🇦🇺',
            'en-IN': '🇮🇳', 'it-IT': '🇮🇹', 'es-ES': '🇪🇸', 'pt-BR': '🇧🇷',
            'fr-FR': '🇫🇷', 'fr-CA': '🇨🇦', 'de-DE': '🇩🇪', 'ja-JP': '🇯🇵', 'zh-CN': '🇨🇳'
        };
HTMLMID2

cat >> "$OUTPUT" << 'HTMLFOOT'

        // Initialize
        document.addEventListener('DOMContentLoaded', function() {
            allCards = Array.from(document.querySelectorAll('.card'));
            images = allCards.map(card => card.querySelector('img'));
            
            // Extract unique months from cards
            const monthSet = new Set();
            allCards.forEach(card => {
                if (card.dataset.month) {
                    monthSet.add(card.dataset.month);
                }
            });
            months = Array.from(monthSet).sort().reverse(); // Newest first

            buildMonthNavigation();
            buildMarketFilter();
            
            // Auto-select current month
            const now = new Date();
            const currentYear = now.getFullYear();
            const currentMonthNum = String(now.getMonth() + 1).padStart(2, '0');
            const currentMonthKey = `${currentYear}-${currentMonthNum}`;
            
            // Select current month if it exists, otherwise select the newest available month
            if (months.includes(currentMonthKey)) {
                selectMonth(currentMonthKey);
            } else if (months.length > 0) {
                selectMonth(months[0]); // Select newest month
            } else {
                filterGallery();
            }
        });

        function buildMonthNavigation() {
            const navContainer = document.getElementById('monthNavigation');
            
            let html = '<h3>📅 Browse by Month</h3><div class="month-breadcrumbs">';
            
            // "All" button
            html += `<button class="month-breadcrumb active" onclick="selectMonth('all')">All Images<span class="month-count">(${allCards.length})</span></button>`;
            
            // Month buttons
            months.forEach(month => {
                const [year, monthNum] = month.split('-');
                const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 
                                   'July', 'August', 'September', 'October', 'November', 'December'];
                const monthName = monthNames[parseInt(monthNum) - 1];
                const count = allCards.filter(card => card.dataset.month === month).length;
                
                html += `<button class="month-breadcrumb" data-month="${month}" onclick="selectMonth('${month}')">${monthName} ${year}<span class="month-count">(${count})</span></button>`;
            });
            
            html += '</div>';
            navContainer.innerHTML = html;
        }

        function selectMonth(month) {
            currentMonth = month;
            
            // Update active state
            document.querySelectorAll('.month-breadcrumb').forEach(btn => {
                btn.classList.remove('active');
            });
            
            if (month === 'all') {
                document.querySelector('.month-breadcrumb').classList.add('active');
            } else {
                document.querySelector(`.month-breadcrumb[data-month="${month}"]`).classList.add('active');
            }
            
            filterGallery();
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }


        function buildMarketFilter() {
            const select = document.getElementById('marketFilter');

            // Extract unique markets from cards
            const marketSet = new Set();
            allCards.forEach(card => {
                if (card.dataset.market && card.dataset.market !== 'Unknown') {
                    marketSet.add(card.dataset.market);
                }
            });

            const sortedMarkets = Array.from(marketSet).sort();
            sortedMarkets.forEach(market => {
                const option = document.createElement('option');
                option.value = market;
                const flag = MARKET_FLAGS[market] || '🌐';
                option.textContent = `${flag} ${MARKET_NAMES[market] || market}`;
                select.appendChild(option);
            });
        }

        function filterGallery() {
            const query = document.getElementById('searchInput').value.toLowerCase();
            const market = document.getElementById('marketFilter').value;
            let visible = 0;

            allCards.forEach(card => {
                const title = card.dataset.title.toLowerCase();
                const copyright = card.dataset.copyright.toLowerCase();
                const date = card.dataset.date.toLowerCase();
                const cardMonth = card.dataset.month;
                const cardMarket = card.dataset.market;

                // Check month filter
                const monthMatch = currentMonth === 'all' || cardMonth === currentMonth;

                // Check market filter
                const marketMatch = market === 'all' || cardMarket === market;

                // Check search query
                const searchMatch = !query.trim() ||
                                   title.includes(query) ||
                                   copyright.includes(query) ||
                                   date.includes(query);

                if (monthMatch && marketMatch && searchMatch) {
                    card.style.display = 'block';
                    visible++;
                } else {
                    card.style.display = 'none';
                }
            });

            // Show/hide no results message
            const noResults = document.getElementById('noResults');
            if (visible === 0) {
                noResults.classList.add('show');
            } else {
                noResults.classList.remove('show');
            }

            // Update counter
            const marketLabel = market === 'all' ? '' : ` in ${market}`;
            const monthLabel = currentMonth === 'all' ? '' : ` (${currentMonth})`;
            document.getElementById('resultsCount').textContent =
                `Showing ${visible} of ${allCards.length} images${marketLabel}${monthLabel}`;
        }

        function resetFilter() {
            document.getElementById('searchInput').value = '';
            document.getElementById('marketFilter').value = 'all';
            selectMonth('all');
        }

        function openLightboxFromCard(imgElement) {
            const card = imgElement.closest('.card');
            const fullSrc = card.dataset.full;
            const title = card.dataset.title;
            const copyright = card.dataset.copyright;
            const date = card.dataset.date;
            const market = card.dataset.market;
            openLightbox(fullSrc, title, copyright, date, market);
        }

        function openLightbox(src, title, copyright, date, market) {
            const lightbox = document.getElementById('lightbox');
            const lightboxImg = document.getElementById('lightboxImg');

            lightboxImg.src = src;
            document.getElementById('lightboxTitle').textContent = title;
            document.getElementById('lightboxCopyright').textContent = copyright;
            document.getElementById('lightboxDate').textContent = date;
            const marketEl = document.getElementById('lightboxMarket');
            if (market && market !== 'Unknown') {
                const flag = MARKET_FLAGS[market] || '🌐';
                marketEl.textContent = `${flag} ${MARKET_NAMES[market] || market}`;
            } else {
                marketEl.textContent = '';
            }
            document.getElementById('downloadBtn').href = src;

            // Find the card that was clicked using full URL
            const visibleCards = allCards.filter(card => card.style.display !== 'none');
            let clickedIndex = 0;
            
            visibleCards.forEach((c, idx) => {
                if (c.dataset.full === src) {
                    clickedIndex = idx;
                }
            });

            currentImageIndex = clickedIndex;
            images = visibleCards;

            lightbox.classList.add('active');
            document.body.style.overflow = 'hidden';
        }

        function closeLightbox() {
            document.getElementById('lightbox').classList.remove('active');
            document.body.style.overflow = '';
        }

        function navigateLightbox(direction) {
            const visibleCards = allCards.filter(card => card.style.display !== 'none');
            currentImageIndex += direction;
            if (currentImageIndex < 0) currentImageIndex = visibleCards.length - 1;
            if (currentImageIndex >= visibleCards.length) currentImageIndex = 0;

            const card = visibleCards[currentImageIndex];
            const img = card.querySelector('img');

            openLightbox(
                card.dataset.full,
                card.dataset.title,
                card.dataset.copyright,
                card.dataset.date,
                card.dataset.market
            );
        }

        function openFullImage() {
            const src = document.getElementById('lightboxImg').src;
            const title = document.getElementById('lightboxTitle').textContent;
            const copyright = document.getElementById('lightboxCopyright').textContent;

            // GitHub Releases forces download via Content-Disposition header.
            // Open a wrapper page with the image embedded to bypass this.
            const html = `<!DOCTYPE html><html><head><title>${title}</title><meta name="viewport" content="width=device-width,initial-scale=1"><style>*{margin:0;padding:0}body{background:#000;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;color:#fff;font-family:sans-serif;padding:20px}img{max-width:100%;max-height:90vh;object-fit:contain}.info{text-align:center;margin-top:15px;opacity:0.8;font-size:14px}</style></head><body><img src="${src}" alt="${title}"><div class="info"><strong>${title}</strong><br>${copyright}</div></body></html>`;

            const w = window.open('', '_blank');
            if (w) {
                w.document.write(html);
                w.document.close();
            } else {
                // Popup blocked fallback
                window.location.href = src;
            }
        }

        function copyImageUrl() {
            const src = document.getElementById('lightboxImg').src;
            navigator.clipboard.writeText(src).then(() => {
                showToast('Image URL copied to clipboard!');
            }).catch(() => {
                // Fallback for older browsers
                const ta = document.createElement('textarea');
                ta.value = src;
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
                showToast('Image URL copied!');
            });
        }

        function copyImageInfo() {
            const title = document.getElementById('lightboxTitle').textContent;
            const copyright = document.getElementById('lightboxCopyright').textContent;
            const date = document.getElementById('lightboxDate').textContent;
            const market = document.getElementById('lightboxMarket').textContent;
            const parts = [title, copyright, date];
            if (market) parts.push(market);
            const info = parts.join('\n');
            navigator.clipboard.writeText(info).then(() => {
                showToast('Image info copied!');
            }).catch(() => {
                const ta = document.createElement('textarea');
                ta.value = info;
                document.body.appendChild(ta);
                ta.select();
                document.execCommand('copy');
                document.body.removeChild(ta);
                showToast('Image info copied!');
            });
        }

        function shareImage() {
            const title = document.getElementById('lightboxTitle').textContent;
            const src = document.getElementById('lightboxImg').src;

            if (navigator.share) {
                navigator.share({ title: title, url: src }).catch(() => {});
            } else {
                copyImageUrl();
            }
        }

        function showToast(message) {
            const existing = document.querySelector('.toast-notification');
            if (existing) existing.remove();

            const toast = document.createElement('div');
            toast.className = 'toast-notification';
            toast.textContent = message;
            document.body.appendChild(toast);
            setTimeout(() => toast.classList.add('show'), 10);
            setTimeout(() => {
                toast.classList.remove('show');
                setTimeout(() => toast.remove(), 300);
            }, 2000);
        }

        // Keyboard navigation
        document.addEventListener('keydown', function(e) {
            const lightbox = document.getElementById('lightbox');
            if (!lightbox.classList.contains('active')) return;

            if (e.key === 'Escape') closeLightbox();
            if (e.key === 'ArrowLeft') navigateLightbox(-1);
            if (e.key === 'ArrowRight') navigateLightbox(1);
        });

        // Close lightbox when clicking outside
        document.getElementById('lightbox').addEventListener('click', function(e) {
            if (e.target === this) closeLightbox();
        });
    </script>
</body>
</html>
HTMLFOOT

echo "✅ Gallery generated: $OUTPUT"
echo ""
echo "🌐 To open the gallery:"
echo "   Linux:   xdg-open \"$OUTPUT\""
echo "   macOS:   open \"$OUTPUT\""
echo "   Windows: start \"$OUTPUT\""
echo ""

exit 0
