# setup.ps1 — تنظیم خودکار کلاینت Arman VPN برای ایران
# اجرا:  .\setup.ps1 -RelayUrl "https://relay.mydomain.com/?secret=YOUR_SECRET"
# بدون ریله (فقط DNS 并 حالت ضد فیلتر):  .\setup.ps1

param(
    # آدرس ریلهٔ شخصی (اختیاری). مثل: https://relay.ali2000.dpdns.org/?secret=XXXXXXXXXXXXXXXX
    [string]$RelayUrl = "",

    # DNS DoH — فقط نقاطی که POST (RFC8484) را پشتیبانی کنند؛ 8.8.8.8/dns-query در ایران پایدار بود
    [string]$Dns = "https://8.8.8.8/dns-query",

    # پس از تنظیم، اتصال روشن شود؟
    [switch]$NoConnect
)

$ErrorActionPreference = "Stop"

# ⚠️ فیلترشکن دوم (Hiddify / sing-box / v2rayN / Clash…) باید بسته باشد!
# هستهٔ آن (sing-box.exe) نام مرورگر/TUN می‌سازد و جریان‌های Go کلاینت Arman را می‌کُشد.
$blockers = @("sing-box", "hiddify", "v2rayN", "clash", "nekoray", "mihomo")
$running = Get-Process | Where-Object { $_.Name -in $blockers } | Select-Object -ExpandProperty Name
if ($running) {
    Write-Host "⚠ فیلترشکن دوم باز است: $($running -join ', ')" -ForegroundColor Yellow
    Write-Host "  آن را از Tray ببندید (یا سرویس Hiddify را غیرفعال کنید) و دوباره setup.ps1 را اجرا کنید." -ForegroundColor Yellow
    exit 1
}

# پیدا کردن پوشهٔ user-data (مسیر پیش‌فرض نصب)
$ud = "$env:LOCALAPPDATA\Programs\Firefox VPN Client\user-data"
if (-not (Test-Path (Join-Path $ud "local-api.token"))) {
    Write-Host "✗ پوشهٔ user-data کلاینت Arman پیدا نشد. مطمئن شوید برنامه نصب است." -ForegroundColor Red
    exit 1
}
$token = (Get-Content (Join-Path $ud "local-api.token") -Raw).Trim()
$api = "http://127.0.0.1:10820"
$auth = @{ "X-Local-Token" = $token }

# چک: هستهٔ برنامه در حال اجرا باشد
try {
    $null = Invoke-RestMethod "$api/api/status" -Headers $auth -TimeoutSec 8
} catch {
    Write-Host "✗ هستهٔ کلاینت (arman-vpn-core) در حال اجرا نیست؛ برنامه را باز کنید و دوباره تلاش کنید." -ForegroundColor Red
    exit 1
}

# خواندن تنظیمات فعلی و تغییر آن‌ها
$s   = Invoke-RestMethod "$api/api/settings" -Headers $auth -TimeoutSec 10
$cfg = $s.config

$cfg.network.api_relay_enabled = $true
$cfg.network.api_relay_ech     = "off"      # ECH با شبکهٔ ایران ناسازگار است
$cfg.network.hello_split       = "off"      # سادگی fine؛ DNS مستقیم fires می‌کند
if ($cfg.dns.servers) { $cfg.dns.servers = @($Dns) }
$cfg.dns.fallback_to_system = $false

if ($RelayUrl) {
    if ($RelayUrl -notmatch "\?secret=\S+") {
        Write-Host "✗ آدرس ریله باید مثل https://relay.name.com/?secret=SECRET باشد (secret در انتهای آدرس)" -ForegroundColor Red
        exit 1
    }
    $cfg.network.api_relay = $RelayUrl
    Write-Host "→ ریلهٔ شخصی ثبت شد: $RelayUrl"
}

$body = @{ config = $cfg } | ConvertTo-Json -Depth 12
Invoke-RestMethod "$api/api/settings" -Method Put -Headers $auth -ContentType "application/json" -Body $body -TimeoutSec 30 | Out-Null
Write-Host "✓ تنظیمات ذخیره شد: DNS=$Dns | fallback_to_system=$($cfg.dns.fallback_to_system) | hello_split=off | ech=off"

# حالت proxy شفاف (بدون TUN)
$cfg2 = (Invoke-RestMethod "$api/api/settings" -Headers $auth -TimeoutSec 10).config
$cfg2.system_proxy.mode = "clear"
$body2 = @{ config = $cfg2 } | ConvertTo-Json -Depth 12
Invoke-RestMethod "$api/api/settings" -Method Put -Headers $auth -ContentType "application/json" -Body $body2 -TimeoutSec 30 | Out-Null
Write-Host "✓ حالت سیستم پروکسی: clear (TUN خاموش — سازگارتر با ایران)"

if (-not $NoConnect) {
    Write-Host "… روشن کردن اتصال (تا ۱ دقیقه)" -NoNewline
    $null = Invoke-RestMethod "$api/api/power" -Method Post -Headers $auth -ContentType "application/json" -Body '{"on":true}' -TimeoutSec 60

    $tries = 0
    do {
        Start-Sleep -Seconds 8; $tries++
        $st = Invoke-RestMethod "$api/api/status" -Headers $auth -TimeoutSec 10
        Write-Host "." -NoNewline
    } while ($st.state.phase -eq "connecting" -and $tries -lt 10)

    Write-Host ""
    if ($st.state.phase -eq "running") {
        Write-Host "✓ متصل شد!" -ForegroundColor Green
        Write-Host "  پروکسی SOCKS5: 127.0.0.1:10810   (داشبورد: http://127.0.0.1:10820/app/)"
        # خروجی واقعی را نشانه بدهید
        try {
            $trace = curl.exe --ssl-no-revoke --socks5-hostname 127.0.0.1:10810 -s --max-time 45 "https://www.cloudflare.com/cdn-cgi/trace" 2>$null
            $loc = ($trace | Select-String "^loc=").Line
            $ip  = ($trace | Select-String "^ip=").Line
            Write-Host "  $ip" -ForegroundColor Cyan
            Write-Host "  $loc" -ForegroundColor Cyan
        } catch { }
    } else {
        Write-Host "⚠ هنوز کامل وصل نشده: $($st.state.message) — برنامه هر چند ثانیه دوباره تلاش می‌کند." -ForegroundColor Yellow
        Write-Host "  لاگ: $ud\logs\  |  توصیه: چند ثانیه هم‌زمان سکوت دستی (هیچ ترافیک تحمیلی نداشته باشید)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "تمام. دیگر نیازی به فیلترشکن دوم نیست." -ForegroundColor Cyan
