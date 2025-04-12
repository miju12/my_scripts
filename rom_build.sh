#!/bin/bash

# ========== CONFIG ==========
CONFIG_FILE=".build_config"
CHAT_ID=""
BOT_TOKEN=""
DEVICE_CODE=""
PD_API=""
DEVICE_TREE=""
BUILD_TYPE=""
# ============================

function save_config() {
    cat <<EOF > $CONFIG_FILE
CHAT_ID="$CHAT_ID"
BOT_TOKEN="$BOT_TOKEN"
DEVICE_CODE="$DEVICE_CODE"
PD_API="$PD_API"
DEVICE_TREE="$DEVICE_TREE"
BUILD_TYPE="$BUILD_TYPE"
EOF
}

function load_config() {
    if [[ -f $CONFIG_FILE ]]; then
        echo "⚙️ Config file found."
        read -p "Use previous saved configuration? (y/n): " use_saved
        if [[ "$use_saved" == "y" ]]; then
            source $CONFIG_FILE
            # Safety net: prompt if BUILD_TYPE is missing
            if [[ -z "$BUILD_TYPE" ]]; then
                echo "⚠️ BUILD_TYPE missing in saved config. Please reconfigure build settings."
                read -p "Enter device code (e.g. sky): " DEVICE_CODE
                read -p "Enter device tree path (e.g. device/xiaomi/sky): " DEVICE_TREE
                echo "Select build type:"
                select btype in "user" "userdebug" "eng"; do
                    [[ -n "$btype" ]] && BUILD_TYPE="$btype" && break
                done
                save_config
            fi
            echo "✅ Using saved config."
            return
        else
            echo "🔄 Choose what to update:"
            echo "1) Telegram settings only"
            echo "2) Build settings only"
            echo "3) Both"
            read -p "Enter your choice (1/2/3): " config_choice

            [[ "$config_choice" == "1" || "$config_choice" == "3" ]] && {
                read -p "Enter Telegram Chat ID: " CHAT_ID
                read -p "Enter Telegram Bot Token: " BOT_TOKEN
                read -p "Enter PixelDrain API Key: " PD_API
            }

            [[ "$config_choice" == "2" || "$config_choice" == "3" ]] && {
                read -p "Enter device code (e.g. sky): " DEVICE_CODE
                read -p "Enter device tree path (e.g. device/xiaomi/sky): " DEVICE_TREE
                echo "Select build type:"
                select btype in "user" "userdebug" "eng"; do
                    [[ -n "$btype" ]] && BUILD_TYPE="$btype" && break
                done
            }

            save_config
            echo "✅ Config updated."
        fi
    else
        echo "⚙️ First time setup:"
        read -p "Enter Telegram Chat ID: " CHAT_ID
        read -p "Enter Telegram Bot Token: " BOT_TOKEN
        read -p "Enter PixelDrain API Key: " PD_API
        read -p "Enter device code (e.g. sky): " DEVICE_CODE
        read -p "Enter device tree path (e.g. device/xiaomi/sky): " DEVICE_TREE
        echo "Select build type:"
        select btype in "user" "userdebug" "eng"; do
            [[ -n "$btype" ]] && BUILD_TYPE="$btype" && break
        done
        save_config
        echo "✅ Config saved."
    fi
}

function send_message() {
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
         -d chat_id="$CHAT_ID" \
         -d text="$1" \
         -d parse_mode="HTML"
}

function upload_pixeldrain() {
    RESPONSE=$(curl -s -T "$1" -u :"$PD_API" https://pixeldrain.com/api/file/)
    echo "$RESPONSE" | grep -Po '(?<=id":")[^"]*' | awk '{print "https://pixeldrain.com/u/" $1}'
}

function upload_gofile() {
    RESPONSE=$(curl -s -F "file=@$1" https://store1.gofile.io/uploadFile)
    echo "$RESPONSE" | grep -oP '(?<="downloadPage":")[^"]*'
}

function md5() {
    md5sum "$1" | awk '{print $1}'
}

function find_rom_zip() {
    find "out/target/product/$DEVICE_CODE" -type f -name "*.zip" -printf "%T@ %p\n" 2>/dev/null | sort -n | tail -n 1 | cut -d' ' -f2-
}

function find_changelog() {
    find "out/target/product/$DEVICE_CODE" -iname "*changelog*.txt" | head -n 1
}

# ===== MAIN BUILD FLOW =====

load_config
send_message "🔧 Starting build for <code>$DEVICE_CODE</code> (<code>$BUILD_TYPE</code>)..."

read -p "Run repo sync before build? (y/n): " sync_choice
[[ "$sync_choice" == "y" ]] && repo sync -c --force-sync --no-tags --no-clone-bundle -j$(nproc)

source build/envsetup.sh
lunch lineage_"$DEVICE_CODE"-bp1a-$BUILD_TYPE
make installclean

BUILD_START=$(date +%s)

( make bacon -j$(nproc) 2>&1 | tee build.log ) &
sleep 600
while pgrep -f "make -j" >/dev/null; do
    PERCENT=$(grep -oP "\[\s*\K\d+(?=%)" build.log | tail -n 1)
    PERCENT=${PERCENT:-unknown}
    send_message "🛠️ Build progress: <b>$PERCENT%</b>"
    sleep 600
done

wait
BUILD_END=$(date +%s)
BUILD_DURATION=$(( (BUILD_END - BUILD_START) / 60 ))

ROM_ZIP=$(find_rom_zip)

if [[ -f "$ROM_ZIP" ]]; then
    CHANGELOG=$(find_changelog)
    ROM_NAME=$(basename "$ROM_ZIP")
    ROM_SIZE=$(du -sh "$ROM_ZIP" | cut -f1)
    ROM_MD5=$(md5 "$ROM_ZIP")

    PD_LINK=$(upload_pixeldrain "$ROM_ZIP")
    GOFILE_LINK=$(upload_gofile "$ROM_ZIP")
    [[ -z "$PD_LINK" ]] && PD_LINK="(PixelDrain upload failed)"
    [[ -z "$GOFILE_LINK" ]] && GOFILE_LINK="(Gofile upload failed)"

    CHANGELOG_PREVIEW=$(head -n 20 "$CHANGELOG" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')

    MESSAGE="✅ <b>Build Completed</b>

📱 <b>Device:</b> <code>$DEVICE_CODE</code>
⚙️ <b>Type:</b> <code>$BUILD_TYPE</code>
📦 <b>Filename:</b> <code>$ROM_NAME</code>
📏 <b>Size:</b> $ROM_SIZE
🔐 <b>MD5:</b> <code>$ROM_MD5</code>
🕒 <b>Time:</b> ${BUILD_DURATION} minutes

📤 <b>Download Links:</b>
🔹 <a href=\"$PD_LINK\">PixelDrain</a>
🔹 <a href=\"$GOFILE_LINK\">Gofile.io</a>

<pre>$CHANGELOG_PREVIEW</pre>
<i>📄 Full changelog attached below.</i>"

    send_message "$MESSAGE"

    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
         -F chat_id="$CHAT_ID" \
         -F document=@"$CHANGELOG" \
         -F caption="📄 <b>Full changelog for $ROM_NAME</b>" \
         -F parse_mode="HTML"
else
    send_message "❌ <b>Build failed</b> for <code>$DEVICE_CODE</code>. No ROM zip found."
fi

# ===== OPTIONAL POWEROFF =====
read -p "Power off system after build? (y/n): " poff
[[ "$poff" == "y" ]] && poweroff
