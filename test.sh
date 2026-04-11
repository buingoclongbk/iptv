#!/bin/sh
# ============================================================
# WH3000 5G Diagnostic Script
# Chạy trên cả QWRT và ImmortalWrt
# Output: /tmp/diag_report.txt
# ============================================================

OUT="/tmp/diag_report.txt"
TTY="/dev/ttyUSB3"

> "$OUT"

log() {
    echo "========================================" | tee -a "$OUT"
    echo ">>> $1" | tee -a "$OUT"
    echo "========================================" | tee -a "$OUT"
}

at_cmd() {
    local CMD="$1"
    printf '%s\r\n' "$CMD" > "$TTY"
    sleep 1
    # Đọc có sẵn trong buffer
}

# --- Detect TTY port ---
log "0. DETECT AT PORT"
for p in /dev/ttyUSB0 /dev/ttyUSB1 /dev/ttyUSB2 /dev/ttyUSB3; do
    echo -n "$p: " | tee -a "$OUT"
    if [ -c "$p" ]; then
        echo "EXISTS" | tee -a "$OUT"
    else
        echo "not found" | tee -a "$OUT"
    fi
done >> "$OUT" 2>&1
ls /dev/cdc-wdm* 2>/dev/null | tee -a "$OUT"

# --- System Info ---
log "1. SYSTEM INFO"
{
    echo "=== Hostname & Uptime ==="
    hostname
    uptime
    echo ""
    echo "=== Firmware Version ==="
    cat /etc/openwrt_release 2>/dev/null || cat /etc/os-release 2>/dev/null
} | tee -a "$OUT"

# --- Driver & Interface Info ---
log "2. MODEM DRIVER & INTERFACE"
{
    echo "=== lsmod qmi ==="
    lsmod | grep -i qmi

    echo ""
    echo "=== wwan0 driver ==="
    ls -la /sys/class/net/wwan0/device/driver 2>/dev/null

    echo ""
    echo "=== wwan interfaces ==="
    ip link show | grep wwan

    echo ""
    echo "=== wwan0 sysfs attributes ==="
    ls /sys/class/net/wwan0/ 2>/dev/null

    echo ""
    echo "=== qmap_mode ==="
    cat /sys/class/net/wwan0/qmap_mode 2>/dev/null || echo "NOT FOUND"

    echo ""
    echo "=== qmap_size ==="
    cat /sys/class/net/wwan0/qmap_size 2>/dev/null || echo "NOT FOUND"

    echo ""
    echo "=== raw_ip ==="
    cat /sys/class/net/wwan0/qmi/raw_ip 2>/dev/null || echo "NOT FOUND"

    echo ""
    echo "=== MTU ==="
    cat /sys/class/net/wwan0/mtu 2>/dev/null

    echo ""
    echo "=== USB device uevent ==="
    cat /sys/class/net/wwan0/device/uevent 2>/dev/null
} | tee -a "$OUT"

# --- quectel-CM-M Process ---
log "3. QUECTEL-CM-M PROCESS"
{
    ps | grep quectel | grep -v grep
} | tee -a "$OUT"

# --- Dial Log ---
log "4. DIAL LOG (last 60 lines)"
{
    LOGFILE=$(find /var/run/qmodem -name "dial_log" 2>/dev/null | head -1)
    if [ -n "$LOGFILE" ]; then
        echo "Log file: $LOGFILE"
        tail -60 "$LOGFILE"
    else
        echo "No dial_log found"
    fi
} | tee -a "$OUT"

# --- AT Commands ---
log "5. AT COMMANDS (via $TTY)"
{
    # Setup TTY nếu có stty
    if command -v stty >/dev/null 2>&1; then
        stty -F "$TTY" 115200 raw -echo 2>/dev/null
    fi

    run_at() {
        local DESC="$1"
        local CMD="$2"
        echo ""
        echo "--- $DESC ---"
        echo "CMD: $CMD"
        printf '%s\r\n' "$CMD" > "$TTY" 2>/dev/null
        sleep 1.5
    }

    run_at "Network Mode Preference" 'AT+QNWPREFCFG="mode_pref"'
    run_at "5G Disable Mode"         'AT+QNWPREFCFG="nr5g_disable_mode"'
    run_at "Serving Cell Info"       'AT+QENG="servingcell"'
    run_at "Signal Info"             'AT+QRSRP'
    run_at "USB Net Mode"            'AT+QCFG="usbnet"'
    run_at "Data Format"             'AT+QCFG="data_interface"'

    echo "(AT responses được đọc qua cat ở bước riêng vì không có timeout)"
} | tee -a "$OUT"

# Đọc buffer sau khi gửi tất cả AT commands
log "5b. AT RESPONSE BUFFER (doc buffer sau khi gui tat ca)"
{
    # Gửi lại từng lệnh và đọc
    _at_read() {
        local DESC="$1"
        local CMD="$2"
        echo ""
        echo "--- $DESC ---"
        printf '%s\r\n' "$CMD" > "$TTY" 2>/dev/null
        sleep 2
        dd if="$TTY" count=1 bs=512 2>/dev/null
    }

    _at_read "mode_pref"       'AT+QNWPREFCFG="mode_pref"'
    _at_read "nr5g_disable"    'AT+QNWPREFCFG="nr5g_disable_mode"'
    _at_read "servingcell"     'AT+QENG="servingcell"'
    _at_read "usbnet"          'AT+QCFG="usbnet"'
} | tee -a "$OUT"

# --- qmodem config ---
log "6. QMODEM CONFIG"
{
    echo "=== /etc/config/qmodem ==="
    cat /etc/config/qmodem 2>/dev/null || echo "File not found"

    echo ""
    echo "=== uci show qmodem ==="
    uci show qmodem 2>/dev/null || echo "uci not found or no qmodem"

    echo ""
    echo "=== qmodem init scripts ==="
    find /etc/init.d /usr/share/qmodem -name "*.sh" 2>/dev/null

    echo ""
    echo "=== search AT mode_pref in qmodem files ==="
    find /usr/share/qmodem /etc -name "*" -type f 2>/dev/null | \
        xargs grep -l "mode_pref\|QNWPREF\|nr5g\|NR5G" 2>/dev/null
} | tee -a "$OUT"

# --- Network State ---
log "7. NETWORK STATE"
{
    echo "=== ip route ==="
    ip route

    echo ""
    echo "=== ip addr ==="
    ip addr show | grep -A2 wwan

    echo ""
    echo "=== uqmi data format ==="
    uqmi -d /dev/cdc-wdm0 --get-data-format 2>/dev/null || echo "uqmi not found or error"

    echo ""
    echo "=== uqmi signal info ==="
    uqmi -d /dev/cdc-wdm0 --get-signal-info 2>/dev/null || echo "uqmi not found or error"

    echo ""
    echo "=== uqmi serving system ==="
    uqmi -d /dev/cdc-wdm0 --get-serving-system 2>/dev/null || echo "uqmi not found or error"
} | tee -a "$OUT"

# --- Done ---
echo "" | tee -a "$OUT"
echo "============================================" | tee -a "$OUT"
echo "DONE! Report saved to: $OUT" | tee -a "$OUT"
echo "============================================" | tee -a "$OUT"
echo "" | tee -a "$OUT"
echo "Cach lay report:"
echo "  cat $OUT"
echo "  Hoac copy qua SCP: scp root@192.168.1.1:$OUT ./"
