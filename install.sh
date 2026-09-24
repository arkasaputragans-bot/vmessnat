#!/bin/bash
# ====================================================================
# MASTER INSTALLER ULTIMATE (VLESS + VMESS + IP INFO + BOT + SPEEDTEST)
# ====================================================================

# 1. Konfigurasi Locale UTF-8 Sistem
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
export PYTHONIOENCODING=utf-8
echo "export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=utf-8" >> /etc/profile
echo "export LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONIOENCODING=utf-8" >> /root/.bashrc

# 2. Update Sistem & Install Paket Pendukung
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
    ca-certificates curl wget unzip jq procps nano psmisc qrencode python3 python3-pip nginx speedtest-cli

pip3 install speedtest-cli requests --break-system-packages 2>/dev/null || pip3 install speedtest-cli requests

# 3. Bersihkan Port & Matikan Semua Proses Lama (Anti-Bentrok)
service nginx stop 2>/dev/null
pkill -9 -f "nginx" 2>/dev/null
pkill -9 -f "xray" 2>/dev/null
pkill -9 -f "cloudflared" 2>/dev/null
pkill -9 -f "bot_daemon.py" 2>/dev/null
fuser -k -9 23331/tcp 2>/dev/null
fuser -k -9 23332/tcp 2>/dev/null
fuser -k -9 23333/tcp 2>/dev/null

# 4. Buat Direktori Kerja
mkdir -p /root/xray /root/.cloudflared
cd /root/xray

# 5. Deteksi Arsitektur & Unduh Xray Core
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && XRAY_ARCH="64" || XRAY_ARCH="arm64-v8a"
[ "$ARCH" = "x86_64" ] && CF_ARCH="amd64" || CF_ARCH="arm64"

echo "⏳ Mengunduh Xray Core Engine..."
curl -L -k "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /root/xray/xray.zip
unzip -o /root/xray/xray.zip -d /root/xray/
rm -f /root/xray/xray.zip
chmod +x /root/xray/xray

# 6. Unduh Cloudflared
echo "⏳ Mengunduh Cloudflared Tunnel..."
curl -L -k "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /root/cloudflared
chmod +x /root/cloudflared

# 7. Konfigurasi Nginx Multiplexer (Jalur VMess & VLESS)
cat << 'EOF' > /etc/nginx/sites-available/default
server {
    listen 127.0.0.1:23333 default_server;
    server_name _;

    location /vmess-railway {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23331;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }

    location /vless-railway {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:23332;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
EOF

# 8. Inisialisasi Database User & Config Xray Dual Inbound (VMess 23331 & VLESS 23332)
FIRST_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")
EXP_DEFAULT=$(python3 -c "import datetime; print((datetime.datetime.now() + datetime.timedelta(days=365)).strftime('%Y-%m-%d %H:%M:%S'))")

cat << EOF > /root/xray/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 23331,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$FIRST_UUID", "alterId": 0, "email": "utama" }
        ]
      },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess-railway" } }
    },
    {
      "port": 23332,
      "listen": "127.0.0.1",
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$FIRST_UUID", "email": "utama" }
        ],
        "decryption": "none"
      },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "/vless-railway" } }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF

cat << EOF > /root/xray/users.json
{
  "utama": {
    "uuid": "$FIRST_UUID",
    "exp": "$EXP_DEFAULT",
    "created": "$(date +%Y-%m-%d)"
  }
}
EOF

# 9. Script Pengirim Backup Mandiri (/root/xray/send_backup.py)
cat << 'EOF' > /root/xray/send_backup.py
import json, os, sys, requests, base64

BOT_CFG = "/root/xray/bot_config.json"
CONFIG_FILE = "/root/xray/config.json"
USERS_FILE = "/root/xray/users.json"

if not os.path.exists(BOT_CFG):
    print("❌ Bot Telegram belum disetting! Atur dulu di menu [10].")
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
    
    # Kirim Dokumen
    requests.post(f"https://api.telegram.org/bot{token}/sendDocument", data={"chat_id": admin_id, "caption": "📦 *File Backup Data VMess & VLESS*"}, files={"document": open(b_file, "rb")}, timeout=30)
    
    # Kirim Kode Base64
    caption_b64 = "📋 *KODE BACKUP BASE64 (Untuk Terminal)*\n\nSalin teks ini untuk menu terminal [9] -> [3]:\n\n`" + b64_str + "`"
    requests.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": admin_id, "text": caption_b64, "parse_mode": "Markdown"}, timeout=30)
    
    print("✅ Berhasil! File .json DAN Kode Base64 telah dikirim ke Telegram kamu.")
except Exception as e:
    print(f"❌ Gagal mengirim backup: {str(e)}")
EOF

# 10. Script Bot Telegram & Daemon Auto-Delete Expired (/root/xray/bot_daemon.py)
cat << 'EOF' > /root/xray/bot_daemon.py
# -*- coding: utf-8 -*-
import requests
import json
import os
import time
import datetime
import subprocess
import threading
import urllib.parse
import base64

CONFIG_FILE = "/root/xray/config.json"
USERS_FILE = "/root/xray/users.json"
BOT_CFG = "/root/xray/bot_config.json"
DOMAIN_FILE = "/root/xray/domain.txt"
MODE_FILE = "/root/xray/mode.txt"
QUICK_LOG = "/root/xray/quick_tunnel.log"

