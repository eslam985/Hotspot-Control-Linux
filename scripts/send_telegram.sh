#!/bin/bash
# /home/es/projects/hotspot-control/scripts/send_telegram.sh

# قراءة المتغيرات من ملف البيئة مباشرة
ENV_FILE="/home/es/projects/hotspot-control/.env"

if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Error: .env file not found"
    exit 1
fi

# تعيين التوكن من المتغير المقروء
TOKEN=$TELEGRAM_TOKEN
CHAT_ID=$1
MESSAGE=$2

if [ -z "$CHAT_ID" ] || [ -z "$MESSAGE" ] || [ -z "$TOKEN" ]; then exit 1; fi

# إرسال الطلب في الخلفية وصمت تام
curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${MESSAGE}" > /dev/null 2>&1
