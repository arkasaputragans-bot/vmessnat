#!/bin/bash
# ========================================================
# UPDATE FITUR BACKUP (FILE JSON + KODE BASE64)
# ========================================================

export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONIOENCODING=utf-8

echo "⏳ Memperbarui sistem backup..."

# 1. Update Script Pengirim Backup Mandiri (/root/xray/send_backup.py)
cat << 'EOF' > /root/xray/send_backup.py
# -*- coding: utf-8 -*-
import json, os, sys, requests, base64

BOT_CFG = "/root/xray/bot_config.json"
CONFIG_FILE = "/root/xray/config.json"
USERS_FILE = "/root/xray/users.json"

if not os.path.exists(BOT_CFG):
    print("❌ Bot Telegram belum disetting! Atur dulu di menu [8].")
    sys.exit(1)

try:
    with open(BOT_CFG) as f: b = json.load(f)
    token = b['token']
    admin_id = b['admin_id']
    
    b_data = {
        "config": json.load(open(CONFIG_FILE)),
        "users": json.load(open(USERS_FILE))
    }
    
    b_file = "/tmp/backup.json"
    with open(b_file, "w") as f:
        json.dump(b_data, f, indent=2)
        
    b64_str = base64.b64encode(json.dumps(b_data).encode()).decode()
    
    # Kirim File JSON
    url_doc = f"https://api.telegram.org/bot{token}/sendDocument"
    with open(b_file, "rb") as doc:
        requests.post(url_doc, data={"chat_id": admin_id, "caption": "📦 File Backup Data VMess\nCara Restore di Telegram: Kirim balik file ini ke bot."}, files={"document": doc}, timeout=30)
        
    # Kirim Kode Base64
    url_msg = f"https://api.telegram.org/bot{token}/sendMessage"
    caption_b64 = (
        "📋 KODE BACKUP BASE64 (Untuk Terminal)\n\n"
        "Salin teks di bawah ini untuk restore di terminal menu [7] -> [3]:\n\n"
        + b64_str
    )
    requests.post(url_msg, json={"chat_id": admin_id, "text": caption_b64}, timeout=30)
    
    print("✅ Berhasil! File .json DAN Kode Base64 telah dikirim ke Telegram kamu.")
except Exception as e:
    print(f"❌ Gagal mengirim backup: {str(e)}")
EOF

# 2. Update Bot Daemon agar Handler Backup di Telegram juga kirim Base64
cat << 'EOF' > /tmp/patch_bot.py
import os

path = '/root/xray/bot_daemon.py'
if os.path.exists(path):
    with open(path) as f:
        code = f.read()

    old_snippet = '''                    elif data == "bot_backup":
                        backup_data = {
                            "config": json.load(open(CONFIG_FILE)),
                            "users": json.load(open(USERS_FILE)),
                            "created": str(datetime.datetime.now())
                        }
                        b_path = f"/root/xray/backup_{datetime.date.today()}.json"
                        with open(b_path, "w") as f: json.dump(backup_data, f, indent=2)
                        send_doc(cid, b_path, "📦 *File Backup Data VMess*\nSimpan file ini untuk restore di VPS baru.")'''

    new_snippet = '''                    elif data == "bot_backup":
                        import base64
                        backup_data = {
                            "config": json.load(open(CONFIG_FILE)),
                            "users": json.load(open(USERS_FILE)),
                            "created": str(datetime.datetime.now())
                        }
                        b_path = f"/root/xray/backup_{datetime.date.today()}.json"
                        with open(b_path, "w") as f: json.dump(backup_data, f, indent=2)
                        b64_str = base64.b64encode(json.dumps(backup_data).encode()).decode()
                        send_doc(cid, b_path, "📦 *File Backup Data VMess*\n\nCara 1: Kirim balik file ini ke bot untuk auto-restore.")
                        send_msg(cid, f"📋 *KODE BACKUP BASE64 (Untuk Terminal)*\\n\\nSalin teks ini untuk menu terminal [7] -> [3]:\\n\\n`{b64_str}`")'''

    if old_snippet in code:
        code = code.replace(old_snippet, new_snippet)
        with open(path, 'w') as f:
            f.write(code)
        print("✅ Patch Bot Daemon berhasil!")
EOF

python3 /tmp/patch_bot.py 2>/dev/null
rm -f /tmp/patch_bot.py

# 3. Restart Bot Daemon
pkill -f "bot_daemon.py" 2>/dev/null
nohup python3 /root/xray/bot_daemon.py > /root/xray/bot.log 2>&1 &

echo "=========================================================="
echo "🎉 SISTEM BACKUP BERHASIL DIPERBARUI TOTAL!"
echo "Sekarang silakan tes menu backup [7] -> [1] lagi."
echo "=========================================================="
