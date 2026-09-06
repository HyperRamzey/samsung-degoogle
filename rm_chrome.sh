#!/bin/bash
# Remove Chrome safely: backup all 6 APKs + restore entry + uninstall
S=RF8M834JT4D
B=/data/local/tmp/degoogle/backup/com.android.chrome
adb -s $S shell "su -c '
set -e
mkdir -p $B
pm path com.android.chrome | sed \"s/^package://\" | while read apk; do
  cp \"\$apk\" $B/
done
echo \"if pm install-existing --user 0 com.android.chrome >/dev/null 2>&1; then echo restored com.android.chrome; elif pm install-multiple -r --user 0 $B/*.apk >/dev/null 2>&1; then echo restored com.android.chrome; fi\" >> /data/local/tmp/degoogle/restore.sh
ls -la $B | head -8
pm uninstall --user 0 com.android.chrome
'"
