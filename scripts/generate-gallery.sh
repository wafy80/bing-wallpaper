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

WALLPAPER_DIR="${WALLPAPER_DIR:-docs}"
OUTPUT="$WALLPAPER_DIR/index.html"
THUMB_DIR="$WALLPAPER_DIR/thumbs"
THUMB_SIZE="${THUMB_SIZE:-300}"
LAST_UPDATED=$(date +"%d/%m/%Y, %H:%M")

# Month names for breadcrumbs
MONTH_NAMES=("January" "February" "March" "April" "May" "June" "July" "August" "September" "October" "November" "December")

# Release configuration
RELEASE_BASE_URL="https://github.com/wafy80/bing-wallpaper/releases/download/wallpapers-archive"

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
    echo "https://github.com/wafy80/bing-wallpaper/releases/download/${RELEASE_PREFIX}-${month_key}/${filename}"
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

        /* ── Accordion Navigation ───────────────────────────────────────── */
        .accordion-nav {
            max-width: 1400px;
            margin: 0 auto 30px;
        }

        /* Year level */
        .year-section {
            margin-bottom: 12px;
            border-radius: 12px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0,0,0,0.25);
        }

        .year-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 16px 24px;
            background: linear-gradient(135deg, var(--primary), var(--primary-dark));
            color: white;
            cursor: pointer;
            user-select: none;
            transition: background 0.25s ease;
        }

        .year-header:hover {
            background: linear-gradient(135deg, var(--primary-dark), #004080);
        }

        .year-header h2 {
            margin: 0;
            font-size: 1.35em;
            font-weight: 700;
            letter-spacing: 0.5px;
        }

        .year-header-right {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .year-count {
            font-size: 0.88em;
            opacity: 0.85;
            background: rgba(255,255,255,0.15);
            padding: 3px 10px;
            border-radius: 20px;
        }

        .accordion-chevron {
            font-size: 1.1em;
            transition: transform 0.3s ease;
            display: inline-block;
        }

        .year-section.open > .year-header .accordion-chevron,
        .month-section.open > .month-header .accordion-chevron {
            transform: rotate(180deg);
        }

        .year-body {
            background: var(--card-bg);
            max-height: 0;
            overflow: hidden;
            transition: max-height 0.4s ease;
        }

        .year-section.open > .year-body {
            /* 20000px is intentionally large (max-height CSS transition trick):
               the browser animates 0→N where N must exceed actual content height.
               Closing (N→0) is smooth; opening feels instant, which is the desired UX. */
            max-height: 20000px;
            transition: max-height 0.6s ease;
        }

        .year-body-inner {
            padding: 16px 20px 20px;
            display: flex;
            flex-direction: column;
            gap: 10px;
        }

        /* Month level */
        .month-section {
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        }

        .month-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 20px;
            background: var(--bg);
            color: var(--text);
            cursor: pointer;
            user-select: none;
            border: 2px solid transparent;
            transition: all 0.25s ease;
        }

        .month-header:hover {
            background: var(--primary);
            color: white;
        }

        .month-section.open > .month-header {
            background: var(--primary);
            color: white;
            border-color: var(--primary-dark);
        }

        .month-header h3 {
            margin: 0;
            font-size: 1.05em;
            font-weight: 600;
        }

        .month-header-right {
            display: flex;
            align-items: center;
            gap: 10px;
        }

        .month-count-badge {
            font-size: 0.82em;
            opacity: 0.85;
        }

        .month-body {
            max-height: 0;
            overflow: hidden;
            transition: max-height 0.4s ease;
        }

        .month-section.open > .month-body {
            max-height: 10000px;
            transition: max-height 0.5s ease;
        }

        /* Image grid inside month */
        .month-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
            gap: 25px;
            padding: 20px;
            background: rgba(0,0,0,0.15);
        }

        @media (max-width: 768px) {
            .month-grid { grid-template-columns: repeat(auto-fill, minmax(280px, 1fr)); gap: 15px; padding: 12px; }
            .year-header h2 { font-size: 1.1em; }
            .year-header { padding: 14px 16px; }
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
        <button class="filter-btn" onclick="expandAll()">🔄 Show All</button>
    </div>

    <div class="gallery-info">
        <span id="resultsCount"></span>
        <span>Last updated: $LAST_UPDATED</span>
    </div>

    <div class="no-results" id="noResults">
        <h2>😕 No images found</h2>
        <p>Try modifying your search terms</p>
    </div>

    <!-- Hidden card pool — JS reads data-* from here, then moves cards into accordion -->
    <div id="cardPool" style="display:none;">
HTMLMID

# Generate cards by month
generate_cards_by_month >> "$OUTPUT"

cat >> "$OUTPUT" << 'HTMLMID2'
    </div><!-- end #cardPool -->

    <!-- Three-level accordion: Year > Month > Images -->
    <div class="accordion-nav" id="accordionNav"></div>

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
        let allCards = [];      // all card elements (from pool)
        let visibleCards = [];  // cards currently shown (after filter)

        const MARKET_NAMES = {
            'en-US': 'United States', 'en-GB': 'United Kingdom', 'en-CA': 'Canada',
            'fr-CA': 'Canada', 'es-ES': 'Spain', 'fr-FR': 'France',
            'de-DE': 'Germany', 'it-IT': 'Italy', 'ja-JP': 'Japan', 'zh-CN': 'China',
            'pt-BR': 'Brazil', 'pt-PT': 'Portugal', 'en-IN': 'India', 'en-AU': 'Australia',
            'es-MX': 'Mexico', 'nl-NL': 'Netherlands', 'ru-RU': 'Russia', 'ko-KR': 'Korea'
        };

        const MARKET_FLAGS = {
            'en-US': '🇺🇸', 'en-GB': '🇬🇧', 'en-CA': '🇨🇦', 'fr-CA': '🇨🇦',
            'es-ES': '🇪🇸', 'fr-FR': '🇫🇷', 'de-DE': '🇩🇪', 'it-IT': '🇮🇹',
            'ja-JP': '🇯🇵', 'zh-CN': '🇨🇳', 'pt-BR': '🇧🇷', 'pt-PT': '🇵🇹',
            'en-IN': '🇮🇳', 'en-AU': '🇦🇺', 'es-MX': '🇲🇽', 'nl-NL': '🇳🇱',
            'ru-RU': '🇷🇺', 'ko-KR': '🇰🇷'
        };
HTMLMID2

cat >> "$OUTPUT" << 'HTMLFOOT'

        // ── Month name helper ──────────────────────────────────────────────
        const MONTH_NAMES_JS = ['January','February','March','April','May','June',
                                'July','August','September','October','November','December'];

        // ── Initialize ─────────────────────────────────────────────────────
        document.addEventListener('DOMContentLoaded', function() {
            // Collect cards from the hidden pool
            allCards = Array.from(document.querySelectorAll('#cardPool .card'));

            buildMarketFilter();
            buildAccordion();

            // Re-index allCards from the rendered accordion so lightbox navigation
            // order matches the visual Year→Month→Image order exactly.
            allCards = Array.from(document.querySelectorAll('#accordionNav .card'));

            // Auto-open the most recent year and its most recent month
            const firstYear = document.querySelector('.year-section');
            if (firstYear) {
                openSection(firstYear);
                const firstMonth = firstYear.querySelector('.month-section');
                if (firstMonth) openSection(firstMonth);
            }

            filterGallery();
        });

        // ── Build accordion ────────────────────────────────────────────────
        function buildAccordion() {
            // Group cards by year → month (sorted newest first)
            const yearMap = new Map(); // year -> Map(month -> [cards])
            allCards.forEach(card => {
                const m = card.dataset.month || 'unknown-00';
                const [year, monthNum] = m.split('-');
                if (!yearMap.has(year)) yearMap.set(year, new Map());
                if (!yearMap.get(year).has(m)) yearMap.get(year).set(m, []);
                yearMap.get(year).get(m).push(card);
            });

            // Sort years newest first
            const sortedYears = Array.from(yearMap.keys()).sort().reverse();
            const nav = document.getElementById('accordionNav');
            nav.innerHTML = '';

            sortedYears.forEach(year => {
                const monthMap = yearMap.get(year);
                const sortedMonths = Array.from(monthMap.keys()).sort().reverse();
                const yearCount = sortedMonths.reduce((s, m) => s + monthMap.get(m).length, 0);

                // Year section
                const yearSection = document.createElement('div');
                yearSection.className = 'year-section';
                yearSection.dataset.year = year;

                // Year header
                const yearHeader = document.createElement('div');
                yearHeader.className = 'year-header';
                yearHeader.innerHTML = `
                    <h2>📅 ${year}</h2>
                    <div class="year-header-right">
                        <span class="year-count" data-year-count="${year}">${yearCount} images</span>
                        <span class="accordion-chevron">▼</span>
                    </div>`;
                yearHeader.addEventListener('click', () => toggleSection(yearSection));

                // Year body
                const yearBody = document.createElement('div');
                yearBody.className = 'year-body';
                const yearBodyInner = document.createElement('div');
                yearBodyInner.className = 'year-body-inner';

                sortedMonths.forEach(monthKey => {
                    const cards = monthMap.get(monthKey);
                    const [, monthNum] = monthKey.split('-');
                    const monthName = MONTH_NAMES_JS[parseInt(monthNum, 10) - 1] || monthKey;

                    // Month section
                    const monthSection = document.createElement('div');
                    monthSection.className = 'month-section';
                    monthSection.dataset.month = monthKey;

                    // Month header
                    const monthHeader = document.createElement('div');
                    monthHeader.className = 'month-header';
                    monthHeader.innerHTML = `
                        <h3>${monthName} ${year}</h3>
                        <div class="month-header-right">
                            <span class="month-count-badge" data-month-count="${monthKey}">${cards.length} images</span>
                            <span class="accordion-chevron">▼</span>
                        </div>`;
                    monthHeader.addEventListener('click', () => toggleSection(monthSection));

                    // Month body + grid
                    const monthBody = document.createElement('div');
                    monthBody.className = 'month-body';
                    const grid = document.createElement('div');
                    grid.className = 'month-grid';
                    grid.dataset.monthGrid = monthKey;

                    // Move cards into grid
                    cards.forEach(card => {
                        card.style.display = '';
                        grid.appendChild(card);
                    });

                    monthBody.appendChild(grid);
                    monthSection.appendChild(monthHeader);
                    monthSection.appendChild(monthBody);
                    yearBodyInner.appendChild(monthSection);
                });

                yearBody.appendChild(yearBodyInner);
                yearSection.appendChild(yearHeader);
                yearSection.appendChild(yearBody);
                nav.appendChild(yearSection);
            });
        }

        // ── Accordion toggle helpers ───────────────────────────────────────
        function openSection(el) {
            el.classList.add('open');
        }

        function closeSection(el) {
            el.classList.remove('open');
        }

        function toggleSection(el) {
            el.classList.toggle('open');
        }

        // ── Market filter builder ──────────────────────────────────────────
        function buildMarketFilter() {
            const select = document.getElementById('marketFilter');

            const marketGroups = new Map();
            allCards.forEach(card => {
                const marketCode = card.dataset.market;
                if (marketCode && marketCode !== 'Unknown') {
                    const displayName = MARKET_NAMES[marketCode] || marketCode;
                    if (!marketGroups.has(displayName)) marketGroups.set(displayName, []);
                    marketGroups.get(displayName).push(marketCode);
                }
            });

            Array.from(marketGroups.keys()).sort().forEach(displayName => {
                const option = document.createElement('option');
                const firstCode = marketGroups.get(displayName)[0];
                const flag = MARKET_FLAGS[firstCode] || '🌐';
                option.value = displayName;
                option.textContent = `${flag} ${displayName}`;
                select.appendChild(option);
            });
        }

        // ── Filter across all cards ────────────────────────────────────────
        function filterGallery() {
            const query = document.getElementById('searchInput').value.toLowerCase().trim();
            const marketDisplayName = document.getElementById('marketFilter').value;
            let visible = 0;

            allCards.forEach(card => {
                const title = (card.dataset.title || '').toLowerCase();
                const copyright = (card.dataset.copyright || '').toLowerCase();
                const date = (card.dataset.date || '').toLowerCase();
                const cardMarketCode = card.dataset.market;

                const marketMatch = marketDisplayName === 'all' ||
                    (cardMarketCode && MARKET_NAMES[cardMarketCode] === marketDisplayName);

                const searchMatch = !query ||
                    title.includes(query) ||
                    copyright.includes(query) ||
                    date.includes(query);

                const show = marketMatch && searchMatch;
                card.style.display = show ? '' : 'none';
                if (show) visible++;
            });

            // Update per-month and per-year counts
            document.querySelectorAll('.month-section').forEach(ms => {
                const monthKey = ms.dataset.month;
                const grid = ms.querySelector('.month-grid');
                if (!grid) return;
                const cnt = Array.from(grid.querySelectorAll('.card')).filter(c => c.style.display !== 'none').length;
                const badge = document.querySelector(`[data-month-count="${monthKey}"]`);
                if (badge) badge.textContent = `${cnt} image${cnt !== 1 ? 's' : ''}`;
            });

            document.querySelectorAll('.year-section').forEach(ys => {
                const yr = ys.dataset.year;
                const cnt = Array.from(ys.querySelectorAll('.card')).filter(c => c.style.display !== 'none').length;
                const badge = document.querySelector(`[data-year-count="${yr}"]`);
                if (badge) badge.textContent = `${cnt} image${cnt !== 1 ? 's' : ''}`;
            });

            // Show/hide no-results banner
            const noResults = document.getElementById('noResults');
            noResults.classList.toggle('show', visible === 0);

            // Update results counter
            const marketLabel = marketDisplayName === 'all' ? '' : ` in ${marketDisplayName}`;
            document.getElementById('resultsCount').textContent =
                `Showing ${visible} of ${allCards.length} images${marketLabel}`;
        }

        function expandAll() {
            // Clear all filters
            document.getElementById('searchInput').value = '';
            document.getElementById('marketFilter').value = 'all';
            filterGallery();
            // Expand every year and month section
            document.querySelectorAll('.year-section, .month-section').forEach(openSection);
            window.scrollTo({ top: 0, behavior: 'smooth' });
        }

        function openLightboxFromCard(imgElement) {
            const card = imgElement.closest('.card');
            openLightbox(
                card.dataset.full,
                card.dataset.title,
                card.dataset.copyright,
                card.dataset.date,
                card.dataset.market
            );
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

            // Build ordered visible card list from the DOM (preserves year→month→image order)
            visibleCards = allCards.filter(c => c.style.display !== 'none');
            currentImageIndex = visibleCards.findIndex(c => c.dataset.full === src);
            if (currentImageIndex < 0) currentImageIndex = 0;

            lightbox.classList.add('active');
            document.body.style.overflow = 'hidden';
        }

        function closeLightbox() {
            document.getElementById('lightbox').classList.remove('active');
            document.body.style.overflow = '';
        }

        function navigateLightbox(direction) {
            visibleCards = allCards.filter(c => c.style.display !== 'none');
            currentImageIndex += direction;
            if (currentImageIndex < 0) currentImageIndex = visibleCards.length - 1;
            if (currentImageIndex >= visibleCards.length) currentImageIndex = 0;

            const card = visibleCards[currentImageIndex];
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
