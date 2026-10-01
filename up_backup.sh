# 1. Matikan daemon lama
pkill -9 -f "bot_daemon.py" 2>/dev/null

# 2. TES LANGSUNG KIRIM FILE KE TELEGRAM SEKARANG
echo "=========================================================="
echo "⏳ SEDANG MENCOBA KIRIM FILE BACKUP KE TELEGRAM..."
python3 -c "
import requests, json, datetime, os

with open('/root/xray/bot_config.json') as f: b = json.load(f)
TOKEN = b['token']
ADMIN_ID = b['admin_id']

b_data = {
    'config': json.load(open('/root/xray/config.json')),
    'users': json.load(open('/root/xray/users.json')),
    'created': str(datetime.datetime.now())
}

now_str = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
b_path = f'/tmp/backup_test.json'
with open(b_path, 'w') as f:
    json.dump(b_data, f, indent=2)

caption = f'📦 *TEST AUTO-BACKUP SEKARANG*\n📅 Waktu: `{datetime.datetime.now().strftime(\"%Y-%m-%d %H:%M:%S\")}`\n👥 Total: `{len(b_data[\"users\"])} Akun`\n\n_File backup terlampir._'

with open(b_path, 'rb') as doc:
    res = requests.post(
        f'https://api.telegram.org/bot{TOKEN}/sendDocument',
        data={'chat_id': ADMIN_ID, 'caption': caption, 'parse_mode': 'Markdown'},
        files={'document': doc},
        timeout=30
    ).json()

print('Respon Resmi Telegram:', res)
if res.get('ok'):
    print('🎉 BERHASIL! File backup terkirim ke Telegram kamu!')
else:
    print('❌ Gagal kirim Telegram, alasan:', res.get('description'))
"
echo "=========================================================="

# 3. Tulis Ulang bot_daemon.py yang Pasti Jalan Auto-Backupnya
cat << 'EOF' > /root/xray/bot_daemon.py
# -*- coding: utf-8 -*-
import requests, json, os, time, datetime, subprocess, threading, urllib.parse, base64, sys

CONFIG_FILE = "/root/xray/config.json"
USERS_FILE = "/root/xray/users.json"
BOT_CFG = "/root/xray/bot_config.json"
DOMAIN_FILE = "/root/xray/domain.txt"
MODE_FILE = "/root/xray/mode.txt"
QUICK_LOG = "/root/xray/quick_tunnel.log"
INTERVAL_FILE = "/root/xray/backup_interval.txt"
LAST_FILE = "/root/xray/last_backup.txt"

