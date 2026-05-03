<div align="center">

![BUNDLE Logo](bundle_logo_v4.svg)


> Pack your entire project into a single AI-ready file — in seconds.

</div>

---

## 🚀 How to Run

### 1. Download the script
Save `BUNDLE.ps1` anywhere on your computer.

### 2. Open PowerShell
Press `Win + R`, type `powershell`, press **Enter**

### 3. Paste this and press Enter

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force; $f = Get-ChildItem -Path $HOME -Filter "BUNDLE.ps1" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { Unblock-File $f.FullName; & $f.FullName } else { Write-Host "BUNDLE.ps1 not found. Make sure it is downloaded." -ForegroundColor Red }
```

The tool will find the script automatically — no need to navigate to any folder.

---

## ✅ Output

- 📄 Single bundled file — e.g. `bundle_MyApp.txt`
- 📦 All source code merged and organized
- 🔒 `.env` files automatically excluded — secrets protected
- 📊 Token estimate shown on completion

---

## ⚠️ Requirements

- Windows
- PowerShell 5.1 or PowerShell 7+

> Do not run in CMD, Git Bash, or WSL. **PowerShell only.**
