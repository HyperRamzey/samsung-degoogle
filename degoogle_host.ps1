# ============================================================================
# degoogle_host.ps1 — host-side orchestrator for the a30s DeGoogle
# Target: RF8M834JT4D (SM-A307FN). NEVER runs against RFCWC0G1Z1J (Fold5).
#
# Usage:
#   powershell -File degoogle_host.ps1 -Phase degoogle   # 1: run degoogle.sh go + pull backups
#   powershell -File degoogle_host.ps1 -Phase firefox    # 2: download+install FF Nightly arm64
#   powershell -File degoogle_host.ps1 -Phase chrome     # 3: remove Chrome (post-Firefox check)
#   powershell -File degoogle_host.ps1 -Phase verify     # final device state report
# ============================================================================
param(
  [Parameter(Mandatory=$true)][ValidateSet('degoogle','firefox','chrome','verify')]$Phase
)
$ErrorActionPreference = 'Stop'
$serial = 'RF8M834JT4D'
$dir    = 'G:\projects\eureka-build-tools\degoogle'
$dev    = '/data/local/tmp/degoogle'
$adb    = 'adb'

function AdbSh($cmd) {
  & $adb -s $serial shell "su -c '$cmd'" 2>&1 | Out-String
}

switch ($Phase) {

  # ---------------------------------------------------------------- 1 DEGOOGLE
  'degoogle' {
    Write-Host "=== PHASE 1: DeGoogle (device script, real run) ===" -ForegroundColor Cyan
    & $adb -s $serial shell "su -c 'sh /data/local/tmp/degoogle.sh go'" | Out-Null
    $log = (& $adb -s $serial shell "su -c 'ls -t $dev/log_*.txt | head -1'").Trim()
    Write-Host "device log: $log"
    # show summary lines
    AdbSh "grep -e REMOVED -e FAILED -e 'verify' -e RESULT -e 'packages:' $log"
    # pull the full state to PC (irreversible-safety backup)
    & $adb -s $serial pull "$dev/." "$dir\device_backup" 2>&1 | Select-Object -Last 1
    Write-Host "backups pulled to: $dir\device_backup"
    if (Test-Path "$dir\device_backup\restore.sh") {
      Write-Host "restore: adb push restore.sh + 'su -c sh /data/local/tmp/degoogle/restore.sh'" -ForegroundColor Yellow
    }
  }

  # ---------------------------------------------------------------- 2 FIREFOX
  'firefox' {
    Write-Host "=== PHASE 2: Firefox Nightly arm64-v8a ===" -ForegroundColor Cyan
    $api = 'https://archive.mozilla.org/pub/mobile/nightly/latest-mozilla-central-android/'
    $html = Invoke-WebRequest -Uri $api -UseBasicParsing
    $apk = [regex]::Matches($html.Content, 'href="(fennec-[0-9a-zA-Z.\-]+\.android-arm64-v8a\.apk)"') |
           ForEach-Object { $_.Groups[1].Value } | Select-Object -First 1
    if (-not $apk) { throw 'no arm64-v8a nightly APK found in archive listing' }
    $url = "$api$(($apk -replace ' ','%20'))"
    Write-Host "latest: $apk"
    $out = "$dir\$apk"
    Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing
    Write-Host ("downloaded: {0:N1} MB" -f ((Get-Item $out).Length / 1MB))
    & $adb -s $serial install -r $out 2>&1 | Select-Object -Last 1
    # verify launchable
    AdbSh 'pm list packages org.mozilla.fennec_$USER' | Out-Null
    $pkg = (& $adb -s $serial shell pm list packages fennec).Trim() -replace 'package:',''
    Write-Host "installed package: $pkg"
    if ($pkg) {
      & $adb -s $serial shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 2>&1 | Select-Object -Last 1
      Write-Host "Firefox Nightly launched (check device screen)" -ForegroundColor Yellow
    }
  }

  # ---------------------------------------------------------------- 3 CHROME
  'chrome' {
    Write-Host "=== PHASE 3: remove Chrome (Firefox must be in) ===" -ForegroundColor Cyan
    $fx = (& $adb -s $serial shell pm list packages fennec).Trim()
    if (-not $fx) { throw 'Firefox not installed - aborting Chrome removal' }
    AdbSh 'pm path com.android.chrome' | Out-Null
    # backup + restore entry, then remove
    AdbSh "mkdir -p $dev/backup/com.android.chrome; cp `$(pm path com.android.chrome | sed 's/package://' | tr '\n' ' ') $dev/backup/com.android.chrome/ 2>/dev/null" | Out-Null
    AdbSh "echo 'if pm install-existing --user 0 com.android.chrome >/dev/null 2>&1; then echo restored com.android.chrome; elif pm install-multiple -r --user 0 $dev/backup/com.android.chrome/*.apk >/dev/null 2>&1; then echo restored com.android.chrome; fi' >> $dev/restore.sh" | Out-Null
    AdbSh 'pm uninstall --user 0 com.android.chrome'
    Write-Host "Chrome removed (restore.sh entry added)" -ForegroundColor Yellow
  }

  # ---------------------------------------------------------------- 4 VERIFY
  'verify' {
    Write-Host "=== FINAL STATE REPORT ===" -ForegroundColor Cyan
    Write-Host "--- google-ish packages remaining ---"
    AdbSh 'pm list packages --user 0 | grep -iE "^package:com.google|^package:com.android.vending|^package:com.android.chrome|gms|gsf" | sort'
    Write-Host "--- role holders ---"
    AdbSh 'dumpsys role | grep -e name= -e holders='
    Write-Host "--- webview ---"
    AdbSh 'dumpsys webviewupdate | grep -e Current -e Valid'
    Write-Host "--- IME ---"
    AdbSh 'ime list -s'
    Write-Host "--- browser ---"
    AdbSh 'pm list packages fennec'
  }
}