def log_print(msg):
    print(f"[{datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

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
    subprocess.run("pkill -9 -f '/root/xray/xray run'", shell=True)
    subprocess.run("fuser -k -9 23331/tcp 23332/tcp 2>/dev/null", shell=True)
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

            current_day = now_dt.day
            if current_day != last_clean_day:
                last_clean_day = current_day
                subprocess.run("sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null", shell=True)
        except Exception:
            pass
        time.sleep(60)

# DAEMON AUTO-BACKUP BERKALA (FILE KE TELEGRAM)
def flexible_backup_loop(token, admin_id):
    log_print(f"Daemon Auto-Backup dimulai untuk Admin ID: {admin_id}")
    while True:
        try:
            interval_hours = 1
            if os.path.exists(INTERVAL_FILE):
                try:
                    with open(INTERVAL_FILE) as f:
                        interval_hours = int(f.read().strip())
                except:
                    interval_hours = 1

            if interval_hours > 0:
                last_time = 0
                if os.path.exists(LAST_FILE):
                    try:
                        with open(LAST_FILE) as f:
                            last_time = float(f.read().strip())
                    except:
                        last_time = 0

                now_ts = time.time()
                # Cek jika interval tercapai (atau pertama kali jalan)
                if (now_ts - last_time) >= (interval_hours * 3600):
                    log_print(f"Waktunya kirim Auto-Backup (Interval: {interval_hours} Jam)...")
                    if os.path.exists(CONFIG_FILE) and os.path.exists(USERS_FILE):
                        b_data = {
                            "config": json.load(open(CONFIG_FILE)),
                            "users": json.load(open(USERS_FILE)),
                            "created": str(datetime.datetime.now())
                        }
                        now_str = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
                        b_path = f"/tmp/backup_{now_str}.json"
                        with open(b_path, "w") as f:
                            json.dump(b_data, f, indent=2)

                        ucount = len(b_data["users"])
                        now_time = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
                        caption = (
                            f"⏰ *AUTO-BACKUP RUTIN ({interval_hours} Jam)*\n"
                            f"📅 Waktu: `{now_time}`\n"
                            f"👥 Total: `{ucount} Akun`\n\n"
                            f"_File backup terlampir. Teruskan file ini ke bot kapan saja untuk restore._"
                        )

                        with open(b_path, "rb") as doc:
                            res = requests.post(
                                f"https://api.telegram.org/bot{token}/sendDocument",
                                data={"chat_id": admin_id, "caption": caption, "parse_mode": "Markdown"},
                                files={"document": doc},
                                timeout=30
                            ).json()
                            log_print(f"Respon Pengiriman Auto-Backup: {res.get('ok')}")

                        with open(LAST_FILE, "w") as f:
                            f.write(str(now_ts))
                        try: os.remove(b_path)
                        except: pass
        except Exception as e:
            log_print(f"Error di loop backup: {str(e)}")
        time.sleep(30)

def main():
    if not os.path.exists(BOT_CFG):
        return

    with open(BOT_CFG) as f: bcfg = json.load(f)
    TOKEN = bcfg.get("token")
    ADMIN_ID = int(bcfg.get("admin_id", 0))

    if not TOKEN or not ADMIN_ID:
        return

    threading.Thread(target=check_expired_and_cleanup_loop, args=(TOKEN, ADMIN_ID), daemon=True).start()
    threading.Thread(target=flexible_backup_loop, args=(TOKEN, ADMIN_ID), daemon=True).start()

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
                                text += f"👤 `{u}`\n📅 Exp: `{exp_str}`\n🔑 UUID: `{v.get('uuid','-')}`\n\n"
                            send_msg(cid, text)

                    elif data == "bot_status":
                        dom = get_domain()
                        with open(USERS_FILE) as f: ucount = len(json.load(f))
                        send_msg(cid, f"⚡ *Status Server:*\n🔹 Domain: `{dom}`\n🔹 Total Akun: `{ucount}`\n🔹 Port: `443` (TLS)")

                    elif data == "bot_speedtest":
                        send_msg(cid, "⏳ *Sedang menjalankan Speedtest...*")
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
                        b_path = f"/tmp/backup_{datetime.date.today()}.json"
                        with open(b_path, "w") as f: json.dump(backup_data, f, indent=2)
                        send_doc(cid, b_path, "📦 *File Backup Data*\nKirim balik file ini ke bot kapan saja untuk restore.")
                        try: os.remove(b_path)
                        except: pass

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

                            new_id = str(uuid.uuid4())
                            now_dt = datetime.datetime.now()

                            if state == "trial":
                                exp_dt = now_dt + datetime.timedelta(hours=val)
                                dur_label = f"{val} Jam"
                            else:
                                exp_dt = now_dt + datetime.timedelta(days=val)
                                dur_label = f"{val} Hari"

                            exp_str = exp_dt.strftime('%Y-%m-%d %H:%M:%S')

                            users[name] = {"uuid": new_id, "exp": exp_str, "created": str(datetime.date.today())}
                            
                            for i in range(len(config.get('inbounds', []))):
                                if 'clients' in config['inbounds'][i].get('settings', {}):
                                    cls = config['inbounds'][i]['settings']['clients']
                                    config['inbounds'][i]['settings']['clients'] = [c for c in cls if c.get('email') != name]

                            config['inbounds'][0]['settings']['clients'].append({"id": new_id, "alterId": 0, "email": name})
                            if len(config['inbounds']) > 1:
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
                            subprocess.run(f"python3 /root/xray/del_user.py '{name}'", shell=True)
                            send_msg(cid, f"✅ Akun `{name}` berhasil dihapus permanen!")
                        except Exception as e:
                            send_msg(cid, f"❌ Error: {str(e)}")

        except Exception:
            time.sleep(2)

if __name__ == '__main__':
    main()
EOF

# 4. Jalankan bot_daemon dengan flag -u (Unbuffered / Log Live Langsung)
nohup python3 -u /root/xray/bot_daemon.py > /root/xray/bot.log 2>&1 &

echo "✅ Bot Daemon Baru Aktif!"
