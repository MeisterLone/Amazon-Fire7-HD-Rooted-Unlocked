#!/usr/bin/env bash
# KFQUWI FASTBOOT token probe + unlock-state reads — Tier A/C1.
# Pre-armed BEFORE plug-in: waits for preloader 0e8d:2000, writes FASTBOOT
# token during READY window, then runs read-only getvar probes including the
# gate allow-table entries (unlock_status / unlock_code / tu_code).
set -u

LOG=/root/fastboot_probe_$(date +%Y%m%d_%H%M%S).log
exec > >(tee -a "$LOG") 2>&1

echo "=== KFQUWI FASTBOOT token probe $(date -Is) ==="
systemctl stop ModemManager 2>/dev/null || true

dmesg -Wc >"$LOG.dmesg" 2>/dev/null &
DMESG_PID=$!
trap 'kill $DMESG_PID 2>/dev/null' EXIT

echo "[*] Waiting up to 180s for preloader 0e8d:2000 ..."
FOUND=0
for i in $(seq 1 3600); do
    if lsusb 2>/dev/null | grep -q '0e8d:2000'; then
        echo "[+] Preloader enumerated (iteration $i)"
        FOUND=1
        break
    fi
    if [ $((i % 40)) -eq 0 ]; then
        CUR=$(lsusb 2>/dev/null | grep -E '1949|0e8d' || true)
        [ -n "$CUR" ] && echo "[i] current USB: $CUR"
    fi
    sleep 0.05
done
[ "$FOUND" -eq 1 ] || { echo "[!] Preloader never enumerated in 180s"; exit 2; }

python3 - <<'PYEOF'
import sys, time
try:
    import usb.core, usb.util
    dev = None
    for _ in range(80):
        dev = usb.core.find(idVendor=0x0e8d, idProduct=0x2000)
        if dev is not None:
            break
        time.sleep(0.05)
    if dev is None:
        print("[!] pyusb: device gone", flush=True); sys.exit(3)
    try:
        if dev.is_kernel_driver_active(0):
            dev.detach_kernel_driver(0)
    except Exception as e:
        print(f"[*] detach note: {e}", flush=True)
    dev.set_configuration()
    usb.util.claim_interface(dev, 0)
    try:
        dev.read(0x81, 512, timeout=200)
    except Exception:
        pass
    dev.write(0x01, b"FASTBOOT", timeout=2000)
    print("[+] FASTBOOT token written", flush=True)
    try:
        resp = dev.read(0x81, 64, timeout=3000)
        print(f"[+] preloader response: {bytes(resp)!r}", flush=True)
    except Exception as e:
        print(f"[!] no response read: {e}", flush=True)
    usb.util.dispose_resources(dev)
    sys.exit(0)
except SystemExit:
    raise
except Exception as e:
    print(f"[!] pyusb path failed: {e}", flush=True); sys.exit(3)
PYEOF

echo "[*] Watching for fastboot re-enumeration (60s)..."
END=$((SECONDS+60))
PREV=""
for i in $(seq 1 120); do
    CUR=$(fastboot devices 2>/dev/null | head -1)
    if [ -n "$CUR" ] && [ "$CUR" != "$PREV" ]; then
        echo "[+] fastboot device: $CUR"
        PREV="$CUR"
        break
    fi
    sleep 0.5
done
if ! fastboot devices 2>/dev/null | grep -q .; then
    echo "[!] fastboot never appeared; dumping lsusb for forensics:"
    lsusb | grep -viE 'Linux Foundation|Intel Corp'
    exit 4
fi
sleep 1

# ---- read-only probes: gate allow-table entries FIRST ----
for v in product serialno max-download-size unlock_status unlock_code tu_code unlocked secure version slot-count slot-suffixes is-userspace; do
    echo "--- getvar:$v"
    timeout 5 fastboot getvar "$v" 2>&1 | head -2
done

echo "--- oem flags (read-only query form)"
timeout 5 fastboot oem flags 2>&1 | head -5

echo "=== probe complete; log: $LOG ; dmesg: $LOG.dmesg ==="
