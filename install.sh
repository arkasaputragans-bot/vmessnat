#!/bin/bash
# ====================================================================
# MASTER INSTALLER VMESS XRAY + CLOUDFLARE + BOT TELEGRAM (FRESH VPS)
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
    ca-certificates curl wget unzip jq procps nano psmisc qrencode python3 python3-pip

pip3 install requests --break-system-packages 2>/dev/null || pip3 install requests

# 3. Bersihkan Port & Matikan Proses Lama
pkill -f "/root/xray/xray" 2>/dev/null
pkill -f "cloudflared" 2>/dev/null
pkill -f "bot_daemon.py" 2>/dev/null
fuser -k 23333/tcp 2>/dev/null

# 4. Buat Direktori Kerja
mkdir -p /root/xray /root/.cloudflared
cd /root/xray

# 5. Deteksi Arsitektur & Unduh Xray Core
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && XRAY_ARCH="64" || XRAY_ARCH="arm64-v8a"
[ "$ARCH" = "x86_64" ] && CF_ARCH="amd64" || CF_ARCH="arm64"

echo "⏳ Mengunduh Xray Core..."
curl -L -k "https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-${XRAY_ARCH}.zip" -o /root/xray/xray.zip
unzip -o /root/xray/xray.zip -d /root/xray/
rm -f /root/xray/xray.zip
chmod +x /root/xray/xray

# 6. Unduh Cloudflared
echo "⏳ Mengunduh Cloudflared..."
curl -L -k "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" -o /root/cloudflared
chmod +x /root/cloudflared

# 7. Inisialisasi Database User & Config Xray
FIRST_UUID=$(python3 -c "import uuid; print(uuid.uuid4())")
EXP_DEFAULT=$(python3 -c "import datetime; print((datetime.date.today() + datetime.timedelta(days=365)).strftime('%Y-%m-%d'))")

cat << EOF > /root/xray/config.json
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "port": 23333,
      "listen": "127.0.0.1",
      "protocol": "vmess",
      "settings": {
        "clients": [
          { "id": "$FIRST_UUID", "alterId": 0, "email": "utama" }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": { "path": "/vmess-railway" }
      }
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

# 8. Buat Script Pengirim Backup Mandiri (/root/xray/send_backup.py)
cat << 'EOF' > /root/xray/send_backup.py
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
    
    url_doc = f"https://api.telegram.org/bot{token}/sendDocument"
    with open(b_file, "rb") as doc:
        requests.post(url_doc, data={"chat_id": admin_id, "caption": "📦 *File Backup Data VMess*\nCara Restore di Telegram: Kirim/upload balik file ini ke bot."}, files={"document": doc}, timeout=30)
        
    url_msg = f"https://api.telegram.org/bot{token}/sendMessage"
    caption_b64 = (
        "📋 *KODE BACKUP BASE64 (Untuk Terminal)*\n\n"
        "Salin teks di bawah ini untuk restore di terminal menu `[7] -> [3]` pada VPS baru:\n\n"
        f"`{b64_str}`"
    )
    requests.post(url_msg, json={"chat_id": admin_id, "text": caption_b64, "parse_mode": "Markdown"}, timeout=30)
    
    print("✅ Berhasil! File .json DAN Kode Base64 telah dikirim ke Telegram kamu.")
except Exception as e:
    print(f"❌ Gagal mengirim backup: {str(e)}")
EOF

# 9. Buat Script Bot Telegram & Daemon Expired (/root/xray/bot_daemon.py)
cat << 'EOF' > /root/xray/bot_daemon.py
import requests
import json
import os
import time
import datetime
import subprocess
import threading
import urllib.parse

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
    subprocess.run("fuser -k 23333/tcp", shell=True)
    subprocess.Popen("env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c /root/xray/config.json > /root/xray/xray.log 2>&1", shell=True)

def generate_link(name, uuid, domain):
    import base64
    cfg = {
        "v": "2", "ps": name, "add": domain, "port": "443",
        "id": uuid, "aid": "0", "scy": "auto", "net": "ws",
        "type": "none", "host": domain, "path": "/vmess-railway",
        "tls": "tls", "sni": domain
    }
    return "vmess://" + base64.b64encode(json.dumps(cfg).encode()).decode()

def check_expired_loop(token=None, admin_id=None):
    while True:
        try:
            if os.path.exists(USERS_FILE) and os.path.exists(CONFIG_FILE):
                with open(USERS_FILE) as f: users = json.load(f)
                with open(CONFIG_FILE) as f: config = json.load(f)
                
                today = datetime.date.today().strftime('%Y-%m-%d')
                expired = []
                for u, val in list(users.items()):
                    if val.get('exp') and val['exp'] < today:
                        expired.append(u)
                        del users[u]
                
                if expired:
                    clients = config['inbounds'][0]['settings']['clients']
                    config['inbounds'][0]['settings']['clients'] = [c for c in clients if c.get('email') not in expired]
                    with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)
                    with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
                    restart_xray()
                    if token and admin_id:
                        for exp_u in expired:
                            msg = f"⚠️ *Notifikasi Kadaluarsa:*\nAkun `{exp_u}` telah kadaluarsa ({today}) dan otomatis dihapus."
                            requests.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": admin_id, "text": msg, "parse_mode": "Markdown"})
        except Exception:
            pass
        time.sleep(3600)