def get_domain():
    mode = "quick"
    if os.path.exists(MODE_FILE):
        with open(MODE_FILE) as f: mode = f.read().strip()
    if mode == "custom" and os.path.exists(DOMAIN_FILE):
        with open(DOMAIN_FILE) as f: return f.read().strip()
    if os.path.exists(QUICK_LOG):
        try:
            with open(QUICK_LOG) as f:
                for l in reversed(f.readlines()):
                    if "trycloudflare.com" in l:
                        import re
                        m = re.search(r'https://[a-zA-Z0-9.-]+\.trycloudflare\.com', l)
                        if m: return m.group(0).replace('https://', '')
        except: pass
    return "Domain-Belum-Siap"

def restart_xray():
    subprocess.run("pkill -f '/root/xray/xray'", shell=True)
    subprocess.run("fuser -k 23331/tcp 2>/dev/null", shell=True)
    subprocess.run("fuser -k 23332/tcp 2>/dev/null", shell=True)
    subprocess.Popen("env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c /root/xray/config.json > /root/xray/xray.log 2>&1", shell=True)

def generate_vmess_link(name, uuid, domain):
    cfg = {
        "v": "2", "ps": name, "add": domain, "port": "443",
        "id": uuid, "aid": "0", "scy": "auto", "net": "ws",
        "type": "none", "host": domain, "path": "/vmess-railway",
        "tls": "tls", "sni": domain
    }
    return "vmess://" + base64.b64encode(json.dumps(cfg).encode()).decode()

def generate_vless_link(name, uuid, domain):
    return f"vless://{uuid}@{domain}:443?path=%2Fvless-railway&security=tls&encryption=none&type=ws&sni={domain}#{urllib.parse.quote(name)}"

def check_expired_and_cleanup_loop(token=None, admin_id=None):
    last_clean_day = None
    while True:
        try:
            now_dt = datetime.datetime.now()
            today_str = now_dt.strftime('%Y-%m-%d %H:%M:%S')

            if os.path.exists(USERS_FILE) and os.path.exists(CONFIG_FILE):
                with open(USERS_FILE) as f: users = json.load(f)
                with open(CONFIG_FILE) as f: config = json.load(f)
                
                expired = []
                for u, val in list(users.items()):
                    if val.get('exp') and val['exp'] < today_str:
                        expired.append(u)
                        del users[u]
                
                if expired:
                    for i in range(len(config.get('inbounds', []))):
                        cls = config['inbounds'][i]['settings']['clients']
                        config['inbounds'][i]['settings']['clients'] = [c for c in cls if c.get('email') not in expired]
                    
                    with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)
                    with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
                    restart_xray()

                    if token and admin_id:
                        for exp_u in expired:
                            msg = f"⚠️ *Notifikasi Kadaluarsa:*\nAkun `{exp_u}` telah kadaluarsa ({today_str}) dan otomatis dihapus."
                            requests.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": admin_id, "text": msg, "parse_mode": "Markdown"})

            # Auto Clean RAM Harian
            current_day = now_dt.day
            if current_day != last_clean_day:
                last_clean_day = current_day
                subprocess.run("sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null", shell=True)
                for log_f in ["/root/xray/xray.log", "/root/xray/bot.log"]:
                    if os.path.exists(log_f) and os.path.getsize(log_f) > 5 * 1024 * 1024:
                        with open(log_f, "w") as lf: lf.write("")
        except Exception:
            pass
        time.sleep(60)

def hourly_backup_loop(token, admin_id):
    while True:
        time.sleep(3600)
        try:
            if os.path.exists(CONFIG_FILE) and os.path.exists(USERS_FILE):
                b_data = {
                    "config": json.load(open(CONFIG_FILE)),
                    "users": json.load(open(USERS_FILE)),
                    "created": str(datetime.datetime.now())
                }
                b64_str = base64.b64encode(json.dumps(b_data).encode()).decode()
                now_time = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
                msg = f"⏰ *AUTO-BACKUP RUTIN (Tiap 1 Jam)*\n📅 Waktu: `{now_time}`\n\nSalin teks Base64 ini untuk restore di VPS baru:\n\n`{b64_str}`"
                requests.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": admin_id, "text": msg, "parse_mode": "Markdown"}, timeout=30)
        except Exception:
            pass

