#!/bin/bash
# Set PATH to include common Linux directories
PATH=/usr/bin:/bin:/usr/local/bin:$PATH

echo "[+] Starting PlayIntegrityFix Script"
printf "\n\n"

download() { wget -T 10 --no-check-certificate -qO - "$1"; }
if command -v curl > /dev/null 2>&1; then
    download() { curl --connect-timeout 10 -s "$1"; }
fi

sleep_pause() {
    sleep 5
}

set_random_beta() {
    if [ "$(echo "$MODEL_LIST" | wc -l)" -ne "$(echo "$PRODUCT_LIST" | wc -l)" ]; then
        echo "Error: MODEL_LIST and PRODUCT_LIST have different lengths."
        sleep_pause
        exit 1
    fi
    count=$(echo "$MODEL_LIST" | wc -l)
    rand_index=$(( $$ % count ))
    MODEL=$(echo "$MODEL_LIST" | sed -n "$((rand_index + 1))p")
    PRODUCT=$(echo "$PRODUCT_LIST" | sed -n "$((rand_index + 1))p")
    DEVICE=$(echo "$PRODUCT" | sed 's/_beta//')
}

download_fail() {
    echo "[!] Download failed!"
    echo "[x] Bailing out!"
    sleep_pause
    exit 1
}

# Function to send a Telegram message
send_telegram_message() {
    local message="$1"
    local bot_token="<YOUR_BOT_TOKEN>"
    local chat_id="<YOUR_CHAT_ID>"
    curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" \
        -d chat_id="$chat_id" \
        -d text="$message" > /dev/null
}

# Step 1: Clone the repository if not already cloned
REPO_DIR="$HOME/android_vendor_certification"
if [ ! -d "$REPO_DIR" ]; then
    git clone https://github.com/miju12/android_vendor_certification.git "$REPO_DIR" || { echo "[!] Failed to clone repository"; exit 1; }
    echo "- Repository cloned into $REPO_DIR"
else
    echo "- Repository already exists at $REPO_DIR"
fi

# Step 2: Create temporary directory for processing
TEMPDIR=$(mktemp -d) || { echo "[!] Failed to create temporary directory"; exit 1; }
cd "$TEMPDIR"

# Fetch data from online sources
download https://developer.android.com/topic/generic-system-image/releases > PIXEL_GSI_HTML || download_fail
grep -m1 -o 'li>.*(Beta)' PIXEL_GSI_HTML | cut -d\> -f2
grep -m1 -o 'Date:.*' PIXEL_GSI_HTML

RELEASE="$(grep -m1 'corresponding Google Pixel builds' PIXEL_GSI_HTML | grep -o '/versions/.*' | cut -d/ -f3)"
ID="$(grep -m1 -o 'Build:.*' PIXEL_GSI_HTML | cut -d' ' -f2)"
INCREMENTAL="$(grep -m1 -o "$ID-.*-" PIXEL_GSI_HTML | cut -d- -f2)"

download "https://developer.android.com$(grep -m1 'corresponding Google Pixel builds' PIXEL_GSI_HTML | grep -o 'href.*' | cut -d\" -f2)" > PIXEL_GET_HTML || download_fail
download "https://developer.android.com$(grep -m1 'Factory images for Google Pixel' PIXEL_GET_HTML | grep -o 'href.*' | cut -d\" -f2)" > PIXEL_BETA_HTML || download_fail

MODEL_LIST="$(grep -A1 'tr id=' PIXEL_BETA_HTML | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')"
PRODUCT_LIST="$(grep -o 'factory/.*_beta' PIXEL_BETA_HTML | cut -d/ -f2)"

download https://source.android.com/docs/security/bulletin/pixel > PIXEL_SECBULL_HTML || download_fail

SECURITY_PATCH="$(grep -A15 "$(grep -m1 -o 'Security patch level:.*' PIXEL_GSI_HTML | cut -d' ' -f4-)" PIXEL_SECBULL_HTML | grep -m1 -B1 '</tr>' | grep 'td' | sed 's;.*<td>\(.*\)</td>;\1;')"

echo "- Selecting Pixel Beta device ..."
[ -z "$PRODUCT" ] && set_random_beta
echo "$MODEL ($PRODUCT)"

# Paths for output files
JSON_FILE="$HOME/gms_certified_props.json"
CONFIG_FILE="$REPO_DIR/overlay/frameworks/base/core/res/res/values/config.xml"

# Step 3: Generate gms_certified_props.json
cat <<EOF > "$JSON_FILE"
{
    "MANUFACTURER": "Google",
    "MODEL": "$MODEL",
    "FINGERPRINT": "google/$PRODUCT/$DEVICE:$RELEASE/$ID/$INCREMENTAL:user/release-keys",
    "BRAND": "google",
    "PRODUCT": "$PRODUCT",
    "DEVICE": "$DEVICE",
    "VERSION.RELEASE": "$RELEASE",
    "ID": "$ID",
    "VERSION.INCREMENTAL": "$INCREMENTAL",
    "TYPE": "user",
    "TAGS": "release-keys",
    "VERSION.SECURITY_PATCH": "$SECURITY_PATCH",
    "VERSION.DEVICE_INITIAL_SDK_INT": "21"
}
EOF
echo "- gms_certified_props.json saved to $JSON_FILE"

# Step 4: Clean up temporary files
rm -rf "$TEMPDIR"
echo "- Temporary files cleaned up."

# Step 5: Commit and push changes to the cloned repository
# The new paths are taken into account below
cp "$JSON_FILE" "$REPO_DIR/gms_certified_props.json"
cd "$REPO_DIR" || { echo "[!] Failed to change to repository directory"; exit 1; }
git add gms_certified_props.json
git commit -m "Update certification props for Pixel Beta: $MODEL ($PRODUCT)"
git push origin 15.0 || { echo "[!] Failed to push changes"; exit 1; }
echo "- Changes pushed to remote repository: git@github.com:miju12/android_vendor_certification.git"

# Step 6: Send the Telegram message
send_telegram_message "We've updated our online certification fingerprint. Clear Play Store data and reboot."
echo "- Telegram message sent."

