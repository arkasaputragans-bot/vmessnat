cat << 'EOF' > /root/xray/cleaner_daemon.py
# -*- coding: utf-8 -*-
# ========================================================
# CLEANER DAEMON - Auto-Delete Akun Expired Otomatis
# (Terpisah dari bot daemon, agar 100% anti-crash)
# ========================================================
import json, os, datetime, subprocess, time, requests

CONFIG_FILE = "/root/xray/config.json"
USERS_FILE = "/root/xray/users.json"
BOT_CFG = "/root/xray/bot_config.json"

def log(msg):
    print(f"[CLEANER {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def restart_xray():
    subprocess.run("pkill -9 -f '/root/xray/xray run'", shell=True)
    subprocess.run("fuser -k -9 23331/tcp 23332/tcp 23334/tcp 2>/dev/null", shell=True)
    subprocess.Popen("env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c /root/xray/config.json > /root/xray/xray.log 2>&1", shell=True)

def get_telegram():
    try:
        if os.path.exists(BOT_CFG):
            with open(BOT_CFG) as f:
                b = json.load(f)
            return b.get('token'), b.get('admin_id')
    except: pass
    return None, None

def cleanup_expired():
    if not (os.path.exists(USERS_FILE) and os.path.exists(CONFIG_FILE)):
        return
    
    now_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    with open(USERS_FILE) as f:
        users = json.load(f)
    with open(CONFIG_FILE) as f:
        config = json.load(f)

    expired = []
    for u, val in users.items():
        exp_val = val.get('exp', '')
        if exp_val and exp_val < now_str:
            expired.append(u)

    if not expired:
        return

    log(f"Menemukan {len(expired)} akun expired: {', '.join(expired)}")

    # Hapus dari users.json
    for u in expired:
        if u in users:
            del users[u]

    # Hapus dari config.json (skip inbound tanpa 'clients')
    for i in range(len(config.get('inbounds', []))):
        settings = config['inbounds'][i].get('settings', {})
        if 'clients' not in settings:
            continue
        settings['clients'] = [c for c in settings['clients'] if c.get('email') not in expired]

    with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
    with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)

    # Hapus user Linux (untuk akun SSH Dropbear)
    for u in expired:
        subprocess.run("userdel -f '" + u + "' 2>/dev/null", shell=True)

    # Restart Xray
    restart_xray()
    log(f"✅ {len(expired)} akun dihapus & Xray direstart. Sisa: {len(users)} akun")

    # Kirim notifikasi Telegram ke admin
    token, admin_id = get_telegram()
    if token and admin_id:
        for exp_u in expired:
            msg = f"⚠️ *Notifikasi Kadaluarsa:*\nAkun `{exp_u}` telah kadaluarsa dan otomatis dihapus."
            try:
                requests.post(f"https://api.telegram.org/bot{token}/sendMessage", 
                              json={"chat_id": admin_id, "text": msg, "parse_mode": "Markdown"},
                              timeout=10)
            except: pass

def main():
    log("Cleaner Daemon dimulai. Cek expired setiap 60 detik.")
    while True:
        try:
            cleanup_expired()
        except Exception as e:
            log(f"ERROR: {str(e)}")
        time.sleep(60)

if __name__ == "__main__":
    main()
EOF

chmod +x /root/xray/cleaner_daemon.py
echo "✅ File cleaner_daemon.py berhasil dibuat!"

cat << 'EOF' > /root/xray/cleaner_daemon.py
# -*- coding: utf-8 -*-
# ========================================================
# CLEANER DAEMON - Auto-Delete Akun Expired Otomatis
# (Terpisah dari bot daemon, agar 100% anti-crash)
# ========================================================
import json, os, datetime, subprocess, time, requests

CONFIG_FILE = "/root/xray/config.json"
USERS_FILE = "/root/xray/users.json"
BOT_CFG = "/root/xray/bot_config.json"

def log(msg):
    print(f"[CLEANER {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}", flush=True)

def restart_xray():
    subprocess.run("pkill -9 -f '/root/xray/xray run'", shell=True)
    subprocess.run("fuser -k -9 23331/tcp 23332/tcp 23334/tcp 2>/dev/null", shell=True)
    subprocess.Popen("env XRAY_LOCATION_ASSET=/root/xray /root/xray/xray run -c /root/xray/config.json > /root/xray/xray.log 2>&1", shell=True)

def get_telegram():
    try:
        if os.path.exists(BOT_CFG):
            with open(BOT_CFG) as f:
                b = json.load(f)
            return b.get('token'), b.get('admin_id')
    except: pass
    return None, None

def cleanup_expired():
    if not (os.path.exists(USERS_FILE) and os.path.exists(CONFIG_FILE)):
        return
    
    now_str = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    with open(USERS_FILE) as f:
        users = json.load(f)
    with open(CONFIG_FILE) as f:
        config = json.load(f)

    expired = []
    for u, val in users.items():
        exp_val = val.get('exp', '')
        if exp_val and exp_val < now_str:
            expired.append(u)

    if not expired:
        return

    log(f"Menemukan {len(expired)} akun expired: {', '.join(expired)}")

    # Hapus dari users.json
    for u in expired:
        if u in users:
            del users[u]

    # Hapus dari config.json (skip inbound tanpa 'clients')
    for i in range(len(config.get('inbounds', []))):
        settings = config['inbounds'][i].get('settings', {})
        if 'clients' not in settings:
            continue
        settings['clients'] = [c for c in settings['clients'] if c.get('email') not in expired]

    with open(USERS_FILE, 'w') as f: json.dump(users, f, indent=2)
    with open(CONFIG_FILE, 'w') as f: json.dump(config, f, indent=2)

    # Hapus user Linux (untuk akun SSH Dropbear)
    for u in expired:
        subprocess.run("userdel -f '" + u + "' 2>/dev/null", shell=True)

    # Restart Xray
    restart_xray()
    log(f"✅ {len(expired)} akun dihapus & Xray direstart. Sisa: {len(users)} akun")

    # Kirim notifikasi Telegram ke admin
    token, admin_id = get_telegram()
    if token and admin_id:
        for exp_u in expired:
            msg = f"⚠️ *Notifikasi Kadaluarsa:*\nAkun `{exp_u}` telah kadaluarsa dan otomatis dihapus."
            try:
                requests.post(f"https://api.telegram.org/bot{token}/sendMessage", 
                              json={"chat_id": admin_id, "text": msg, "parse_mode": "Markdown"},
                              timeout=10)
            except: pass

def main():
    log("Cleaner Daemon dimulai. Cek expired setiap 60 detik.")
    while True:
        try:
            cleanup_expired()
        except Exception as e:
            log(f"ERROR: {str(e)}")
        time.sleep(60)

if __name__ == "__main__":
    main()
EOF

chmod +x /root/xray/cleaner_daemon.py
echo "✅ File cleaner_daemon.py berhasil dibuat!"
