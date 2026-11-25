# msg-via-wifi
# PC Chat

Encrypted, peer-to-peer chat between two Windows PCs on the same network.
One file (`PCChat.bat`), no manual setup.

## Features

- Installs Python automatically if missing (winget, then python.org fallback)
- Encrypted with TLS (ephemeral certificate, ECDSA P-256, TLS 1.2+)
- Security code to detect a man-in-the-middle
- Large chat window (18 pt), resizable with `Ctrl +`, `Ctrl -`, `Ctrl + mouse wheel`
- Notifications for incoming messages when the window is not focused:
  sound, taskbar flash, `(n)` unread counter in the title, Windows toast
- **Sound toggle** button (or `Ctrl + M`) for public spaces. When muted, the
  beep and the toast sound are off, while the flash, title counter and silent
  toast still work. The setting is remembered between runs.

## Requirements

- Windows 10 or 11, both PCs on the same LAN
- Network profile set to **Private** (Settings > Network & Internet > your connection)
- No router "client isolation" (common on guest Wi-Fi)
- Internet access on first run only (Python and the `cryptography` library)

## Usage

1. Copy `PCChat.bat` to both PCs and double-click it. For the first run, use
   **Run as administrator** so the firewall rule is created. Otherwise click
   **Allow** (Private networks) on the Windows firewall popup.
2. Enter your username and the other PC's IP. Your own IP is shown in the
   dialog, so exchange them by call or text. Start order does not matter.
3. When the green line `ENCRYPTED (TLS). Security code: XXXX-XXXX-XXXX-XXXX`
   appears, **read the code aloud to the other person**. It must be identical
   on both screens. If it differs, close the chat: someone is intercepting.
4. Type in the bottom field and press Enter. Close the window to quit.

## How it works

| Topic | Design |
|---|---|
| Roles | Same script on both PCs. The PC with the numerically lower IP connects, the higher one listens, so no coordination or collisions. |
| Framing | One message per line (`\n`), read through `makefile()` so TCP chunking cannot split messages. |
| Encryption | The listener generates a throwaway self-signed certificate (valid 1 day, files deleted right after loading). |
| Authentication | The security code is the first 64 bits of the SHA-256 of the certificate, compared out of band. |
| Stranger filter | The listener closes any connection whose IP is not the one you typed. |
| Threads | The network runs in a worker thread and talks to the Tk UI only through a `queue`. |
| Toast safety | Incoming text is quote-escaped and truncated before reaching PowerShell, so a peer cannot inject commands. |
| Python source | Embedded after the `###PYTHON-START###` marker, extracted to `%TEMP%\pcchat.py` at launch. |

## Troubleshooting

| Symptom | Fix |
|---|---|
| Stuck on "Waiting for the other PC to start..." | Check the IP, and that the other PC is running the chat. |
| Cannot connect | From the other PC: `Test-NetConnection <host-ip> -Port 5000`. Failure means firewall, Public network profile, or client isolation. |
| No toast pop-up | Focus Assist / Do Not Disturb is on. Sound, flash and title still work. |
| Security code differs | Do not chat. Restart both sides. Persistent mismatch means interception on the network. |
| `cryptography` install fails | Check internet access, then rerun. |

## Limits

- One-to-one only, no message history, new key every session
- Security depends on actually comparing the code
- The firewall rule opens TCP 5000 on Private networks. Remove it with:
  `netsh advfirewall firewall delete rule name="PC Chat"`

## Files

- `PCChat.bat`: launcher plus embedded Python app
- `%APPDATA%\pcchat_sound.txt`: remembered sound setting (`on` / `off`)
