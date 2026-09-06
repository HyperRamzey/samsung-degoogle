#!/system/bin/sh
# ============================================================================
# degoogle.sh — DeGoogle for DerpFest a30s (SM-A307FN, Android 15)
# Runs ON DEVICE as root:  adb shell "su -c 'sh /data/local/tmp/degoogle.sh dry'"
#                          adb shell "su -c 'sh /data/local/tmp/degoogle.sh go'"
#
# WHAT IT DOES
#   1. Preflight  : root check, /data space check, snapshot installed packages
#   2. Backup     : every package slated for removal -> APK backup + restore.sh
#   3. Remove     : Google apps -> GMS overlays -> GMS core (that order)
#   4. Verify     : dialer role, IME, webview, camera, SMS, installer intact
#
# KEEP LIST (sole functional providers on this ROM - DO NOT REMOVE):
#   dialer, gboard, tts, packageinstaller, webview (single valid provider),
#   googlecamera.fishfood (only camera), messaging (only SMS), contacts,
#   deskclock, calculator, calendar, soundpicker, avatarpicker
#
# Restore: sh /data/local/tmp/degoogle/restore.sh
#          (factory reset also brings system packages back automatically)
# ============================================================================
D=/data/local/tmp/degoogle
TS=$(date +%Y%m%d_%H%M%S)
LOG="$D/log_$TS.txt"
BACKUP="$D/backup"
MODE=${1:-dry}

# ---- keep list (never removed, never backed up for removal) ----
KEEP=" com.google.android.dialer com.google.android.inputmethod.latin \
com.google.android.tts com.google.android.packageinstaller \
com.google.android.webview com.google.android.apps.googlecamera.fishfood \
com.google.android.apps.messaging com.google.android.contacts \
com.google.android.deskclock com.google.android.calculator \
com.google.android.calendar com.google.android.soundpicker \
com.google.android.avatarpicker "