def main():
    if not os.path.exists(BOT_CFG):
        check_expired_loop()
        return

    with open(BOT_CFG) as f: bcfg = json.load(f)
    TOKEN = bcfg.get("token")
    ADMIN_ID = int(bcfg.get("admin_id", 0))

    if not TOKEN or not ADMIN_ID:
        check_expired_loop()
        return

    threading.Thread(target=check_expired_loop, args=(TOKEN, ADMIN_ID), daemon=True).start()

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
            [{"text": "➕ Buat Akun", "callback_data": "bot_create"}, {"text": "📋 List Akun", "callback_data": "bot_list"}],
            [{"text": "🔄 Perpanjang", "callback_data": "bot_renew"}, {"text": "🗑️ Hapus Akun", "callback_data": "bot_delete"}],
            [{"text": "📦 Backup Data", "callback_data": "bot_backup"}, {"text": "⚡ Status Server", "callback_data": "bot_status"}]
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
                            text = "📋 *Daftar Akun VMess Aktif:*\n\n"
                            today = datetime.date.today()
                            for u, v in users.items():
                                exp_date = datetime.datetime.strptime(v['exp'], '%Y-%m-%d').date()
                                sisa = (exp_date - today).days
                                status = f"{sisa} hari lagi" if sisa >= 0 else "Kadaluarsa"
                                text += f"👤 `{u}`\n📅 Exp: `{v['exp']}` ({status})\n🔑 UUID: `{v['uuid']}`\n\n"
                            send_msg(cid, text)

                    elif data == "bot_status":
                        dom = get_domain()
                        with open(USERS_FILE) as f: ucount = len(json.load(f))
                        send_msg(cid, f"⚡ *Status Server:*\n🔹 Domain: `{dom}`\n🔹 Total Akun: `{ucount}`\n🔹 Port: `443` (TLS)\n🔹 Service: `Running`")

                    elif data == "bot_backup":
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
                        send_msg(cid, f"📋 *KODE BACKUP BASE64 (Untuk Terminal)*\n\nSalin teks ini untuk menu terminal [7] -> [3]:\n\n`{b64_str}`")

                    elif data == "bot_create":
                        user_state[cid] = "create"
                        send_msg(cid, "📝 Format: `nama durasi_hari`\nContoh: `budi 30`")

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
                    fid = doc["file_id"]
                    f_info = requests.get(f"{API}/getFile?file_id={fid}").json()
                    if f_info.get("ok"):
                        f_path = f_info["result"]["file_path"]
                        down = requests.get(f"https://api.telegram.org/file/bot{TOKEN}/{f_path}").content
                        try:
                            d = json.loads(down.decode())
                            if "config" in d and "users" in d:
                                with open(CONFIG_FILE, 'w') as f: json.dump(d["config"], f, indent=2)
                                with open(USERS_FILE, 'w') as f: json.dump(d["users"], f, indent=2)
                                restart_xray()
                                send_msg(cid, "🎉 *RESTORE SUKSES!* Seluruh data akun & konfigurasi telah dipulihkan.")
                            else:
                                send_msg(cid, "❌ File bukan format backup yang valid!")
                        except Exception as e:
                            send_msg(cid, f"❌ Gagal restore: {str(e)}")

                elif "message" in upd and "text" in upd["message"]:
                    msg = upd["message"]
                    cid = msg["chat"]["id"]
                    text = msg["text"].strip()
                    if cid != ADMIN_ID: continue

                    if text in ["/start", "/menu"]:
                        user_state[cid] = None
                        send_msg(cid, "🤖 *Panel Manajemen VMess Railway Admin*\nSilakan pilih menu di bawah:", reply_markup=main_menu)
                        continue

                    state = user_state.get(cid)

                    if state == "create":
                        user_state[cid] = None
                        try:
                            parts = text.split()
                            name = parts[0]
                            days = int(parts[1]) if len(parts) > 1 else 30
                            with open(USERS_FILE) as f: users = json.load(f)
                            with open(CONFIG_FILE) as f: config = json.load(f)
                            
                            if name in users:
                                send_msg(cid, "❌ Nama user sudah terpakai!"); continue

                            import uuid as uid
                            new_id = str(uid.uuid4())
                            exp_date = (datetime.date.today() + datetime.timedelta(days=days)).strftime('%Y-%m-%d')
                            
                            users[name] = {"uuid": new_id, "exp": exp_date, "created": str(datetime.date.today())}
                            config['inbounds'][0]['settings']['clients'].append({"id": new_id, "alterId": 0, "email": name})
                            
                            with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)
                            with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
                            restart_xray()
                            
                            dom = get_domain()
                            link = generate_link(name, new_id, dom)
                            qr_url = f"https://api.qrserver.com/v1/create-qr-code/?size=350x350&data={urllib.parse.quote(link)}"
                            
                            caption = (
                                f"🎉 *Akun VMess Berhasil Dibuat!*\n\n"
                                f"🔹 User : `{name}`\n"
                                f"🔹 Expired : `{exp_date}` ({days} Hari)\n"
                                f"🔹 Domain : `{dom}`\n"
                                f"🔹 Port : `443`\n"
                                f"🔹 UUID : `{new_id}`\n\n"
                                f"📌 *Link VMess:*\n`{link}`"
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
                            
                            cur_exp = datetime.datetime.strptime(users[name]['exp'], '%Y-%m-%d').date()
                            base_date = max(cur_exp, datetime.date.today())
                            new_exp = (base_date + datetime.timedelta(days=days)).strftime('%Y-%m-%d')
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
                            clients = config['inbounds'][0]['settings']['clients']
                            config['inbounds'][0]['settings']['clients'] = [c for c in clients if c.get('email') != name]
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

# 10. Pasang Script Menu CLI Lengkap (/usr/local/bin/menu)
cat << 'EOF' > /usr/local/bin/menu
#!/bin/bash

export XRAY_LOCATION_ASSET="/root/xray"
CONFIG_FILE="/root/xray/config.json"
USERS_FILE="/root/xray/users.json"
BOT_CFG="/root/xray/bot_config.json"
MODE_FILE="/root/xray/mode.txt"
DOMAIN_FILE="/root/xray/domain.txt"
QUICK_LOG="/root/xray/quick_tunnel.log"

restart_xray() {
    pkill -f "/root/xray/xray" 2>/dev/null
    fuser -k 23333/tcp 2>/dev/null
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

make_link() {
    local u_name="$1"
    local u_id="$2"
    local domain=$(get_current_domain)

    if [[ "$domain" == *"Menghubungkan"* ]] || [ "$domain" == "Belum-diatur" ]; then
        echo "❌ Domain belum siap/aktif. Atur di menu opsi [6]."
        return
    fi

    local v_json=$(cat << JSON
{
  "v": "2",
  "ps": "$u_name",
  "add": "$domain",
  "port": "443",
  "id": "$u_id",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "$domain",
  "path": "/vmess-railway",
  "tls": "tls",
  "sni": "$domain"
}
JSON
)
    echo "vmess://$(echo -n "$v_json" | base64 -w 0)"
}

while true; do
    CUR_MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "quick")
    CUR_DOM=$(get_current_domain)
    TOTAL_ACC=$(jq '.inbounds[0].settings.clients | length' "$CONFIG_FILE" 2>/dev/null || echo 0)

    pgrep -f "/root/xray/xray" > /dev/null && STAT_X="\033[1;32m[ AKTIF ]\033[0m" || STAT_X="\033[1;31m[ MATI ]\033[0m"
    pgrep -f "cloudflared" > /dev/null && STAT_T="\033[1;32m[ AKTIF ]\033[0m" || STAT_T="\033[1;31m[ MATI ]\033[0m"
    pgrep -f "bot_daemon.py" > /dev/null && STAT_B="\033[1;32m[ AKTIF ]\033[0m" || STAT_B="\033[1;33m[ NONAKTIF ]\033[0m"

    echo ""
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e "        \033[1;33m⚡ VMESS XRAY ULTIMATE PANEL (RAILWAY) ⚡\033[0m"
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e " 🔹 Xray Service : $STAT_X"
    echo -e " 🔹 Cloudflare   : $STAT_T (Mode: \033[1;35m$CUR_MODE\033[0m)"
    echo -e " 🔹 Bot Telegram : $STAT_B"
    echo -e " 🔹 Domain / SNI : \033[1;36m$CUR_DOM\033[0m"
    echo -e " 🔹 Total Akun   : \033[1;32m$TOTAL_ACC Akun\033[0m"
    echo -e "\033[1;34m=====================================================\033[0m"
    echo -e " [1] Buat Akun VMess Baru (Durasi Hari)"
    echo -e " [2] Hapus Akun VMess"
    echo -e " [3] Perpanjang Masa Aktif Akun (Renew)"
    echo -e " [4] Lihat Detail Akun, Sisa Hari & QR Code"
    echo -e " [5] Ganti / Custom UUID Akun"
    echo -e " [6] Atur Domain (Domain Sendiri / Quick Tunnel)"
    echo -e " [7] \033[1;36mBackup & Restore (Opsi A: Telegram / Opsi B: Base64)\033[0m"
    echo -e " [8] \033[1;35mIntegrasi Bot Telegram Admin (Setup Token & ID)\033[0m"
    echo -e " [9] Restart Semua Service"
    echo -e " \033[1;31m[10] Hapus Script Total (Reset VPS Bersih)\033[0m"
    echo -e " [0] Keluar"
    echo -e "\033[1;34m=====================================================\033[0m"
    read -p "Pilih Opsi [0-10]: " opt

    case $opt in
        1)
            echo ""
            echo -e "\033[1;33m--- BUAT AKUN VMESS BARU ---\033[0m"
            read -p "Masukkan Nama User: " new_name
            [ -z "$new_name" ] && { echo -e "❌ Nama tidak boleh kosong!"; sleep 1.5; continue; }

            exists=$(jq --arg u "$new_name" '.inbounds[0].settings.clients[] | select(.email == $u)' "$CONFIG_FILE" 2>/dev/null)
            if [ -n "$exists" ]; then
                echo -e "❌ User '$new_name' sudah ada!"; read -p "Tekan [Enter] untuk kembali..." dummy; continue
            fi

            read -p "Masa aktif berapa hari? (default 30): " dur_days
            [ -z "$dur_days" ] && dur_days=30

            new_id=$(python3 -c "import uuid; print(uuid.uuid4())")
            exp_date=$(python3 -c "import datetime; print((datetime.date.today() + datetime.timedelta(days=$dur_days)).strftime('%Y-%m-%d'))")

            jq --arg u "$new_name" --arg id "$new_id" '.inbounds[0].settings.clients += [{"id": $id, "alterId": 0, "email": $u}]' "$CONFIG_FILE" > /tmp/c.json && mv /tmp/c.json "$CONFIG_FILE"
            jq --arg u "$new_name" --arg id "$new_id" --arg exp "$exp_date" --arg cr "$(date +%Y-%m-%d)" '.[$u] = {"uuid": $id, "exp": $exp, "created": $cr}' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"

            restart_xray
            link=$(make_link "$new_name" "$new_id")
            cur_dom=$(get_current_domain)

            clear
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e "          🎉 \033[1;32mAKUN VMESS BERHASIL DIBUAT!\033[0m 🎉"
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e " 🔹 User     : \033[1;37m$new_name\033[0m"
            echo -e " 🔹 Expired  : \033[1;33m$exp_date ($dur_days Hari)\033[0m"
            echo -e " 🔹 Domain   : \033[1;36m$cur_dom\033[0m"
            echo -e " 🔹 Port     : \033[1;37m443\033[0m"
            echo -e " 🔹 UUID     : \033[1;33m$new_id\033[0m"
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e " 📱 \033[1;33mSCAN QR CODE LANGSUNG DARI HP:\033[0m"
            qrencode -t ANSIUTF8 "$link"
            echo -e "\033[1;32m=====================================================\033[0m"
            echo -e " 📌 \033[1;33mLINK VMESS:\033[0m"
            echo -e "\033[1;36m$link\033[0m"
            echo -e "\033[1;32m=====================================================\033[0m"
            read -p " 👉 Tekan [ENTER] jika sudah selesai copy/scan untuk kembali ke menu..." dummy
            ;;
        2)
            echo -e "\n--- HAPUS AKUN ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do echo " [$((i+1))] ${list_u[$i]}"; done
            read -p "Pilih Nomor yang ingin dihapus: " d_idx
            if [ -n "$d_idx" ] && [ "$d_idx" -le "${#list_u[@]}" ] && [ "$d_idx" -ge 1 ]; then
                target="${list_u[$((d_idx-1))]}"
                jq --arg u "$target" '.inbounds[0].settings.clients |= map(select(.email != $u))' "$CONFIG_FILE" > /tmp/c.json && mv /tmp/c.json "$CONFIG_FILE"
                jq --arg u "$target" 'del(.[$u])' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"
                restart_xray
                echo "✅ Akun '$target' berhasil dihapus!"
            else
                echo "❌ Pilihan tidak valid."
            fi
            read -p "Tekan [Enter] untuk kembali..." dummy
            ;;
        3)
            echo -e "\n--- PERPANJANG AKUN (RENEW) ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do
                u="${list_u[$i]}"
                cur_exp=$(jq -r --arg u "$u" '.[$u].exp // "Unknown"' "$USERS_FILE")
                echo " [$((i+1))] $u (Exp: $cur_exp)"
            done
            read -p "Pilih Nomor akun: " r_idx
            if [ -n "$r_idx" ] && [ "$r_idx" -le "${#list_u[@]}" ] && [ "$r_idx" -ge 1 ]; then
                target="${list_u[$((r_idx-1))]}"
                read -p "Tambah masa aktif berapa hari?: " add_days
                [ -z "$add_days" ] && add_days=30
                new_exp=$(python3 -c "
import datetime, json
with open('$USERS_FILE') as f: u = json.load(f)
c_exp = datetime.datetime.strptime(u.get('$target', {}).get('exp', '$(date +%Y-%m-%d)'), '%Y-%m-%d').date()
base = max(c_exp, datetime.date.today())
print((base + datetime.timedelta(days=$add_days)).strftime('%Y-%m-%d'))
")
                jq --arg u "$target" --arg exp "$new_exp" '.[$u].exp = $exp' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"
                echo "✅ Akun '$target' berhasil diperpanjang hingga: $new_exp!"
            fi
            read -p "Tekan [Enter] untuk kembali..." dummy
            ;;
        4)
            echo -e "\n--- DAFTAR AKUN & DETAIL ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do
                u="${list_u[$i]}"
                exp_date=$(jq -r --arg u "$u" '.[$u].exp // "Unknown"' "$USERS_FILE")
                echo " [$((i+1))] $u | Exp: $exp_date"
            done
            read -p "Pilih Nomor untuk melihat link & QR: " s_idx
            if [ -n "$s_idx" ] && [ "$s_idx" -le "${#list_u[@]}" ] && [ "$s_idx" -ge 1 ]; then
                target="${list_u[$((s_idx-1))]}"
                target_id=$(jq -r --arg u "$target" '.inbounds[0].settings.clients[] | select(.email == $u) | .id' "$CONFIG_FILE")
                exp_date=$(jq -r --arg u "$target" '.[$u].exp // "Unknown"' "$USERS_FILE")
                link=$(make_link "$target" "$target_id")
                cur_dom=$(get_current_domain)
                
                clear
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e "               📋 \033[1;33mDETAIL AKUN VMESS\033[0m"
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e " 🔹 User     : \033[1;37m$target\033[0m"
                echo -e " 🔹 Expired  : \033[1;33m$exp_date\033[0m"
                echo -e " 🔹 Domain   : \033[1;36m$cur_dom\033[0m"
                echo -e " 🔹 UUID     : \033[1;33m$target_id\033[0m"
                echo -e " 🔹 Port     : \033[1;37m443 (TLS)\033[0m"
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e " 📱 \033[1;33mSCAN QR CODE DARI HP:\033[0m"
                qrencode -t ANSIUTF8 "$link"
                echo -e "\033[1;34m=====================================================\033[0m"
                echo -e " 📌 \033[1;33mLINK VMESS:\033[0m"
                echo -e "\033[1;36m$link\033[0m"
                echo -e "\033[1;34m=====================================================\033[0m"
                read -p " 👉 Tekan [ENTER] jika sudah selesai..." dummy
            fi
            ;;
        5)
            echo -e "\n--- GANTI / CUSTOM UUID ---"
            mapfile -t list_u < <(jq -r '.inbounds[0].settings.clients[].email' "$CONFIG_FILE")
            for i in "${!list_u[@]}"; do echo " [$((i+1))] ${list_u[$i]}"; done
            read -p "Pilih Nomor akun: " c_idx
            if [ -n "$c_idx" ] && [ "$c_idx" -le "${#list_u[@]}" ] && [ "$c_idx" -ge 1 ]; then
                target="${list_u[$((c_idx-1))]}"
                read -p "Masukkan UUID Baru (Enter untuk auto random): " custom_uuid
                [ -z "$custom_uuid" ] && custom_uuid=$(python3 -c "import uuid; print(uuid.uuid4())")
                jq --arg u "$target" --arg id "$custom_uuid" '(.inbounds[0].settings.clients[] | select(.email == $u)).id = $id' "$CONFIG_FILE" > /tmp/c.json && mv /tmp/c.json "$CONFIG_FILE"
                jq --arg u "$target" --arg id "$custom_uuid" '.[$u].uuid = $id' "$USERS_FILE" > /tmp/u.json && mv /tmp/u.json "$USERS_FILE"
                restart_xray
                echo "✅ UUID untuk '$target' berhasil diubah ke: $custom_uuid"
            fi
            read -p "Tekan [Enter] untuk kembali..." dummy
            ;;
        6)
            echo -e "\n\033[1;33m--- PENGATURAN DOMAIN CLOUDFLARE ---\033[0m"
            echo " [1] Pakai Domain Sendiri (Login Cloudflare via Browser)"
            echo " [2] Pakai Quick Tunnel Gratis (*.trycloudflare.com)"
            read -p "Pilih [1/2]: " dom_opt
            if [ "$dom_opt" == "1" ]; then
                echo -e "\n\033[1;36m=====================================================\033[0m"
                echo -e "🔑 \033[1;33mLANGKAH LOGIN CLOUDFLARE:\033[0m"
                echo "1. Buka link resmi Cloudflare di bawah ini pada browser."
                echo "2. Pilih domain kamu dan klik Authorize."
                echo -e "\033[1;36m=====================================================\033[0m\n"
                
                /root/cloudflared tunnel login

                if [ ! -f /root/.cloudflared/cert.pem ]; then
                    echo "❌ Login dibatalkan atau cert.pem tidak ditemukan."
                    read -p "Tekan [Enter] untuk kembali..." dummy; continue
                fi

                echo -e "\n\033[1;32m✅ Berhasil login ke akun Cloudflare!\033[0m"
                read -p "Masukkan Subdomain kamu (Contoh: sgdo4.mamzvpn.com): " custom_dom
                [ -z "$custom_dom" ] && { echo "Domain kosong!"; continue; }

                pkill -f "cloudflared" 2>/dev/null
                /root/cloudflared tunnel delete -f railway-tunnel 2>/dev/null
                /root/cloudflared tunnel create railway-tunnel
                /root/cloudflared tunnel route dns railway-tunnel "$custom_dom"

                nohup /root/cloudflared tunnel run --url http://127.0.0.1:23333 railway-tunnel > /dev/null 2>&1 &
                echo "$custom_dom" > "$DOMAIN_FILE"
                echo "custom" > "$MODE_FILE"

                echo -e "\n\033[1;32m🎉 SUKSES! Domain '$custom_dom' sekarang AKTIF PERMANEN!\033[0m"
                read -p "Tekan [Enter] untuk kembali..." dummy

            elif [ "$dom_opt" == "2" ]; then
                pkill -f "cloudflared" 2>/dev/null
                rm -f "$QUICK_LOG"
                nohup /root/cloudflared tunnel --url http://127.0.0.1:23333 --logfile "$QUICK_LOG" > /dev/null 2>&1 &
                echo "quick" > "$MODE_FILE"
                echo "Menunggu koneksi siap 6 detik..."
                sleep 6
            fi
            ;;
        7)
            echo -e "\n\033[1;33m--- BACKUP & RESTORE DATA ---\033[0m"
            echo " [1] Opsi A: Kirim File Backup ke Telegram Admin"
            echo " [2] Opsi B: Buat Kode Teks Base64 (Simpan di Catatan)"
            echo " [3] Restore dari Kode Teks Base64"
            read -p "Pilih Opsi [1-3]: " b_opt

            if [ "$b_opt" == "1" ]; then
                python3 /root/xray/send_backup.py
                read -p "Tekan [Enter] untuk kembali..." dummy

            elif [ "$b_opt" == "2" ]; then
                b_str=$(python3 -c "
import json, base64
b_data = {'config': json.load(open('$CONFIG_FILE')), 'users': json.load(open('$USERS_FILE'))}
print(base64.b64encode(json.dumps(b_data).encode()).decode())
")
                echo -e "\n\033[1;32m=================== KODE BACKUP (COPY DI BAWAH) ===================\033[0m"
                echo "$b_str"
                echo -e "\033[1;32m===================================================================\033[0m"
                echo "💡 Salin seluruh teks di atas dan simpan di catatan HP kamu."
                read -p "Tekan [Enter] untuk kembali..." dummy

            elif [ "$b_opt" == "3" ]; then
                echo "Masukkan / Paste Kode Base64 Backup kamu di bawah ini:"
                read -p "Kode: " in_b64
                python3 -c "
import json, base64, sys
try:
    raw = base64.b64decode('$in_b64').decode()
    d = json.loads(raw)
    with open('$CONFIG_FILE', 'w') as f: json.dump(d['config'], f, indent=2)
    with open('$USERS_FILE', 'w') as f: json.dump(d['users'], f, indent=2)
    print('✅ RESTORE BERHASIL! Data akun telah dipulihkan.')
except Exception as e:
    print('❌ Kode backup tidak valid!')
"
                restart_xray
                read -p "Tekan [Enter] untuk kembali..." dummy
            fi
            ;;
        8)
            echo -e "\n\033[1;33m--- INTEGRASI BOT TELEGRAM ADMIN ---\033[0m"
            echo "Dapatkan Bot Token dari @BotFather dan ID kamu dari @userinfobot"
            read -p "Masukkan Token Bot Telegram: " in_tok
            read -p "Masukkan ID Telegram Admin: " in_aid
            if [ -n "$in_tok" ] && [ -n "$in_aid" ]; then
                echo "{\"token\": \"$in_tok\", \"admin_id\": $in_aid}" > "$BOT_CFG"
                restart_bot
                echo -e "\n✅ \033[1;32mBot Telegram Berhasil Dikonfigurasi & Dinyalakan!\033[0m"
                echo "Silakan buka Telegram kamu dan kirim pesan: /start"
            else
                echo "❌ Token atau ID tidak boleh kosong!"
            fi
            read -p "Tekan [Enter] untuk kembali..." dummy
            ;;
        9)
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
            echo "✅ Semua service sudah direstart!"
            sleep 2
            ;;
        10)
            echo -e "\n\033[1;31m=====================================================\033[0m"
            echo -e "⚠️  \033[1;33mPERINGATAN: RESET TOTAL VPS\033[0m"
            echo -e "Seluruh akun VMess, binary Xray, Cloudflare, Bot,"
            echo -e "dan file menu ini akan DIHAPUS BERSIH dari sistem."
            echo -e "\033[1;31m=====================================================\033[0m"
            read -p "Apakah kamu yakin ingin menghapus total? (y/n): " confirm_del
            if [[ "$confirm_del" =~ ^[Yy]$ ]]; then
                echo -e "\n⏳ Sedang membersihkan sistem..."
                pkill -f "/root/xray/xray" 2>/dev/null
                pkill -f "cloudflared" 2>/dev/null
                pkill -f "bot_daemon.py" 2>/dev/null
                fuser -k 23333/tcp 2>/dev/null
                rm -rf /root/xray /root/.cloudflared /root/cloudflared /usr/local/bin/menu /root/install.sh
                echo -e "\033[1;32m✅ BERHASIL DIHAPUS TOTAL!\033[0m"
                echo "VPS kamu sekarang sudah bersih seperti baru deploy."
                exit 0
            else
                echo "Dibatalkan."
            fi
            ;;
        0)
            exit 0
            ;;
    esac
done
EOF

chmod +x /usr/local/bin/menu

# 11. Nyalakan Service Awal
export XRAY_LOCATION_ASSET="/root/xray"
nohup env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c /root/xray/config.json > /root/xray/xray.log 2>&1 &
echo "quick" > /root/xray/mode.txt
nohup /root/cloudflared tunnel --url http://127.0.0.1:23333 --logfile /root/xray/quick_tunnel.log > /dev/null 2>&1 &
nohup python3 /root/xray/bot_daemon.py > /root/xray/bot.log 2>&1 &

sleep 2

echo "=========================================================="
if pgrep -f "/root/xray/xray" > /dev/null; then
    echo -e "🎉 STATUS XRAY: \033[1;32m[ AKTIF / BERJALAN ]\033[0m"
else
    echo -e "❌ Xray Log Error: $(cat /root/xray/xray.log)"
fi
echo "=========================================================="

