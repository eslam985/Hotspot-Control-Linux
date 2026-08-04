#!/bin/bash

# --- الإعدادات الموحدة الجديدة ---
IFACE="wlp3s0"
# المسار الموحد داخل نظام لينكس
BASE_DIR="/home/es/projects/hotspot-control/data"
SPEED_FILE="$BASE_DIR/speeds.conf"

LAST_MD5=""
cleanup() {
    echo -e "\n[!] Cleaning Speed Limits..."
    sudo tc qdisc del dev $IFACE root 2>/dev/null
    sudo tc qdisc del dev $IFACE handle ffff: ingress 2>/dev/null
    sudo tc qdisc del dev ifb0 root 2>/dev/null
    exit
}
trap cleanup SIGINT SIGTERM

apply_speeds() {
    echo "[*] Changes detected! Applying new speed limits..."
    
    sudo tc qdisc del dev $IFACE root 2>/dev/null
    sudo tc qdisc del dev $IFACE handle ffff: ingress 2>/dev/null
    sudo tc qdisc del dev ifb0 root 2>/dev/null

    sudo modprobe ifb numifbs=1 2>/dev/null
    sudo ip link set dev ifb0 up 2>/dev/null
    sudo tc qdisc add dev $IFACE root handle 1: htb default 10
    sudo tc qdisc add dev $IFACE handle ffff: ingress
    sudo tc filter add dev $IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    sudo tc qdisc add dev ifb0 root handle 1: htb default 10

    while IFS='=' read -r IP CONFIG || [ -n "$IP" ]; do
        # تنظيف السطر من أي مسافات زائدة وتجاهل التعليقات
        IP=$(echo "$IP" | tr -d '[:space:]')
        [[ -z "$IP" ]] && continue
        [[ "$IP" == "#"* ]] && continue
        
        IFS=':' read -r DL UL <<< "$CONFIG"
        
        ID=$(echo "$IP" | cut -d'.' -f4)
        
        # تحميل (Download)
        sudo tc class add dev "$IFACE" parent 1: classid "1:$ID" htb rate "$DL" ceil "$DL"
        sudo tc filter add dev "$IFACE" protocol ip parent 1: prio "$ID" u32 match ip dst "$IP/32" flowid "1:$ID"
        
        # رفع (Upload)
        sudo tc class add dev ifb0 parent 1: classid "1:$ID" htb rate "$UL" ceil "$UL"
        sudo tc filter add dev ifb0 protocol ip parent 1: prio "$ID" u32 match ip src "$IP/32" flowid "1:$ID"
        
        echo "[+] Applied for $IP -> DL: $DL | UL: $UL"
    done < "$SPEED_FILE"
}

echo "Speed Limiter Active (Watching speeds.conf for changes...)"

while true; do
    if [ -f "$SPEED_FILE" ]; then
        CURRENT_MD5=$(md5sum "$SPEED_FILE" | awk '{print $1}')
        if [ "$CURRENT_MD5" != "$LAST_MD5" ]; then
            apply_speeds
            LAST_MD5=$CURRENT_MD5
        fi
    fi
    sleep 5
done
