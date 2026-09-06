# Samsung DeGoogle — GMS removal for rooted A-series (Android 13–15 custom ROMs)

Safe, reversible removal of Google Mobile Services and Google apps from rooted
Samsung Exynos devices running AOSP-based custom ROMs (tested: DerpFest 15 on
SM-A307FN / a30s, KernelSU root). **Nothing is deleted from the system image** —
system packages are only uninstalled *for user 0* and every APK is backed up
first, so everything restores with `restore.sh` or a factory reset.

## What it does

1. **Preflight** — root check, `/data` space check, snapshot of installed packages
2. **Backup** — every package slated for removal → APK backup + `restore.sh` generator
3. **Remove** — Google apps → GMS overlays + setupwizard → GMS core stack (that order)
4. **Zygote mount fix** — stubs data dirs of removed *system* packages (see below —
   the step that keeps SystemUI alive)
5. **Verify** — dialer role, IME, webview, camera, SMS, package installer all intact

## The keep list (DO NOT REMOVE on this ROM)

These are sole functional providers on DerpFest a30s — removing any of them breaks
core phone functions:

| Package | Role |
| --- | --- |
| `com.google.android.dialer` | DIALER role (only dialer) |
| `com.google.android.inputmethod.latin` | Gboard — only IME |
| `com.google.android.webview` | only valid WebView provider on this ROM |
| `com.google.android.apps.googlecamera.fishfood` | only camera |
| `com.google.android.apps.messaging` | SMS role |
| `com.google.android.contacts` | SYSTEM_CONTACTS role |
| deskclock, calculator, calendar, soundpicker, avatarpicker, tts, packageinstaller | sole providers |

## Critical knowledge: why removed GMS crash-loops SystemUI (and the fix)

**Symptom**: after removal, every app (SystemUI, launcher, permissioncontroller,
`android.process.acore`, …) dies at once in a SIGABRT loop; logcat shows:

```
JNI FatalError called: (<pkg>) com_android_internal_os_Zygote.cpp:817:
Failed to mount /data_mirror/data_de/null/0/com.google.android.gms
to /data/user_de/0/com.google.android.gms: No such file or directory
```

**Root cause**: `pm uninstall --user 0` *hides* system packages — they stay in
`packages.xml` and package manager keeps feeding them to zygote's
`isolateAppData()`. For every forked process zygote bind-mounts each tracked
package's data dirs into the app's mount namespace; a **missing DE dir
(`/data/user_de/0/<pkg>`) is a fatal abort** (missing CE dir is tolerated).
GMS is forceQueryable → it's in essentially every process's mount list →
every fork dies.

**Fix (automatic in this script)**: after all removals, recreate empty stub dirs
(DE + CE) with the right uid/gid/mode/SELinux label, then `chattr +i` them —
**the immutable flag is required**: package manager's boot-time cleanup deletes
plain empty dirs of uninstalled packages, which resurrects the crash loop on
every reboot. Immutable stubs survive reboots (verified on-device across
multiple boots). `restore.sh` clears the flags before reinstalling.

## Files

| File | Purpose |
| --- | --- |
| `degoogle.sh` | device-side script (run as root; `dry` / `go` modes) |
| `degoogle_host.ps1` | host orchestrator: degoogle → firefox → chrome → verify phases |
| `fix_zygote_de_v2.sh` | standalone repair script for devices already hit by the bug |
| `restore_prepend.sh` | retro-patches an old restore.sh with the chattr-clear prelude |

## Usage

```powershell
# 1. Push + dry run (ALWAYS dry first)
adb push degoogle.sh /data/local/tmp/degoogle.sh
adb shell "su -c 'sh /data/local/tmp/degoogle.sh dry'"

# 2. Real run (backups + removals + zygote fix happen together)
adb shell "su -c 'sh /data/local/tmp/degoogle.sh go'"

# 3. (optional) host orchestration incl. Firefox Nightly install
powershell -File degoogle_host.ps1 -Phase degoogle
powershell -File degoogle_host.ps1 -Phase firefox   # then verify browsing
powershell -File degoogle_host.ps1 -Phase chrome    # removes Chrome last

# Restore everything
adb push restore.sh → adb shell "su -c 'sh /data/local/tmp/degoogle/restore.sh'"
```

## Requirements

- Rooted device (KernelSU/Magisk — script runs via `su`)
- `adb` on host, device serial set in `degoogle_host.ps1` (**edit the serial —
  it defaults to the author's a30s; never point it at a device you can't afford
  to reset**)
- Custom ROM where the Google apps above are the *sole* providers — on other
  ROMs, adjust `KEEP` first (e.g. LineageOS ships its own dialer/webview)

## Device-verified state

- 56 packages removed (GMS core, GSF, Vending, setupwizard stack, 20 GMS
  overlays, Google apps), Firefox Nightly as browser
- All critical functions verified: calls, SMS, IME, camera, webview, installer
- Crash-loop bug diagnosed, fixed, **verified across reboots**
- 1.6 GB APK backup + generated restore.sh

## License

MIT — no warranty; you are modifying a device you own. Factory reset always
restores the system image packages.
