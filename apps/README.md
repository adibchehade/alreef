# My Apps

A small Windows GUI that installs, updates and removes my usual apps with winget.

## Run it

Open PowerShell and paste:

```powershell
irm alreef.es/tools | iex
```

It asks for admin rights (UAC), then opens the window.

## What it does

- Shows each app with its status: **Installed**, **Update available** or **Not installed**
- **Install / Update / Uninstall selected**
- **Update everything on this PC** (`winget upgrade --all`)
- **Create restore point** before big changes
- **Remove Edge** (keeps WebView2, which other apps need)
- Uses only the official `winget` source, so a broken Microsoft Store source doesn't block it
- If a vendor's file fails winget's checksum (as CCleaner often does), it opens the official download page

## Add an app

1. Find its ID: `winget search <name> --source winget`
2. Add a line to `apps.json`:

```json
{ "name": "VLC", "id": "VideoLAN.VLC", "category": "Media", "homepage": "https://www.videolan.org", "default": false }
```

`default: true` ticks it automatically when the window opens. The script reads `apps.json` from GitHub each time, so you don't need to change the script itself.