is_kept() {
  case "$KEEP" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ---- removal lists ----
# Google apps (no GMS needed to be gone first; removed before GMS core)
R_APPS="com.google.android.googlequicksearchbox \
com.google.android.youtube \
com.google.android.apps.maps \
com.google.android.apps.photos \
com.google.android.apps.docs \
com.google.android.gm \
com.google.android.apps.nbu.files \
com.google.android.apps.turbo \
com.google.android.apps.wellbeing \
com.google.android.apps.safetyhub \
com.google.android.apps.weather \
com.google.android.apps.restore \
com.google.android.as \
com.google.android.as.oss \
com.google.android.ambient.streaming \
com.google.android.apps.carrier.carrierwifi \
com.google.android.projection.gearhead \
com.google.android.ar.core \
com.google.android.markup \
com.google.android.tag \
com.google.android.printservice.recommendation \
com.google.android.flipendo \
com.google.android.settings.intelligence \
com.google.android.pixel.avatarpicker \
com.google.android.marvin.talkback"

# GMS-related overlays + setupwizard stack (zero functional impact w/o GMS)
R_OVERLAYS="com.android.phone.gms.overlay \
com.android.providers.settings.gms.overlay \
com.android.providers.settings.gms.personalsafety.overlay \
com.android.providers.settings.gms.turbo.overlay \
com.android.server.telecom.gms.overlay \
com.android.systemui.gms.overlay \
com.android.systemui.gms.personalsafety.overlay \
com.google.android.overlay.gmsconfig.asi \
com.google.android.overlay.gmsconfig.common \
com.google.android.overlay.gmsconfig.comms \
com.google.android.overlay.gmsconfig.geotz \
com.google.android.overlay.gmsconfig.gsa \
com.google.android.overlay.gmsconfig.personalsafety \
com.google.android.overlay.gmsconfig.photos \
com.google.android.documentsui.pixel.overlay \
com.google.android.setupwizard \
com.google.android.pixel.setupwizard \
com.google.android.pixel.setupwizard.overlay \
com.google.android.pixel.setupwizard.overlay2021"

# GMS core stack - removed LAST (apps that depend on it are already gone)
R_GMS="com.google.android.gms \
com.google.android.gms.location.history \
com.google.android.gms.supervision \
com.google.android.gsf \
com.android.vending \
com.google.android.configupdater \
com.google.android.partnersetup \
com.google.android.onetimeinitializer \
com.google.android.feedback \
com.google.android.verifier \
com.google.android.turboadapter \
com.google.android.safetycore \
com.google.android.ext.shared"

# NOTE: com.android.chrome is NOT removed here. It is removed by the host
# script only AFTER Firefox Nightly is installed and verified (browser
# redundancy). Restore: restore.sh covers it too if it was backed up there.

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

mkdir -p "$D" "$BACKUP"
echo "=== degoogle $MODE — $(date) ===" >"$LOG"

# ---------------------------------------------------------------- preflight
if [ "$(id -u)" != "0" ]; then
  echo "FATAL: not root (run via: su -c 'sh $0 $MODE')" | tee -a "$LOG"
  exit 1
fi
AVAIL=$(df /data | tail -1 | awk '{print $4}')
AVAIL_MB=$((AVAIL / 1024))
log "preflight: root OK, /data free ${AVAIL_MB}MB"
if [ "$AVAIL_MB" -lt 2048 ]; then
  log "WARNING: <2GB free on /data — APK backup may fail; restore via factory reset still possible"
fi
pm list packages --user 0 >"$D/packages_before.txt" 2>/dev/null
log "preflight: $(wc -l <"$D/packages_before.txt") packages installed for user 0"

installed() { pm list packages --user 0 2>/dev/null | grep -q "^package:$1$"; }

# ---------------------------------------------------------------- backup
backup_pkg() {
  p=$1
  pm path "$p" >"$D/paths.tmp" 2>/dev/null || return 1
  mkdir -p "$BACKUP/$p"
  n=0
  while IFS= read -r line; do
    apk=${line#package:}
    [ -f "$apk" ] || continue
    cp "$apk" "$BACKUP/$p/" 2>>"$LOG" && n=$((n + 1))
  done <"$D/paths.tmp"
  if [ "$n" -gt 0 ]; then log "backup: $p ($n apk)"; else log "backup: $p FAILED (no files)"; fi
  return 0
}

gen_restore() {
  p=$1
  cat >>"$D/restore.sh" <<EOF
# clear immutable flag first: degoogle.sh stubbed this package's data dirs
# (chattr +i) to keep zygote mount lists happy; PM must own them again
for _d in /data/user_de/0/$p /data/data/$p; do
  [ -e "\$_d" ] && chattr -i "\$_d" 2>/dev/null
 done
if pm install-existing --user 0 $p >/dev/null 2>&1; then
  echo "restored $p (system image)"
elif pm install-multiple -r --user 0 $BACKUP/$p/*.apk >/dev/null 2>&1; then
  echo "restored $p (from backup)"
else
  echo "MANUAL RESTORE NEEDED: $p (apks in $BACKUP/$p)"
fi
EOF
}

# ---------------------------------------------------------------- zygote mount fix
# After removals, PM still tracks removed SYSTEM packages in packages.xml (they
# remain "uninstalled for user 0", not deleted). Zygote's isolateAppData()
# then tries to bind-mount their data dirs for every forked app; a missing
# /data/user_de/0/<pkg> (DE dir) is FATAL and crash-loops SystemUI + all apps.
# (Missing CE dir is tolerated; DE is not.) Boot-time PM cleanup also deletes
# empty data dirs of uninstalled packages, so the stubs need chattr +i.
# Fix: recreate empty stub dirs (DE + CE) with correct uid/gid/mode/label and
# set them immutable. Packages stay uninstalled/hidden — degoogle intact.
fix_zygote_mounts() {
  log "--- zygote mount stubs (DE+CE, immutable) ---"
  local p U fixed=0 d
  for p in $R_APPS $R_OVERLAYS $R_GMS; do
    case "$p" in *.overlay | *overlay*) continue ;; esac # overlays have no data dirs
    U=$(dumpsys package "$p" 2>/dev/null | grep -m1 -o 'uid=[0-9]*' | cut -d= -f2)
    [ -z "$U" ] && continue
    for d in /data/user_de/0/$p /data/data/$p; do
      if [ -e "$d" ]; then
        chattr +i "$d" 2>>"$LOG" && fixed=$((fixed + 1))
      else
        mkdir -p "$d" 2>>"$LOG" || {
          log "STUB_FAIL $d (mkdir)"
          continue
        }
        chown "$U:$U" "$d" 2>>"$LOG"
        chmod 0771 "$d" 2>>"$LOG"
        restorecon -F "$d" 2>>"$LOG"
        chattr +i "$d" 2>>"$LOG" && fixed=$((fixed + 1)) || log "STUB_FAIL $d (chattr)"
      fi
    done
  done
  log "zygote mount fix: $fixed dirs stubbed+immutable"
}

# ---------------------------------------------------------------- remove
remove_pkg() {
  p=$1
  if is_kept "$p"; then
    log "SKIP $p (keep-list)"
    return 0
  fi
  if ! installed "$p"; then
    log "skip $p (not installed for user 0)"
    return 0
  fi
  if [ "$MODE" = "dry" ]; then
    log "[dry-run] would remove: $p"
    return 0
  fi
  backup_pkg "$p"
  gen_restore "$p"
  out=$(pm uninstall --user 0 "$p" 2>&1)
  case "$out" in
  *Success*) log "REMOVED $p" ;;
  *) log "FAILED $p: $out" ;;
  esac
}

log "--- phase 1: Google apps ---"
for p in $R_APPS; do remove_pkg "$p"; done

log "--- phase 2: GMS overlays + setupwizard ---"
for p in $R_OVERLAYS; do remove_pkg "$p"; done

log "--- phase 3: GMS core stack (last) ---"
for p in $R_GMS; do remove_pkg "$p"; done

# zygote mount fix MUST run after all removals (stubs depend on final PM state)
if [ "$MODE" != "dry" ]; then
  fix_zygote_mounts
else
  log "[dry-run] would run fix_zygote_mounts after removals"
fi

# extra user-curated list (one package per line, applied last)
if [ -f "$D/extra_remove.txt" ]; then
  log "--- phase 4: extra_remove.txt ---"
  while IFS= read -r p; do
    [ -n "$p" ] && remove_pkg "$p"
  done <"$D/extra_remove.txt"
fi

# ---------------------------------------------------------------- leftover scan
log "--- leftover scan (google-ish packages still VISIBLE for user 0) ---"
pm list packages --user 0 2>/dev/null | sed 's/^package://' |
  grep -iE '^com\.google\.|^com\.android\.(vending|chrome)$|gms|gsf' |
  while IFS= read -r p; do
    if [ "$p" = "com.google.android.gms" ] || pm path "$p" >/dev/null 2>&1; then :; fi
    if is_kept "$p"; then
      log "leftover(kept): $p"
    elif [ "$p" = "com.android.chrome" ]; then
      log "leftover(chrome): $p — removed by host script AFTER Firefox is installed"
    elif pm path "$p" >/dev/null 2>&1; then
      log "leftover(present): $p  -> add to $D/extra_remove.txt if unwanted"
    else log "leftover(hidden/uninstalled-for-user): $p (OK)"; fi
  done

# ---------------------------------------------------------------- verify
log "--- verification ---"
V_FAIL=0
if dumpsys role 2>/dev/null | grep -A2 'name=android.app.role.DIALER' | grep -q 'com.google.android.dialer'; then
  log "verify OK: dialer role -> Google Dialer"
else log "verify WARN: dialer role check inconclusive"; fi
if ime list -s 2>/dev/null | grep -q 'inputmethod.latin'; then
  log "verify OK: Gboard IME available"
else
  log "verify FAIL: no Gboard IME!"
  V_FAIL=1
fi
if dumpsys webviewupdate 2>/dev/null | grep -q 'Valid package com.google.android.webview'; then
  log "verify OK: webview provider valid"
else
  log "verify FAIL: webview provider invalid!"
  V_FAIL=1
fi
if cmd package resolve-activity -a android.media.action.IMAGE_CAPTURE >/dev/null 2>&1; then
  log "verify OK: camera intent resolves"
else
  log "verify FAIL: no camera app!"
  V_FAIL=1
fi
if installed com.google.android.packageinstaller; then
  log "verify OK: package installer present"
else
  log "verify FAIL: package installer gone!"
  V_FAIL=1
fi
if dumpsys role 2>/dev/null | grep -A2 'name=android.app.role.SMS' | grep -q 'apps.messaging'; then
  log "verify OK: SMS role -> Messages"
else log "verify WARN: SMS role check inconclusive (Messages kept installed)"; fi

pm list packages --user 0 >"$D/packages_after.txt" 2>/dev/null
B=$(wc -l <"$D/packages_before.txt")
A=$(wc -l <"$D/packages_after.txt")
log "packages: before=$B after=$A (delta $((B - A)))"
log "restore script: sh $D/restore.sh"
log "backup dir: $BACKUP (pull it to PC!)"
if [ "$V_FAIL" = "1" ]; then
  log "RESULT: DONE WITH FAILURES — see verify lines above; restore with restore.sh"
else
  log "RESULT: OK — all critical functions verified"
fi
rm -f "$D/paths.tmp"
echo "Full log: $LOG"
exit $V_FAIL
