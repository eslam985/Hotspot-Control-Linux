# /home/es/projects/hotspot-control/scripts/bot_listener.py
import datetime
import os
import sqlite3
import telebot
from telebot import types
from dotenv import load_dotenv  # تأكد من حذف load_data

# تحديد المسار الرئيسي للمشروع وقراءة ملف البيئة
BASE_DIR = "/home/es/projects/hotspot-control/data"
PROJECT_ROOT = "/home/es/projects/hotspot-control"
load_dotenv(os.path.join(PROJECT_ROOT, ".env"))

# جلب التوكن من ملف الـ .env
TOKEN = os.getenv("TELEGRAM_TOKEN")

# التحقق من وجود التوكن لمنع الأخطاء
if not TOKEN:
    raise ValueError("Error: TELEGRAM_TOKEN not found in .env file")

CONTACTS_FILE = os.path.join(BASE_DIR, "telegram_contacts.txt")
USAGE_DB = os.path.join(BASE_DIR, "usage.sqlite")
QUOTA_FILE = os.path.join(BASE_DIR, "quotas.conf")

bot = telebot.TeleBot(TOKEN)
user_states = {}


def main_keyboard():
    markup = types.ReplyKeyboardMarkup(resize_keyboard=True)
    btn_usage = types.KeyboardButton("📊 استهلاكي الآن")
    btn_register = types.KeyboardButton("📝 تسجيل جديد / تحديث الاسم")
    markup.add(btn_usage)
    markup.add(btn_register)
    return markup


def format_size(mb):
    try:
        mb = float(mb)
        if mb >= 1000:
            return f"{mb / 1000:.2f} GB"
        return f"{mb:.2f} MB"
    except:
        return f"{mb} MB"


def get_quotas():
    quotas = {}
    if os.path.exists(QUOTA_FILE):
        with open(QUOTA_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and "=" in line and not line.startswith("#"):
                    parts = line.split("=")
                    mac = parts[0].strip().lower()
                    try:
                        quotas[mac] = float(parts[1].strip())
                    except ValueError:
                        pass
    return quotas


@bot.message_handler(commands=["start", "help"])
def send_welcome(message):
    bot.reply_to(
        message,
        "👋 أهلاً بك في نظام إشعارات الشبكة!\n\nاختر من الأزرار بالأسفل ما تريد:",
        reply_markup=main_keyboard(),
    )


@bot.message_handler(func=lambda message: True)
def handle_message(message):
    chat_id = message.chat.id
    text = message.text.strip()
    username = message.from_user.username or "NoUsername"

    # 1. زر استهلاكي الآن
    if text == "📊 استهلاكي الآن":
        try:
            quotas_dict = get_quotas()
            conn = sqlite3.connect(USAGE_DB)
            cursor = conn.cursor()

            cursor.execute(
                "SELECT name, usage, mac FROM devices WHERE chat_id = ?",
                (str(chat_id),),
            )
            rows = cursor.fetchall()
            conn.close()

            if rows:
                response = "📊 **تقرير استهلاك الباقة الحالي:**\n\n"
                for row in rows:
                    dev_name, usage_mb, mac = row
                    mac_lower = mac.lower()
                    quota_mb = quotas_dict.get(mac_lower, 0.0)

                    used_str = format_size(usage_mb)

                    if quota_mb > 0:
                        quota_str = format_size(quota_mb)
                        rem_mb = max(0.0, quota_mb - usage_mb)
                        rem_str = format_size(rem_mb)
                        percent_used = min(
                            100.0, (usage_mb / quota_mb) * 100
                        )
                        percent_rem = max(0.0, 100.0 - percent_used)

                        response += (
                            f"👤 **الاسم:** {dev_name}\n"
                            f"📈 **المستهلك:** `{used_str}`\n"
                            f"📦 **إجمالي الباقة:** `{quota_str}`\n"
                            f"⏳ **المتبقي:** `{rem_str}` ({percent_rem:.1f}%)\n"
                            f"🆔 **الماك:** `{mac}`\n"
                            f"----------------------------\n"
                        )
                    else:
                        response += (
                            f"👤 **الاسم:** {dev_name}\n"
                            f"📈 **المستهلك:** `{used_str}`\n"
                            f"📦 **إجمالي الباقة:** غير محدودة\n"
                            f"🆔 **الماك:** `{mac}`\n"
                            f"----------------------------\n"
                        )

                bot.reply_to(
                    message,
                    response,
                    parse_mode="Markdown",
                    reply_markup=main_keyboard(),
                )
            else:
                bot.reply_to(
                    message,
                    "⚠️ **حسابك غير مربوط بأي جهاز حالياً!**\n\n"
                    "يرجى الضغط على زر [ 📝 تسجيل جديد / تحديث الاسم ] لكتابة اسمك، ليقوم الأدمن بربط حسابك.",
                    reply_markup=main_keyboard(),
                )

        except Exception as e:
            bot.reply_to(
                message,
                f"❌ حدث خطأ أثناء قراءة البيانات: {e}",
                reply_markup=main_keyboard(),
            )

    # 2. زر تسجيل جديد
    elif text == "📝 تسجيل جديد / تحديث الاسم":
        user_states[chat_id] = "WAITING_FOR_NAME"
        bot.reply_to(
            message,
            "✍️ من فضلك اكتب اسمك المسجل في الشبكة (مثال: Es أو sayed):",
            reply_markup=types.ReplyKeyboardRemove(),
        )

    # 3. استقبال الاسم عند التسجيل
    elif user_states.get(chat_id) == "WAITING_FOR_NAME":
        now = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
        first_name = message.from_user.first_name or ""
        last_name = message.from_user.last_name or ""
        tg_full_name = f"{first_name} {last_name}".strip()
        tg_username = (
            f"@{message.from_user.username}"
            if message.from_user.username
            else "NoUsername"
        )

        entry = (
            f"[{now}] InputName: {text} | TG Profile: {tg_full_name} | Username: {tg_username} | ChatID: {chat_id}\n"
        )

        with open(CONTACTS_FILE, "a", encoding="utf-8") as f:
            f.write(entry)

        user_states.pop(chat_id, None)

        bot.reply_to(
            message,
            f"✅ تم تسجيل بياناتك بنجاح يا *{text}*!\n\n"
            f"سيقوم الأدمن بتفعيل إشعاراتك وربط حسابك قريباً.",
            parse_mode="Markdown",
            reply_markup=main_keyboard(),
        )

    else:
        bot.reply_to(
            message,
            "الرجاء الاختيار من الأزرار بالأسفل:",
            reply_markup=main_keyboard(),
        )


if __name__ == "__main__":
    print("🤖 Bot listener running...")
    bot.infinity_polling()