def main():
    if not os.path.exists(BOT_CFG):
        check_expired_and_cleanup_loop()
        return

    with open(BOT_CFG) as f: bcfg = json.load(f)
    TOKEN = bcfg.get("token")
    ADMIN_ID = int(bcfg.get("admin_id", 0))

    if not TOKEN or not ADMIN_ID:
        check_expired_and_cleanup_loop()
        return

    threading.Thread(target=check_expired_and_cleanup_loop, args=(TOKEN, ADMIN_ID), daemon=True).start()
    threading.Thread(target=hourly_backup_loop, args=(TOKEN, ADMIN_ID), daemon=True).start()

    API = f"https://api.telegram.org/bot{TOKEN}"
    user_state = {}

    def send_msg(chat_id, text, reply_markup=None):
        payload = {"chat_id": chat_id, "text": text, "parse_mode": "Markdown"}
        if reply_markup: payload["reply_markup"] = reply_markup
        return requests.post(f"{API}/sendMessage", json=payload, timeout=15)

    def send_photo(chat_id, photo_url, caption):
        payload = {"chat_id": chat_id, "photo": photo_url, "caption": caption, "parse_mode": "Markdown"}
        return requests.post(f"{API}/sendPhoto", json=payload, timeout=20)

    def send_doc(chat_id, file_path, caption):
        with open(file_path, 'rb') as f:
            return requests.post(f"{API}/sendDocument", data={"chat_id": chat_id, "caption": caption, "parse_mode": "Markdown"}, files={"document": f}, timeout=30)

    main_menu = {
        "inline_keyboard": [
            [{"text": "➕ Akun Normal", "callback_data": "bot_create"}, {"text": "⚡ Akun Trial", "callback_data": "bot_trial"}],
            [{"text": "📋 List Akun", "callback_data": "bot_list"}, {"text": "🔄 Perpanjang", "callback_data": "bot_renew"}],
            [{"text": "🗑️ Hapus Akun", "callback_data": "bot_delete"}, {"text": "🚀 Speedtest", "callback_data": "bot_speedtest"}],
            [{"text": "📦 Backup Sekarang", "callback_data": "bot_backup"}, {"text": "📊 Status Server", "callback_data": "bot_status"}]
        ]
    }

    offset = 0
    while True:
        try:
            res = requests.get(f"{API}/getUpdates?offset={offset}&timeout=20", timeout=30).json()
            for upd in res.get("result", []):
                offset = upd["update_id"] + 1

                if "callback_query" in upd:
                    cq = upd["callback_query"]
                    cid = cq["message"]["chat"]["id"]
                    cq_id = cq["id"]
                    data = cq.get("data")
                    requests.post(f"{API}/answerCallbackQuery", json={"callback_query_id": cq_id})

                    if cid != ADMIN_ID: continue

                    if data == "bot_list":
                        if os.path.exists(USERS_FILE):
                            with open(USERS_FILE) as f: users = json.load(f)
                            text = "📋 *Daftar Akun Aktif:*\n\n"
                            now_dt = datetime.datetime.now()
                            for u, v in users.items():
                                exp_str = v.get('exp', '')
                                try:
                                    exp_dt = datetime.datetime.strptime(exp_str, '%Y-%m-%d %H:%M:%S')
                                    diff = exp_dt - now_dt
                                    if diff.total_seconds() > 86400:
                                        status = f"{diff.days} hari lagi"
                                    elif diff.total_seconds() > 0:
                                        status = f"{int(diff.total_seconds()//3600)} jam lagi"
                                    else:
                                        status = "Kadaluarsa"
                                except:
                                    status = exp_str
                                text += f"👤 `{u}`\n📅 Exp: `{exp_str}` ({status})\n🔑 UUID: `{v['uuid']}`\n\n"
                            send_msg(cid, text)

                    elif data == "bot_status":
                        dom = get_domain()
                        with open(USERS_FILE) as f: ucount = len(json.load(f))
                        send_msg(cid, f"⚡ *Status Server:*\n🔹 Domain: `{dom}`\n🔹 Total Akun: `{ucount}`\n🔹 Port: `443` (TLS)\n🔹 Mode: `VMess & VLESS Aktif`\n🔹 Auto-Backup: `Aktif Tiap 1 Jam`")

                    elif data == "bot_speedtest":
                        send_msg(cid, "⏳ *Sedang menjalankan Speedtest...* (Tunggu 15-20 detik)")
                        def run_st():
                            try:
                                out = subprocess.check_output("speedtest-cli --simple", shell=True).decode()
                                send_msg(cid, f"🚀 *HASIL SPEEDTEST SERVER:*\n\n```\n{out}\n```")
                            except Exception as e:
                                send_msg(cid, f"❌ Gagal Speedtest: {str(e)}")
                        threading.Thread(target=run_st).start()

                    elif data == "bot_backup":
                        backup_data = {
                            "config": json.load(open(CONFIG_FILE)),
                            "users": json.load(open(USERS_FILE)),
                            "created": str(datetime.datetime.now())
                        }
                        b_path = f"/root/xray/backup_{datetime.date.today()}.json"
                        with open(b_path, "w") as f: json.dump(backup_data, f, indent=2)
                        b64_str = base64.b64encode(json.dumps(backup_data).encode()).decode()
                        send_doc(cid, b_path, "📦 *File Backup Data*\nKirim balik file ini ke bot kapan saja untuk restore.")
                        send_msg(cid, f"📋 *KODE BACKUP BASE64 (Untuk Terminal)*\n\nSalin kode ini:\n\n`{b64_str}`")

                    elif data == "bot_create":
                        user_state[cid] = "create"
                        send_msg(cid, "📝 *Buat Akun Normal*\nFormat: `nama durasi_hari`\nContoh: `budi 30`")

                    elif data == "bot_trial":
                        user_state[cid] = "trial"
                        send_msg(cid, "⚡ *Buat Akun Trial*\nFormat: `nama pilihan_durasi`\n`1` = 1 Jam\n`24` = 24 Jam (1 Hari)\n\nContoh: `tes 1` atau `tes 24`")

                    elif data == "bot_renew":
                        user_state[cid] = "renew"
                        send_msg(cid, "🔄 Format: `nama hari_tambahan`\nContoh: `budi 30`")

                    elif data == "bot_delete":
                        user_state[cid] = "delete"
                        send_msg(cid, "🗑️ Masukkan nama user yang ingin dihapus:")

                elif "message" in upd and "document" in upd["message"]:
                    msg = upd["message"]
                    cid = msg["chat"]["id"]
                    if cid != ADMIN_ID: continue

                    doc = msg["document"]
                    f_info = requests.get(f"{API}/getFile?file_id={doc['file_id']}").json()
                    if f_info.get("ok"):
                        f_path = f_info["result"]["file_path"]
                        down = requests.get(f"https://api.telegram.org/file/bot{TOKEN}/{f_path}").content
                        try:
                            d = json.loads(down.decode())
                            if "config" in d and "users" in d:
                                with open(CONFIG_FILE, 'w') as f: json.dump(d["config"], f, indent=2)
                                with open(USERS_FILE, 'w') as f: json.dump(d["users"], f, indent=2)
                                restart_xray()
                                send_msg(cid, "🎉 *RESTORE SUKSES!* Seluruh akun & konfigurasi berhasil dipulihkan.")
                            else:
                                send_msg(cid, "❌ Format file backup tidak valid!")
                        except Exception as e:
                            send_msg(cid, f"❌ Gagal restore: {str(e)}")

                elif "message" in upd and "text" in upd["message"]:
                    msg = upd["message"]
                    cid = msg["chat"]["id"]
                    text = msg["text"].strip()
                    if cid != ADMIN_ID: continue

                    if text in ["/start", "/menu"]:
                        user_state[cid] = None
                        send_msg(cid, "🤖 *Panel Manajemen VMess & VLESS Railway*\nSilakan pilih menu di bawah:", reply_markup=main_menu)
                        continue

                    state = user_state.get(cid)

                    if state in ["create", "trial"]:
                        user_state[cid] = None
                        try:
                            parts = text.split()
                            name = parts[0]
                            val = int(parts[1]) if len(parts) > 1 else (1 if state == "trial" else 30)

                            with open(USERS_FILE) as f: users = json.load(f)
                            with open(CONFIG_FILE) as f: config = json.load(f)

                            if name in users:
                                send_msg(cid, "❌ Nama user sudah terpakai!"); continue

                            import uuid as uid
                            new_id = str(uid.uuid4())
                            now_dt = datetime.datetime.now()

                            if state == "trial":
                                exp_dt = now_dt + datetime.timedelta(hours=val)
                                dur_label = f"{val} Jam"
                            else:
                                exp_dt = now_dt + datetime.timedelta(days=val)
                                dur_label = f"{val} Hari"

                            exp_str = exp_dt.strftime('%Y-%m-%d %H:%M:%S')

                            users[name] = {"uuid": new_id, "exp": exp_str, "created": str(datetime.date.today())}
                            config['inbounds'][0]['settings']['clients'].append({"id": new_id, "alterId": 0, "email": name})
                            config['inbounds'][1]['settings']['clients'].append({"id": new_id, "email": name})

                            with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)
                            with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
                            restart_xray()

                            dom = get_domain()
                            vmess_link = generate_vmess_link(name, new_id, dom)
                            vless_link = generate_vless_link(name, new_id, dom)
                            qr_url = f"https://api.qrserver.com/v1/create-qr-code/?size=350x350&data={urllib.parse.quote(vless_link)}"

                            caption = (
                                f"🎉 *Akun ({'TRIAL' if state == 'trial' else 'NORMAL'}) Berhasil Dibuat!*\n\n"
                                f"🔹 User : `{name}`\n"
                                f"🔹 Expired : `{exp_str}` ({dur_label})\n"
                                f"🔹 Domain : `{dom}`\n"
                                f"🔹 Port : `443` (TLS)\n"
                                f"🔹 UUID : `{new_id}`\n\n"
                                f"⚡ *Link VLESS (Direkomendasikan):*\n`{vless_link}`\n\n"
                                f"📌 *Link VMess:*\n`{vmess_link}`"
                            )
                            send_photo(cid, qr_url, caption)
                        except Exception as e:
                            send_msg(cid, f"❌ Error: {str(e)}")

                    elif state == "renew":
                        user_state[cid] = None
                        try:
                            parts = text.split()
                            name = parts[0]
                            days = int(parts[1]) if len(parts) > 1 else 30
                            with open(USERS_FILE) as f: users = json.load(f)
                            if name not in users:
                                send_msg(cid, "❌ User tidak ditemukan!"); continue
                            
                            cur_exp = users[name].get('exp', '')
                            try:
                                base_dt = max(datetime.datetime.strptime(cur_exp, '%Y-%m-%d %H:%M:%S'), datetime.datetime.now())
                            except:
                                base_dt = datetime.datetime.now()

                            new_exp = (base_dt + datetime.timedelta(days=days)).strftime('%Y-%m-%d %H:%M:%S')
                            users[name]['exp'] = new_exp
                            with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
                            send_msg(cid, f"✅ Akun `{name}` diperpanjang hingga: `{new_exp}`")
                        except Exception as e:
                            send_msg(cid, f"❌ Error: {str(e)}")

                    elif state == "delete":
                        user_state[cid] = None
                        try:
                            name = text
                            with open(USERS_FILE) as f: users = json.load(f)
                            with open(CONFIG_FILE) as f: config = json.load(f)
                            if name not in users:
                                send_msg(cid, "❌ User tidak ditemukan!"); continue
                            del users[name]
                            for i in range(len(config.get('inbounds', []))):
                                cls = config['inbounds'][i]['settings']['clients']
                                config['inbounds'][i]['settings']['clients'] = [c for c in cls if c.get('email') != name]
                            
                            with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)
                            with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
                            restart_xray()
                            send_msg(cid, f"✅ Akun `{name}` berhasil dihapus!")
                        except Exception as e:
                            send_msg(cid, f"❌ Error: {str(e)}")

        except Exception:
            time.sleep(2)

