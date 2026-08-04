#!/bin/bash
INTERFACE_WIFI="wlp3s0"

INTERFACE_ETH="enp2s0f0"

SSID="Es_Share"

PASS="es123456"

CHAN="1" # القناة 1 غالباً أكثر استقراراً مع AMD # غيرها من 1 إلى 6 أو 11

trap 'echo -e "\n[!] Kill All..."; killall -9 create_ap hostapd dnsmasq 2>/dev/null; pkill -f "speed_limiter" 2>/dev/null; pkill -f "start-quota" 2>/dev/null; nmcli device set $INTERFACE_WIFI managed yes 2>/dev/null; exit' SIGINT SIGTERM SIGHUP EXIT

if [[ $EUID -ne 0 ]]; then
echo "يجب تشغيل السكريبت بـ sudo"
exit 1
fi

if [ -f /tmp/create_ap.${INTERFACE_WIFI}.lock ]; then

echo "نقطة الوصول تعمل بالفعل.. جاري الإيقاف الآن..."
killall -9 create_ap hostapd dnsmasq 2>/dev/null
pkill -f "speed_limiter" 2>/dev/null
pkill -f "watch -n 1 show-quota" 2>/dev/null
nmcli device set $INTERFACE_WIFI managed yes 2>/dev/null
nmcli radio wifi on 2>/dev/null
echo "تم الإيقاف بنجاح."
trap - EXIT # تم إضافة هذا السطر لمنع تكرار الـ trap
exit 0

else

echo "جاري تنظيف العمليات وتجهيز البث..."

# قتل أي نسخة قديمة من المحرك فوراً لمنع تضارب البيانات

pkill -f "start-quota"

pkill -f "tcpdump"

# تنظيف الجداول لضمان عمل الحظر والنت

sudo iptables -F FORWARD

sudo iptables -t raw -F PREROUTING

sudo iptables -t mangle -F

# 1. تنظيف العمليات القديمة

killall -9 dnsmasq hostapd wpa_supplicant create_ap 2>/dev/null

rm -f /tmp/create_ap.${INTERFACE_WIFI}.lock

# 2. تحييد الـ NetworkManager تماماً عن الكارت (أهم خطوة لـ AMD)

# 2. تحرير الكارت تماماً وضمان عدم قفله

nmcli device set $INTERFACE_WIFI managed no

rfkill unblock wifi

ip link set $INTERFACE_WIFI down

sleep 1

ip link set $INTERFACE_WIFI up

sleep 1


# 3. رفع الواجهة والتأكد من فك أي قفل

rfkill unblock all 2>/dev/null

ip link set $INTERFACE_WIFI up 2>/dev/null
echo "جاري تشغيل نقطة الوصول (Es)..."
# تشغيل الهوت سبوت الآن (سيأتي ترتيب قواعده بعد قواعدك أنت)
create_ap --no-virt -c $CHAN $INTERFACE_WIFI $INTERFACE_ETH $SSID $PASS &
# 2. انتظر قليلاً لاستقرار الشبكة
sleep 5
# 3. تشغيل المحدد في الخلفية (صامت)
# 3. تشغيل المحدد في الخلفية (صامت) من المسار الجديد
#sudo bash /home/es/projects/hotspot-control/scripts/speed_limiter.sh &
sudo bash /home/es/projects/ethernet-control/limit_speed.sh &

# 4. الآن شغل المحرك من المسار الجديد
sudo bash /home/es/projects/hotspot-control/scripts/start-quota &
# 1. تصفير الملف أولاً
> /tmp/hotspot_traffic.raw
# 2. تشغيل أمين المخزن (tcpdump) أولاً لضمان وجود بيانات
sudo tcpdump -l -i $INTERFACE_WIFI -nn -t > /tmp/hotspot_traffic.raw &
# 3. انتظر ثانيتين لضمان أن tcpdump بدأ الكتابة فعلياً
sleep 2

# لضمان عدم خمول كارت الوايفاي أثناء العمل
sudo iw dev $INTERFACE_WIFI set power_save off
echo "جاري فتح لوحة التحكم Guardian Ultra..."
watch --color -n 1 "bash /home/es/projects/hotspot-control/scripts/show-quota; printf '\033[0;34m\n--- الأجهزة المتصلة (IP | Name | MAC) ---\n\033[0m'; sudo find /tmp/ -name 'dnsmasq.leases' -exec cat {} + 2>/dev/null | awk '{print \"\033[0;32m\" \$3 \" | \" \$4 \" | \" \$2 \"\033[0m\"}' | sort -u"
fi