# ============================================================
# Tailscale Auto-Install Script (Windows 10 / 11)
# ============================================================

param (
    [Parameter(Mandatory=$false)]
    [string]$TailscaleAuthKey = "",

    [Parameter(Mandatory=$false)]
    [string]$FromEmail = "waqar@rrpgroup.com.bd",

    [Parameter(Mandatory=$false)]
    [string]$ToEmail = "ceh.waqar@gmail.com",

    [Parameter(Mandatory=$false)]
    [string]$SmtpServer = "mail.rrpgroup.com.bd",

    [Parameter(Mandatory=$false)]
    [int]$SmtpPort = 587
)

# --- Step 1: Admin Elevation ---
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    $argString = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    foreach ($key in $MyInvocation.BoundParameters.Keys) {
        $val = $MyInvocation.BoundParameters[$key]
        if ($val -is [switch]) {
            if ($val) { $argString += " -$key" }
        } else {
            $escapedVal = $val.ToString().Replace('"', '`"')
            $argString += " -$key `"$escapedVal`""
        }
    }
    Start-Process -Verb RunAs -FilePath "powershell.exe" -ArgumentList $argString
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
} elseif (-not [string]::IsNullOrEmpty($TailscaleAuthKey)) {
    Write-Host "      Not logged in. Authenticating with Tailscale Auth Key..." -ForegroundColor Yellow
    try {
        & $tsCli up --authkey=$TailscaleAuthKey --accept-routes=true --accept-dns=true 2>&1 | Out-Default
        $tsIP = (& $tsCli ip -4 2>$null)
        if ($tsIP) { $tsIP = $tsIP.Trim() }
        $loginUrl = "Authenticated using Auth Key - Tailscale IP: $tsIP"
        Write-Host "      $loginUrl" -ForegroundColor Green
    } catch {
        Write-Host "      ERROR: Auth Key authentication failed - $_" -ForegroundColor Red
        $errorOccurred = $true
    }
} else {
    Write-Host "      Not logged in. Starting tailscale login..." -ForegroundColor Yellow

    # Logout first to ensure clean state
    try { & $tsCli logout 2>$null } catch {}
    Start-Sleep -Seconds 2

    # Run login as background process, capture stderr to file using unique names to prevent race conditions
    $randomSuffix = Get-Random -Minimum 1000 -Maximum 9999
    $stderrFile = Join-Path $env:TEMP "ts_login_output_$randomSuffix.txt"
    $stdoutFile = Join-Path $env:TEMP "ts_login_stdout_$randomSuffix.txt"
    if (Test-Path $stderrFile) { Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue }
    if (Test-Path $stdoutFile) { Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue }

    $loginProc = Start-Process -FilePath $tsCli -ArgumentList "login" `
        -RedirectStandardError $stderrFile `
        -RedirectStandardOutput $stdoutFile `
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

    Write-Host "      Login URL: $loginUrl" -ForegroundColor Green
    Write-Host "      (Tailscale login process remains active in background to process authentication)" -ForegroundColor Yellow
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
    # Decrypt SMTP Password using embedded AES key/IV/ciphertext bytes to avoid plaintext hardcoding
    [byte[]]$aesKey = 222,248,210,166,208,215,92,216,77,63,140,111,86,99,73,86
    [byte[]]$aesIv  = 240,119,124,167,72,95,33,247,115,53,198,26,194,27,59,22
    [byte[]]$aesCiphertext = 4,23,73,163,126,176,120,195,253,213,37,142,2,218,108,181

    $aes = [System.Security.Cryptography.Aes]::Create()
    $aes.Key = $aesKey
    $aes.IV = $aesIv
    $decryptor = $aes.CreateDecryptor()
    $decryptedBytes = $decryptor.TransformFinalBlock($aesCiphertext, 0, $aesCiphertext.Length)
    $passString = [System.Text.Encoding]::UTF8.GetString($decryptedBytes)
    $secPass = ConvertTo-SecureString $passString -AsPlainText -Force

    $cred = New-Object System.Management.Automation.PSCredential($FromEmail, $secPass)
    $subject = "Tailscale Login - $sysComp ($sysUser)"
    $body = "Computer: $sysComp`r`nUsername: $sysUser`r`n`r`nTailscale Login URL:`r`n$loginUrl"

    Send-MailMessage -From $FromEmail -To $ToEmail -Subject $subject -Body $body `
        -SmtpServer $SmtpServer -Port $SmtpPort -UseSsl -Credential $cred -ErrorAction Stop

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
    
    # Configure and start TermService to listen on RDP connections
    Set-Service -Name "TermService" -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name "TermService" -ErrorAction SilentlyContinue

    # Enable firewall rule locale-independently on Windows 10/11
    if (Get-Command Enable-NetFirewallRule -ErrorAction SilentlyContinue) {
        Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
    } else {
        netsh advfirewall firewall set rule group="Remote Desktop" new enable=yes 2>$null | Out-Null
    }
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
# Clean up login temp files if they exist and are not locked
if (Get-Variable -Name "stderrFile" -ErrorAction SilentlyContinue) {
    if ($stderrFile -and (Test-Path $stderrFile)) { Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue }
}
if (Get-Variable -Name "stdoutFile" -ErrorAction SilentlyContinue) {
    if ($stdoutFile -and (Test-Path $stdoutFile)) { Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue }
}
$answer = Read-Host "Restart the computer now? (Y/N)"
if ($answer -eq 'Y' -or $answer -eq 'y') {
    Write-Host "Restarting in 5 seconds..."
    shutdown /r /t 5
} else {
    Write-Host "Restart skipped. Please restart manually when ready."
    Read-Host "Press Enter to exit"
}