if __name__ == '__main__':
    main()
EOF

# 11. Pasang Script Menu CLI Lengkap Dengan Info IP & Lokasi (/usr/local/bin/menu)
cat << 'EOF' > /usr/local/bin/menu
#!/bin/bash

export XRAY_LOCATION_ASSET="/root/xray"
CONFIG_FILE="/root/xray/config.json"
USERS_FILE="/root/xray/users.json"
BOT_CFG="/root/xray/bot_config.json"
MODE_FILE="/root/xray/mode.txt"
DOMAIN_FILE="/root/xray/domain.txt"
QUICK_LOG="/root/xray/quick_tunnel.log"

get_server_info() {
    if [ ! -f /tmp/server_info.txt ]; then
        local info=$(curl -s --max-time 2 http://ip-api.com/json 2>/dev/null)
        if [ -n "$info" ]; then
            local ip=$(echo "$info" | jq -r '.query // "Unknown"')
            local city=$(echo "$info" | jq -r '.city // ""')
            local country=$(echo "$info" | jq -r '.country // "Unknown"')
            local isp=$(echo "$info" | jq -r '.isp // "Unknown"')
            echo "$ip|$city, $country|$isp" > /tmp/server_info.txt
        else
            echo "Unknown|Unknown|Unknown" > /tmp/server_info.txt
        fi
    fi
}

restart_xray() {
    pkill -f "/root/xray/xray" 2>/dev/null
    fuser -k 23331/tcp 2>/dev/null
    fuser -k 23332/tcp 2>/dev/null
    service nginx restart 2>/dev/null || /usr/sbin/nginx -s reload 2>/dev/null
    nohup env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c "$CONFIG_FILE" > /root/xray/xray.log 2>&1 &
}

restart_bot() {
    pkill -f "bot_daemon.py" 2>/dev/null
    nohup python3 /root/xray/bot_daemon.py > /root/xray/bot.log 2>&1 &
}

get_current_domain() {
    local mode=$(cat "$MODE_FILE" 2>/dev/null || echo "quick")
    if [ "$mode" == "custom" ]; then
        cat "$DOMAIN_FILE" 2>/dev/null || echo "Belum-diatur"
    else
        local q_dom=$(grep -oE 'https://[a-zA-Z0-9.-]+\.trycloudflare\.com' "$QUICK_LOG" 2>/dev/null | tail -n 1 | sed 's|https://||')
        if [ -n "$q_dom" ]; then
            echo "$q_dom"
        else
            echo "Menghubungkan ke Cloudflare..."
        fi
    fi
}

make_vmess() {
    local u_name="$1"
    local u_id="$2"
    local domain=$(get_current_domain)
    local v_json=$(cat << JSON
{
  "v": "2", "ps": "$u_name", "add": "$domain", "port": "443",
  "id": "$u_id", "aid": "0", "scy": "auto", "net": "ws",
  "type": "none", "host": "$domain", "path": "/vmess-railway",
  "tls": "tls", "sni": "$domain"
}
JSON
)
    echo "vmess://$(echo -n "$v_json" | base64 -w 0)"
}

make_vless() {
    local u_name="$1"
    local u_id="$2"
    local domain=$(get_current_domain)
    echo "vless://$u_id@$domain:443?path=%2Fvless-railway&security=tls&encryption=none&type=ws&sni=$domain#$u_name"
}

while true; do
    CUR_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "quick")
    CUR_DOM=$(get_current_domain)
    TOTAL_ACC=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

    pgrep -f "/root/xray/xray" > /dev/null && STAT_X="\033[1;32m[ AKTIF ]\033[0m" || STAT_X="\033[1;31m[ MATI ]\033[0m"
    pgrep -f "cloudflared" > /dev/null && STAT_T="\033[1;32m[ AKTIF ]\033[0m" || STAT_T="\033[1;31m[ MATI ]\033[0m"
    pgrep -f "bot_daemon.py" > /dev/null && STAT_B="\033[1;32m[ AKTIF ]\033[0m" || STAT_B="\033[1;33m[ NONAKTIF ]\033[0m"

    get_server_info
    IFS='|' read -r S_IP S_LOC S_ISP < /tmp/server_info.txt

    echo ""
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e "      \033[1;33m⚡ VMESS & VLESS ULTIMATE PANEL (RAILWAY) ⚡\033[0m"
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e " 🌐 IP Server    : \033[1;32m$S_IP\033[0m (\033[1;36m$S_LOC\033[0m)"
    echo -e " 🏢 Provider/ISP : \033[1;37m$S_ISP\033[0m"
    echo -e " 🔹 Xray Service : $STAT_X (VMess & VLESS)"
    echo -e " 🔹 Cloudflare   : $STAT_T (Mode: \033[1;35m$CUR_MODE\033[0m)"
    echo -e " 🔹 Bot Telegram : $STAT_B (Auto-Backup: \033[1;32m1 Jam\033[0m)"
    echo -e " 🔹 Domain / SNI : \033[1;36m$CUR_DOM\033[0m"
    echo -e " 🔹 Total Akun   : \033[1;32m$TOTAL_ACC Akun\033[0m"
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e " [1] Buat Akun Normal (Durasi Hari)"
    echo -e " [2] \033[1;33mBuat Akun TRIAL (1 Jam / 24 Jam)\033[0m"
    echo -e " [3] Hapus Akun"
    echo -e " [4] Perpanjang Masa Aktif Akun (Renew)"
    echo -e " [5] Lihat Detail Akun, Sisa Waktu, Link & QR Code"
    echo -e " [6] Ganti / Custom UUID Akun"
    echo -e " [7] Atur Domain (Domain Sendiri / Quick Tunnel)"
    echo -e " [8] \033[1;32mCek Speedtest Server (Ping, DL, UL)\033[0m"
    echo -e " [9] Backup & Restore Data"
    echo -e " [10] Integrasi Bot Telegram Admin"
    echo -e " [11] Restart Semua Service"
    echo -e " \033[1;31m[12] Hapus Script Total (Reset VPS)\033[0m"
    echo -e " [0] Keluar"
    echo -e "\033[1;34m=====================================================\033[0m"
    read -p "Pilih Opsi [0-12]: " opt

    case $opt in
        1|2)
            is_trial=0
            [ "$opt" == "2" ] && is_trial=1

            echo ""
            [ "$is_trial" == "1" ] && echo -e "\033[1;33m--- BUAT AKUN TRIAL ---\033[0m" || echo -e "\033[1;33m--- BUAT AKUN NORMAL ---\033[0m"
            read -p "Masukkan Nama User: " new_name
            [ -z "$new_name" ] && { echo -e "❌ Nama kosong!"; sleep 1.5; continue; }

            exists=$(jq --arg u "$new_name" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE" 2>/dev/null)
            if [ -n "$exists" ]; then
                echo -e "❌ User '$new_name' sudah ada!"; read -p "Tekan Enter..."; continue
            fi

            if [ "$is_trial" == "1" ]; then
                echo "Pilih Durasi Trial:"
                echo " [1] 1 Jam"
                echo " [2] 24 Jam (1 Hari)"
                read -p "Pilihan [1/2]: " tr_opt
                [ "$tr_opt" == "2" ] && tr_hours=24 || tr_hours=1
                exp_date=$(python3 -c "import datetime; print((datetime.datetime.now() + datetime.timedelta(hours=$tr_hours)).strftime('%Y-%m-%d %H:%M:%S'))")
                dur_lbl="$tr_hours Jam"
            else
                read -p "Masa aktif berapa hari? (default 30): " dur_days
                [ -z "$dur_days" ] && dur_days=30
                exp_date=$(python3 -c "import datetime; print((datetime.datetime.now() + datetime.timedelta(days=$dur_days)).strftime('%Y-%m-%d %H:%M:%S'))")
                dur_lbl="$dur_days Hari"
            fi

            new_id=$(python3 -c "import uuid; print(uuid.uuid4())")

            jq --arg u "$new_name" --arg id "$new_id" '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}] | .inbounds[1].settings.clients += [{"id": $id, "email": $u}]' "$CONFIG_FILE" > /tmp/c.json && mv /tmp/c.json "$CONFIG_FILE"
            jq --arg u "$new_name" --arg id "$new_id" --arg exp "$exp_date" --arg cr "$(date +%Y-%m-%d)" '.[$u] = {"uuid": $id, "exp": $exp, "created": $cr}' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"

            restart_xray
            cur_dom=$(get_current_domain)
            vless_l=$(make_vless "$new_name" "$new_id")
            vmess_l=$(make_vmess "$new_name" "$new_id")

            clear
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e "          🎉 \033[1;32mAKUN BERHASIL DIBUAT!\033[0m 🎉"
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e " 🔹 User     : \033[1;37m$new_name\033[0m"
            echo -e " 🔹 Expired  : \033[1;33m$exp_date ($dur_lbl)\033[0m"
            echo -e " 🔹 Domain   : \033[1;36m$cur_dom\033[0m"
            echo -e " 🔹 Port     : \033[1;37m443 (TLS)\033[0m"
            echo -e " 🔹 UUID     : \033[1;33m$new_id\033[0m"
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e " 📱 \033[1;33mSCAN QR CODE (VLESS):\033[0m"
            qrencode -t ANSIUTF8 "$vless_l"
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e " ⚡ \033[1;32mLINK VLESS (KENCANG & GAME):\033[0m"
            echo -e "\033[1;36m$vless_l\033[0m"
            echo ""
            echo -e " 📌 \033[1;33mLINK VMESS:\033[0m"
            echo -e "\033[1;36m$vmess_l\033[0m"
            echo -e "\033[1;32m=====================================================\033[0m"
            read -p " 👉 Tekan [ENTER] jika sudah selesai copy untuk kembali..." dummy
            ;;

        3)
            echo -e "\n--- HAPUS AKUN ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do echo " [$((i+1))] ${list_u[$i]}"; done
            read -p "Pilih Nomor: " d_idx
            if [ -n "$d_idx" ] && [ "$d_idx" -le "${#list_u[@]}" ] && [ "$d_idx" -ge 1 ]; then
                target="${list_u[$((d_idx-1))]}"
                jq --arg u "$target" '.inbounds[0].settings.clients |= map(select(.email != $u)) | .inbounds[1].settings.clients |= map(select(.email != $u))' "$CONFIG_FILE" > /tmp/c.json && mv /tmp/c.json "$CONFIG_FILE"
                jq --arg u "$target" 'del(.[$u])' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"
                restart_xray
                echo "✅ Akun '$target' berhasil dihapus!"
            fi
            read -p "Tekan Enter..." dummy
            ;;

        4)
            echo -e "\n--- PERPANJANG AKUN ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do
                u="${list_u[$i]}"
                cur_exp=$(jq -r --arg u "$u" '.[$u].exp // "Unknown"' "$USERS_FILE")
                echo " [$((i+1))] $u (Exp: $cur_exp)"
            done
            read -p "Pilih Nomor: " r_idx
            if [ -n "$r_idx" ] && [ "$r_idx" -le "${#list_u[@]}" ] && [ "$r_idx" -ge 1 ]; then
                target="${list_u[$((r_idx-1))]}"
                read -p "Tambah berapa hari?: " add_days
                [ -z "$add_days" ] && add_days=30
                new_exp=$(python3 -c "
import datetime, json
with open('$USERS_FILE') as f: u = json.load(f)
c_str = u.get('$target', {}).get('exp', '')
try:
    base = max(datetime.datetime.strptime(c_str, '%Y-%m-%d %H:%M:%S'), datetime.datetime.now())
except:
    base = datetime.datetime.now()
print((base + datetime.timedelta(days=$add_days)).strftime('%Y-%m-%d %H:%M:%S'))
")
                jq --arg u "$target" --arg exp "$new_exp" '.[$u].exp = $exp' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"
                echo "✅ Akun '$target' diperpanjang hingga: $new_exp!"
            fi
            read -p "Tekan Enter..." dummy
            ;;

        5)
            echo -e "\n--- DAFTAR & DETAIL AKUN ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do
                u="${list_u[$i]}"
                exp_date=$(jq -r --arg u "$u" '.[$u].exp // "Unknown"' "$USERS_FILE")
                echo " [$((i+1))] $u | Exp: $exp_date"
            done
            read -p "Pilih Nomor: " s_idx
            if [ -n "$s_idx" ] && [ "$s_idx" -le "${#list_u[@]}" ] && [ "$s_idx" -ge 1 ]; then
                target="${list_u[$((s_idx-1))]}"
                target_id=$(jq -r --arg u "$target" '.inbounds[0].settings.clients[] | select(.email == $u) | .id' "$CONFIG_FILE")
                exp_date=$(jq -r --arg u "$target" '.[$u].exp // "Unknown"' "$USERS_FILE")
                cur_dom=$(get_current_domain)
                vless_l=$(make_vless "$target" "$target_id")
                vmess_l=$(make_vmess "$target" "$target_id")

                clear
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e "                  📋 DETAIL AKUN"
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e " 🔹 User    : \033[1;37m$target\033[0m"
                echo -e " 🔹 Expired : \033[1;33m$exp_date\033[0m"
                echo -e " 🔹 Domain  : \033[1;36m$cur_dom\033[0m"
                echo -e " 🔹 Port    : \033[1;37m443 (TLS)\033[0m"
                echo -e " 🔹 UUID    : \033[1;33m$target_id\033[0m"
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e " 📱 SCAN QR CODE (VLESS):"
                qrencode -t ANSIUTF8 "$vless_l"
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e " ⚡ LINK VLESS:\n\033[1;36m$vless_l\033[0m\n"
                echo -e " 📌 LINK VMESS:\n\033[1;36m$vmess_l\033[0m"
                echo -e "\033[1;34m=====================================================\033[0m"
                read -p " Tekan [ENTER] untuk kembali..." dummy
            fi
            ;;

        6)
            echo -e "\n--- GANTI / CUSTOM UUID ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do echo " [$((i+1))] ${list_u[$i]}"; done
            read -p "Pilih Nomor: " c_idx
            if [ -n "$c_idx" ] && [ "$c_idx" -le "${#list_u[@]}" ] && [ "$c_idx" -ge 1 ]; then
                target="${list_u[$((c_idx-1))]}"
                read -p "UUID Baru (Enter untuk auto): " custom_uuid
                [ -z "$custom_uuid" ] && custom_uuid=$(python3 -c "import uuid; print(uuid.uuid4())")
                jq --arg u "$target" --arg id "$custom_uuid" '(.inbounds[0].settings.clients[] | select(.email == $u)).id = $id | (.inbounds[1].settings.clients[] | select(.email == $u)).id = $id' "$CONFIG_FILE" > /tmp/c.json && mv /tmp/c.json "$CONFIG_FILE"
                jq --arg u "$target" --arg id "$custom_uuid" '.[$u].uuid = $id' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"
                restart_xray
                echo "✅ UUID diubah ke: $custom_uuid"
            fi
            read -p "Tekan Enter..." dummy
            ;;

        7)
            echo -e "\n--- PENGATURAN DOMAIN ---"
            echo " [1] Domain Sendiri (Cloudflare)"
            echo " [2] Quick Tunnel (*.trycloudflare.com)"
            read -p "Pilih [1/2]: " dom_opt
            if [ "$dom_opt" == "1" ]; then
                /root/cloudflared tunnel login
                if [ ! -f /root/.cloudflared/cert.pem ]; then
                    echo "❌ Login gagal/batal."; read -p "Tekan Enter..."; continue
                fi
                read -p "Masukkan Subdomain (Contoh: sgdo4.mamzvpn.com): " custom_dom
                [ -z "$custom_dom" ] && continue
                pkill -f "cloudflared" 2>/dev/null
                /root/cloudflared tunnel delete -f railway-tunnel 2>/dev/null
                /root/cloudflared tunnel create railway-tunnel
                /root/cloudflared tunnel route dns railway-tunnel "$custom_dom"
                nohup /root/cloudflared tunnel run --url http://127.0.0.1:23333 railway-tunnel > /dev/null 2>&1 &
                echo "$custom_dom" > "$DOMAIN_FILE"
                echo "custom" > "$MODE_FILE"
                echo "✅ Domain $custom_dom aktif permanen!"
            elif [ "$dom_opt" == "2" ]; then
                pkill -f "cloudflared" 2>/dev/null
                rm -f "$QUICK_LOG"
                nohup /root/cloudflared tunnel --url http://127.0.0.1:23333 --logfile "$QUICK_LOG" > /dev/null 2>&1 &
                echo "quick" > "$MODE_FILE"
                echo "Menunggu koneksi 6 detik..."
                sleep 6
            fi
            read -p "Tekan Enter..." dummy
            ;;

        8)
            echo -e "\n⏳ Sedang melakukan Speedtest Server (15-20 detik)..."
            speedtest-cli --simple
            read -p "Tekan [ENTER] untuk kembali..." dummy
            ;;

        9)
            echo -e "\n--- BACKUP & RESTORE DATA ---"
            echo " [1] Kirim Backup File & Base64 ke Telegram"
            echo " [2] Tampilkan Kode Base64 di Layar"
            echo " [3] Restore dari Kode Base64"
            read -p "Pilih [1-3]: " b_opt
            if [ "$b_opt" == "1" ]; then
                python3 /root/xray/send_backup.py
            elif [ "$b_opt" == "2" ]; then
                b_str=$(python3 -c "
import json, base64
b_data = {'config': json.load(open('$CONFIG_FILE')), 'users': json.load(open('$USERS_FILE'))}
print(base64.b64encode(json.dumps(b_data).encode()).decode())
")
                echo -e "\nKODE BACKUP BASE64:\n$b_str\n"
            elif [ "$b_opt" == "3" ]; then
                read -p "Paste Kode Base64: " in_b64
                python3 -c "
import json, base64
try:
    d = json.loads(base64.b64decode('$in_b64').decode())
    with open('$CONFIG_FILE', 'w') as f: json.dump(d['config'], f, indent=2)
    with open('$USERS_FILE', 'w') as f: json.dump(d['users'], f, indent=2)
    print('✅ RESTORE BERHASIL!')
except Exception as e:
    print('❌ Kode backup tidak valid!')
"
                restart_xray
            fi
            read -p "Tekan Enter..." dummy
            ;;

        10)
            echo -e "\n--- INTEGRASI BOT TELEGRAM ---"
            read -p "Token Bot Telegram: " in_tok
            read -p "ID Telegram Admin: " in_aid
            if [ -n "$in_tok" ] && [ -n "$in_aid" ]; then
                echo "{\"token\": \"$in_tok\", \"admin_id\": $in_aid}" > "$BOT_CFG"
                restart_bot
                echo "✅ Bot Telegram Aktif! Buka Telegram dan ketik /start"
            fi
            read -p "Tekan Enter..." dummy
            ;;

        11)
            echo "Merestart semua service..."
            restart_xray
            restart_bot
            CUR_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "quick")
            pkill -f "cloudflared" 2>/dev/null
            if [ "$CUR_MODE" == "custom" ]; then
                nohup /root/cloudflared tunnel run --url http://127.0.0.1:23333 railway-tunnel > /dev/null 2>&1 &
            else
                rm -f "$QUICK_LOG"
                nohup /root/cloudflared tunnel --url http://127.0.0.1:23333 --logfile "$QUICK_LOG" > /dev/null 2>&1 &
            fi
            echo "✅ Semua service berhasil direstart!"
            sleep 2
            ;;

        12)
            read -p "Yakin ingin RESET TOTAL? (y/n): " confirm_del
            if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                service nginx stop 2>/dev/null
                pkill -9 -f "nginx" 2>/dev/null
                pkill -9 -f "xray" 2>/dev/null
                pkill -9 -f "cloudflared" 2>/dev/null
                pkill -9 -f "bot_daemon.py" 2>/dev/null
                fuser -k -9 23331/tcp 2>/dev/null
                fuser -k -9 23332/tcp 2>/dev/null
                fuser -k -9 23333/tcp 2>/dev/null
                rm -rf /root/xray /root/.cloudflared /root/cloudflared /usr/local/bin/menu /etc/nginx/sites-available/default
                echo "✅ VPS Bersih Total!"
                exit 0
            fi
            ;;
        0)
            exit 0
            ;;
    esac
done
EOF

chmod +x /usr/local/bin/menu

# 12. Nyalakan Service Awal
service nginx restart 2>/dev/null || /usr/sbin/nginx
export XRAY_LOCATION_ASSET="/root/xray"
nohup env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c /root/xray/config.json > /root/xray/xray.log 2>&1 &
echo "quick" > /root/xray/mode.txt
nohup /root/cloudflared tunnel --url http://127.0.0.1:23333 --logfile /root/xray/quick_tunnel.log > /dev/null 2>&1 &
nohup python3 /root/xray/bot_daemon.py > /root/xray/bot.log 2>&1 &

sleep 2

echo "=========================================================="
if pgrep -f "/root/xray/xray" > /dev/null; then
    echo -e "🎉 STATUS XRAY: \033[1;32m[ AKTIF / BERJALAN ]\033[0m (VMess & VLESS)"
else
    echo -e "❌ Xray Log Error: $(cat /root/xray/xray.log)"
fi
echo "=========================================================="
menu
