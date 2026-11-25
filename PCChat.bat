@echo off
setlocal
title PC Chat

set "PY="
where python >nul 2>&1 && python -c "pass" >nul 2>&1 && set "PY=python"

if not defined PY (
  echo [1/4] Installing Python...
  winget install -e --id Python.Python.3.12 --scope user --silent --accept-package-agreements --accept-source-agreements
  call :findpy
)
if not defined PY (
  echo winget unavailable, downloading from python.org...
  powershell -NoProfile -Command "Invoke-WebRequest https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe -OutFile $env:TEMP\pyinst.exe"
  "%TEMP%\pyinst.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0
  call :findpy
)
if not defined PY (
  echo Python install failed. Install it manually from python.org
  pause
  exit /b 1
)

echo [2/4] Installing encryption library...
"%PY%" -m pip install --quiet --disable-pip-version-check cryptography
"%PY%" -c "import cryptography" >nul 2>&1
if errorlevel 1 (
  echo Could not install the "cryptography" library. Check your internet connection.
  pause
  exit /b 1
)

echo [3/4] Opening firewall port 5000 (Admin needed, otherwise click Allow on the popup)...
netsh advfirewall firewall add rule name="PC Chat" dir=in action=allow protocol=TCP localport=5000 profile=private >nul 2>&1

echo [4/4] Starting chat...
powershell -NoProfile -Command "$t=[IO.File]::ReadAllText('%~f0'); $i=$t.IndexOf('###PYTHON'+'-START###'); [IO.File]::WriteAllText('%TEMP%\pcchat.py',$t.Substring($i+18).TrimStart())"
"%PY%" "%TEMP%\pcchat.py"
exit /b

:findpy
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do if exist "%%D\python.exe" set "PY=%%D\python.exe"
exit /b

###PYTHON-START###
import os, socket, ssl, threading, queue, hashlib, ipaddress, tempfile, datetime, time
import ctypes, subprocess, winsound
import tkinter as tk
from tkinter import simpledialog, font as tkfont

PORT = 5000
q = queue.Queue()

def my_ip(target="8.8.8.8"):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect((target, 9))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return socket.gethostbyname(socket.gethostname())

def make_cert():
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    key = ec.generate_private_key(ec.SECP256R1())
    nm = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "pcchat")])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(nm).issuer_name(nm)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(minutes=5))
            .not_valid_after(now + datetime.timedelta(days=1))
            .sign(key, hashes.SHA256()))
    d = tempfile.mkdtemp()
    c, k = os.path.join(d, "c.pem"), os.path.join(d, "k.pem")
    with open(c, "wb") as f:
        f.write(cert.public_bytes(serialization.Encoding.PEM))
    with open(k, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.PEM,
                serialization.PrivateFormat.PKCS8, serialization.NoEncryption()))
    return c, k, cert.public_bytes(serialization.Encoding.DER)

def code(der):
    h = hashlib.sha256(der).hexdigest()[:16].upper()
    return "-".join(h[i:i+4] for i in range(0, 16, 4))

def network(peer, state):
    try:
        if ipaddress.ip_address(my_ip(peer)) < ipaddress.ip_address(peer):
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE
            ctx.minimum_version = ssl.TLSVersion.TLSv1_2
            while True:
                try:
                    raw = socket.create_connection((peer, PORT), timeout=5)
                    raw.settimeout(10)
                    s = ctx.wrap_socket(raw)
                    break
                except OSError:
                    q.put(("sys", "Waiting for the other PC to start..."))
                    time.sleep(2)
            der = s.getpeercert(True)
        else:
            c, k, der = make_cert()
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.minimum_version = ssl.TLSVersion.TLSv1_2
            ctx.load_cert_chain(c, k)
            os.remove(c); os.remove(k)
            srv = socket.create_server(("0.0.0.0", PORT))
            q.put(("sys", f"Waiting for {peer} on port {PORT}..."))
            while True:
                raw, addr = srv.accept()
                if addr[0] != peer:
                    raw.close()
                    q.put(("sys", f"Rejected stranger {addr[0]}"))
                    continue
                try:
                    raw.settimeout(10)
                    s = ctx.wrap_socket(raw, server_side=True)
                    break
                except (ssl.SSLError, OSError):
                    raw.close()
            srv.close()
        s.settimeout(None)
        state["sock"] = s
        q.put(("sys", f"ENCRYPTED (TLS). Security code: {code(der)}\n"
                      "Read this code aloud to the other person. It must be identical on both screens."))
        with s.makefile("r", encoding="utf-8") as f:
            for line in f:
                q.put(("msg", line.rstrip()))
        q.put(("sys", "[Peer left]"))
    except Exception as e:
        q.put(("sys", f"Error: {e}"))

# ---------- UI ----------
root = tk.Tk()
root.withdraw()
default = os.environ.get("USERNAME", "anon")
name = simpledialog.askstring("PC Chat", "Your username:", initialvalue=default, parent=root) or default
mine = my_ip()
peer = simpledialog.askstring("PC Chat", f"Your IP is {mine} (give it to the other person).\n\nOther PC's IP:", parent=root)
if not peer:
    raise SystemExit
peer = peer.strip()

