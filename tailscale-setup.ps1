# ============================================================
# Tailscale Auto-Install Script (Windows 10 / 11)
# ============================================================

# --- Step 1: Admin Elevation ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process -Verb RunAs -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# Force TLS 1.2 for downloads (needed on some Win10 builds)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Tailscale Auto-Install Script" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

$tsCli = "C:\Program Files\Tailscale\tailscale.exe"
$errorOccurred = $false

# --- Step 2 & 3: Download and Install ---
if (Test-Path $tsCli) {
    Write-Host "[1/6] Tailscale already installed - skipping download." -ForegroundColor Green
    Write-Host "[2/6] Tailscale already installed - skipping install." -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "[1/6] Downloading Tailscale installer..." -ForegroundColor Yellow
    $msiPath = Join-Path $env:TEMP "tailscale-setup.msi"
    $downloadUrl = "https://pkgs.tailscale.com/stable/tailscale-setup-latest-amd64.msi"
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $msiPath -UseBasicParsing -ErrorAction Stop
        Write-Host "      Download complete." -ForegroundColor Green
    } catch {
        Write-Host "      ERROR: Download failed - $_" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host ""

    Write-Host "[2/6] Installing Tailscale silently..." -ForegroundColor Yellow
    $installArgs = "/i `"$msiPath`" /quiet /norestart"
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "      ERROR: Installation failed (exit code $($proc.ExitCode))" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "      Installation complete." -ForegroundColor Green
    Write-Host ""

    # Wait for CLI to appear
    Write-Host "      Waiting for Tailscale CLI..." -ForegroundColor Yellow
    for ($i = 0; $i -lt 15; $i++) {
        if (Test-Path $tsCli) { break }
        Start-Sleep -Seconds 2
    }
    if (-not (Test-Path $tsCli)) {
        Write-Host "      ERROR: Tailscale CLI not found after 30s" -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
    Write-Host "      Tailscale CLI is ready." -ForegroundColor Green
    Write-Host ""
}

# --- Step 4: Login URL or Status ---
Write-Host "[3/6] Checking Tailscale login status..." -ForegroundColor Yellow
$loginUrl = ""

# Try to get IP (means already logged in)
$tsIP = $null
try {
    $tsIP = (& $tsCli ip -4 2>$null)
    if ($tsIP) { $tsIP = $tsIP.Trim() }
} catch {}

if ($tsIP -match '^\d+\.\d+\.\d+\.\d+$') {
    $loginUrl = "Already logged in - Tailscale IP: $tsIP"
    Write-Host "      $loginUrl" -ForegroundColor Green
} else {
    Write-Host "      Not logged in. Starting tailscale login..." -ForegroundColor Yellow

    # Logout first to ensure clean state
    try { & $tsCli logout 2>$null } catch {}
    Start-Sleep -Seconds 2

    # Run login as background process, capture stderr to file
    $stderrFile = Join-Path $env:TEMP "ts_login_output.txt"
    if (Test-Path $stderrFile) { Remove-Item $stderrFile -Force }

    $loginProc = Start-Process -FilePath $tsCli -ArgumentList "login" `
        -RedirectStandardError $stderrFile `
        -RedirectStandardOutput (Join-Path $env:TEMP "ts_login_stdout.txt") `
        -PassThru -WindowStyle Hidden

    # Poll stderr file for URL (up to 30 seconds)
    $loginUrl = "URL not captured - check Tailscale manually"
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 2
        if (Test-Path $stderrFile) {
            $content = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
            if ($content -and $content -match '(https://\S+)') {
                $loginUrl = $Matches[1]
                break
            }
        }
    }

    # Stop the blocking login process
    try {
        if (-not $loginProc.HasExited) {
            Stop-Process -Id $loginProc.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}

    Write-Host "      Login URL: $loginUrl" -ForegroundColor Green
}
Write-Host ""

# --- Step 5: System Info ---
Write-Host "[4/6] Gathering system info..." -ForegroundColor Yellow
$sysUser = $env:USERNAME
$sysComp = $env:COMPUTERNAME
Write-Host "      User: $sysUser  Computer: $sysComp" -ForegroundColor Green
Write-Host ""

# --- Step 6: Send Email ---
Write-Host "[5/6] Sending email with login URL..." -ForegroundColor Yellow
try {
    $smtpServer = "mail.rrpgroup.com.bd"
    $smtpPort = 587
    $from = "waqar@rrpgroup.com.bd"
    $to = "ceh.waqar@gmail.com"
    $subject = "Tailscale Login - $sysComp ($sysUser)"
    $body = "Computer: $sysComp`r`nUsername: $sysUser`r`n`r`nTailscale Login URL:`r`n$loginUrl"
    $secPass = ConvertTo-SecureString 'Waa@098)(*' -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($from, $secPass)

    Send-MailMessage -From $from -To $to -Subject $subject -Body $body `
        -SmtpServer $smtpServer -Port $smtpPort -UseSsl -Credential $cred -ErrorAction Stop

    Write-Host "      Email sent successfully." -ForegroundColor Green
} catch {
    Write-Host "      WARNING: Email failed - $_" -ForegroundColor Red
    $errorOccurred = $true
}
Write-Host ""

# --- Step 7: Enable Remote Desktop ---
Write-Host "[6/6] Enabling Remote Desktop..." -ForegroundColor Yellow
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
    # Enable firewall rule (works on both Win10 and Win11)
    netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes 2>$null | Out-Null
    Write-Host "      Remote Desktop enabled." -ForegroundColor Green
} catch {
    Write-Host "      WARNING: Could not enable RDP - $_" -ForegroundColor Red
    $errorOccurred = $true
}
Write-Host ""

# --- Step 8: Prompt for Restart ---
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
$answer = Read-Host "Restart the computer now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Restarting in 5 seconds..."
    shutdown /r /t 5
} else {
    Write-Host "Restart skipped. Please restart manually when ready."
    Read-Host "Press Enter to exit"
}
