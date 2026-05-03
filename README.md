# BUNDLE

> Pack your entire project into a single AI-ready file — in seconds.

---

## What is this?

**BUNDLE** is a PowerShell tool that scans your computer, finds your project, and merges all its source code into one clean `.txt` file — ready to paste into any AI chat (ChatGPT, Claude, Gemini, etc.).

No installation. No dependencies. One script.

---

## How to Run

**1 — Download** `BUNDLE-UNIVERSAL.ps1`

**2 — Open PowerShell**
Press `Win + R`, type `powershell`, press **Enter**

**3 — Paste this command and press Enter**

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; $f = Get-ChildItem -Path $HOME -Filter "BUNDLE-UNIVERSAL.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { Unblock-File $f.FullName; & $f.FullName } else { Write-Host "BUNDLE-UNIVERSAL.ps1 not found. Make sure it is downloaded." -ForegroundColor Red }
```

**4 — Follow the prompts**
The tool will ask for your project name and where to save the output. That's it.

---

## What it does

- Scans all drives automatically to find your project
- Skips noise: `node_modules`, `.git`, `build`, binaries, images
- Protects secrets: `.env` files are never included
- Outputs a single `.txt` file with all your source code
- Shows file count, size, and token estimate when done

Works with any stack: React, Node, Python, Flutter, Java, Go, and more.

---

## Requirements

- Windows
- PowerShell 5.1 or PowerShell 7+

> Do not run in CMD, Git Bash, or WSL. **PowerShell only.**

---

## License

MIT — free to use, modify, and share.