base_title = f"PC Chat - {name} ({mine})"
root.title(base_title)
root.geometry("900x650")
root.deiconify()
fnt = tkfont.Font(family="Segoe UI", size=18)
log = tk.Text(root, font=fnt, wrap="word", state="disabled", padx=10, pady=10)
log.tag_config("sys", foreground="#0a7d33")
log.tag_config("me", foreground="#1a56db")
box = tk.Entry(root, font=fnt)
box.pack(side="bottom", fill="x", padx=6, pady=6)
bar = tk.Frame(root)
bar.pack(side="top", fill="x")
btn = tk.Button(bar, font=("Segoe UI", 12, "bold"), relief="flat", padx=14, pady=4,
                cursor="hand2", command=lambda: toggle_sound())
btn.pack(side="right", padx=6, pady=4)
log.pack(side="top", fill="both", expand=True)
box.focus()

def add(text, tag=None):
    log.config(state="normal")
    log.insert("end", text + "\n", tag)
    log.config(state="disabled")
    log.see("end")

def zoom(d):
    fnt.configure(size=max(8, min(60, fnt.cget("size") + d)))

root.bind("<Control-plus>", lambda e: zoom(2))
root.bind("<Control-equal>", lambda e: zoom(2))
root.bind("<Control-minus>", lambda e: zoom(-2))
root.bind("<Control-MouseWheel>", lambda e: zoom(2 if e.delta > 0 else -2))

# ---------- Notifications ----------
unread = 0

class FLASHWINFO(ctypes.Structure):
    _fields_ = [("cbSize", ctypes.c_uint), ("hwnd", ctypes.c_void_p),
                ("dwFlags", ctypes.c_uint), ("uCount", ctypes.c_uint),
                ("dwTimeout", ctypes.c_uint)]

def flash():
    hwnd = ctypes.windll.user32.GetParent(root.winfo_id())
    fi = FLASHWINFO(ctypes.sizeof(FLASHWINFO), hwnd, 0x0F, 5, 0)  # ALL | until foreground
    ctypes.windll.user32.FlashWindowEx(ctypes.byref(fi))

def toast(title, text, silent=False):
    esc = lambda s: s.replace("'", "''")[:200]  # untrusted text: neutralise quotes
    mute = ("$a=$x.CreateElement('audio');$a.SetAttribute('silent','true');"
            "$x.DocumentElement.AppendChild($a) | Out-Null;") if silent else ""
    ps = ("[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null;"
          "$x=[Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent('ToastText02');"
          "$n=$x.GetElementsByTagName('text');"
          + mute +
          f"$n.Item(0).AppendChild($x.CreateTextNode('{esc(title)}')) | Out-Null;"
          f"$n.Item(1).AppendChild($x.CreateTextNode('{esc(text)}')) | Out-Null;"
          "$t=[Windows.UI.Notifications.ToastNotification]::new($x);"
          "[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("
          "'{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe').Show($t)")
    subprocess.Popen(["powershell", "-NoProfile", "-WindowStyle", "Hidden", "-Command", ps],
                     creationflags=0x08000000)  # CREATE_NO_WINDOW

# Sound on/off (remembered between runs). Visual alerts stay active when muted.
SOUND_FILE = os.path.join(os.environ.get("APPDATA", tempfile.gettempdir()), "pcchat_sound.txt")
try:
    sound = {"on": open(SOUND_FILE).read().strip() != "off"}
except OSError:
    sound = {"on": True}

def refresh_btn():
    if sound["on"]:
        btn.config(text="Sound: ON  (Ctrl+M)", bg="#d1fae5", fg="#065f46", activebackground="#a7f3d0")
    else:
        btn.config(text="Sound: OFF (Ctrl+M)", bg="#e5e7eb", fg="#374151", activebackground="#d1d5db")

def toggle_sound(_=None):
    sound["on"] = not sound["on"]
    refresh_btn()
    try:
        with open(SOUND_FILE, "w") as f:
            f.write("on" if sound["on"] else "off")
    except OSError:
        pass
    add("Sound notifications " + ("ON" if sound["on"] else "OFF (silent mode)"), "sys")

root.bind("<Control-m>", toggle_sound)
refresh_btn()

def notify(line):
    global unread
    if sound["on"]:
        winsound.MessageBeep(winsound.MB_ICONASTERISK)
    if root.focus_displayof() is None:  # window not focused
        unread += 1
        root.title(f"({unread}) New message - {base_title}")
        flash()
        sender, _, body = line.partition(": ")
        toast(sender, body, silent=not sound["on"])

def on_focus(_=None):
    global unread
    unread = 0
    root.title(base_title)

root.bind("<FocusIn>", on_focus)

# ---------- Send / receive ----------
state = {}
def send(_=None):
    t = box.get().strip()
    if not t:
        return
    if "sock" not in state:
        add("Not connected yet.", "sys")
        return
    try:
        state["sock"].sendall(f"{name}: {t}\n".encode("utf-8"))
        add(f"{name}: {t}", "me")
        box.delete(0, "end")
    except OSError:
        add("Send failed.", "sys")
box.bind("<Return>", send)

def poll():
    while not q.empty():
        kind, text = q.get()
        add(text, "sys" if kind == "sys" else None)
        if kind == "msg":
            notify(text)
    root.after(100, poll)

add("Starting... (Ctrl + / Ctrl - / Ctrl+wheel = font size)", "sys")
threading.Thread(target=network, args=(peer, state), daemon=True).start()
poll()
root.mainloop()
