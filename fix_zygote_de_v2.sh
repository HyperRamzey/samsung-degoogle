#!/system/bin/sh
# fix_zygote_de_v2.sh — persistent fix for zygote DE-mount aborts
# v1 stubs were deleted at next boot by package manager cleanup of
# uninstalled-for-user-0 packages. v2: re-create stubs + set immutable
# flag (chattr +i) so boot-time cleanup cannot remove them.
# Degoogle state (uninstalled for user 0) is untouched — packages stay hidden.

STAMP=/data/local/tmp/degoogle/fix_zygote_de_v2.log
echo "=== fix_zygote_de_v2 $(date) ===" >$STAMP

uid_of() { dumpsys package "$1" 2>/dev/null | grep -m1 -o 'uid=[0-9]*' | cut -d= -f2; }

PKGS="com.google.android.gms
com.google.android.gsf
com.android.vending
com.google.android.configupdater
com.google.android.partnersetup
com.google.android.onetimeinitializer
com.google.android.feedback
com.google.android.verifier
com.google.android.turboadapter
com.google.android.safetycore
com.google.android.ext.shared
com.google.android.gms.location.history
com.google.android.gms.supervision
com.google.android.googlequicksearchbox
com.google.android.youtube
com.google.android.apps.maps
com.google.android.apps.photos
com.google.android.apps.docs
com.google.android.gm
com.google.android.apps.nbu.files
com.google.android.apps.turbo
com.google.android.apps.wellbeing
com.google.android.apps.safetyhub
com.google.android.apps.weather
com.google.android.apps.restore
com.google.android.as
com.google.android.as.oss
com.google.android.ambient.streaming
com.google.android.apps.carrier.carrierwifi
com.google.android.projection.gearhead
com.google.android.ar.core
com.google.android.markup
com.google.android.tag
com.google.android.printservice.recommendation
com.google.android.flipendo
com.google.android.settings.intelligence
com.google.android.marvin.talkback
com.google.android.setupwizard
com.google.android.pixel.setupwizard"

fixed=0
for p in $PKGS; do
  U=$(uid_of "$p")
  [ -z "$U" ] && continue
  for d in /data/user_de/0/$p /data/data/$p; do
    if [ -e "$d" ]; then
      chattr +i "$d" 2>>$STAMP
      echo "immutable-set $d" >>$STAMP
      fixed=$((fixed + 1))
    else
      mkdir -p "$d" 2>>$STAMP || {
        echo "MKDIR_FAIL $d" >>$STAMP
        continue
      }
      chown "$U:$U" "$d" 2>>$STAMP
      chmod 0771 "$d" 2>>$STAMP
      restorecon -F "$d" 2>>$STAMP
      chattr +i "$d" 2>>$STAMP
      echo "STUBBED+IMMUTABLE $d uid=$U" >>$STAMP
      fixed=$((fixed + 1))
    fi
  done
done
echo "fixed=$fixed" >>$STAMP
echo "summary:"
tail -3 $STAMP
ls -la /data/user_de/0/com.google.android.gms /data/data/com.google.android.gms 2>&1
