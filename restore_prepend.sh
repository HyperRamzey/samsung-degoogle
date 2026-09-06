#!/system/bin/sh
# restore_prepend.sh — rewrite on-device restore.sh with immutable-clear prelude.
# The original restore.sh was generated before fix_zygote_mounts existed; restored
# packages would fail to take back their (now immutable) stub dirs.
R=/data/local/tmp/degoogle/restore.sh
if [ ! -f "$R" ]; then
  echo "NO_RESTORE_SH"
  exit 1
fi
if grep -q "chattr -i" "$R"; then
  echo "ALREADY_PATCHED"
  exit 0
fi
cp "$R" "$R.pre_immutable.bak"
{
  echo '# === prelude added by fix_zygote_de_v2 (degoogle.sh update) ==='
  echo '# clear immutable flags on all degoogle stub dirs so PM can own them again'
  echo 'for _d in /data/user_de/0/com.google* /data/data/com.google* /data/user_de/0/com.android.vending /data/data/com.android.vending; do'
  echo '  [ -e "$_d" ] && chattr -i "$_d" 2>/dev/null'
  echo 'done'
  cat "$R.pre_immutable.bak"
} >"$R"
echo "PATCHED ($(wc -l <$R) lines, backup: $R.pre_immutable.bak)"
grep -c "chattr -i" "$R"
