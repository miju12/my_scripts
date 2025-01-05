#!/usr/bin/env bash
#
# Upload Files
#

CONFIG_FILE="$HOME/.upload_keys"
TELEGRAM_API="https://api.telegram.org"

# Function to save a key
save_key() {
  local service=$1
  local key=$2
  echo "$service=$key" >> "$CONFIG_FILE"
}

# Function to get a key
get_key() {
  local service=$1
  grep -w "$service" "$CONFIG_FILE" | cut -d '=' -f 2
}

# Function to send message to Telegram
send_to_telegram() {
  local message=$1
  local token=$(get_key "TelegramBotToken")
  local chat_id=$(get_key "TelegramChatID")

  if [ -z "$token" ]; then
    read -p "Please enter Telegram bot token: " token
    save_key "TelegramBotToken" "$token"
  fi

  if [ -z "$chat_id" ]; then
    read -p "Please enter Telegram chat ID: " chat_id
    save_key "TelegramChatID" "$chat_id"
  fi

  curl -s -X POST "$TELEGRAM_API/bot$token/sendMessage" -d chat_id="$chat_id" -d text="$message"
}

echo " "
echo "[1] Github Release [gh auth login]
[2] Devuploads [Key]
[3] pixeldrain [Key]
[4] Gofile
[5] Sourceforge [Key]
"
read -p "Please enter your number: " UP
read -p "Please enter file path/name: " FP

# Check if file exists
if [ ! -f "$FP" ]; then
  echo "File does not exist: $FP"
  exit 1
fi

case $UP in
  1)
    read -p "Please enter GitHub repo link: " GH
    FN="$(basename "$FP")" && FN="${FN%%.*}"
    echo -e "Started uploading file on GitHub..."
    gh release create "$FN" --generate-notes --repo "$GH"
    gh release upload --clobber "$FN" "$FP" --repo "$GH"
    LINK="https://github.com/$GH/releases/tag/$FN"
    ;;
  2)
    KEY=$(get_key "Devuploads")
    if [ -z "$KEY" ]; then
      read -p "Please enter DevUploads key: " KEY
      save_key "Devuploads" "$KEY"
    fi
    echo -e "Started uploading file on DevUploads..."
    UPLOAD_OUTPUT=$(bash <(curl -s https://devuploads.com/upload.sh) -f "$FP" -k "$KEY")
    LINK=$(echo "$UPLOAD_OUTPUT" | grep -oP 'https://devuploads.com/\S+')
    ;;
  3)
    KEY=$(get_key "Pixeldrain")
    if [ -z "$KEY" ]; then
      read -p "Please enter PixelDrain key: " KEY
      save_key "Pixeldrain" "$KEY"
    fi
    echo -e "Started uploading file on PixelDrain..."
    UPLOAD_OUTPUT=$(curl -T "$FP" -u ":$KEY" https://pixeldrain.com/api/file/)
    LINK=$(echo "$UPLOAD_OUTPUT" | jq -r '.url')
    ;;
  4)
    echo -e "Started uploading file on Gofile..."
    SERVER=$(curl -X GET 'https://api.gofile.io/servers' | grep -Po '(store[^"]*)' | tail -n 1)
    UPLOAD_OUTPUT=$(curl -X POST "https://${SERVER}.gofile.io/contents/uploadfile" -F "file=@$FP")
    LINK=$(echo "$UPLOAD_OUTPUT" | grep -Po '(https://gofile.io/d/)[^"]*')
    ;;
  5)
    echo -e "Started uploading file on SourceForge..."
    read -p "Please enter Username: " USER
    read -p "Please enter upload location (Path after /home/frs/project/): " UPL
    scp "$FP" "$USER@frs.sourceforge.net:/home/frs/project/$UPL"
    LINK="https://sourceforge.net/projects/$UPL"
    ;;
  *)
    echo "Invalid option selected."
    exit 1
    ;;
esac

# Send the link to Telegram
send_to_telegram "File uploaded: $LINK"
echo "File uploaded successfully: $LINK"

