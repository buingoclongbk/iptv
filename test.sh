#!/bin/sh
# ============================================================
# WH3000 Speed Diagnostic Script v2
# Test 4 cases: QWRT/Immortal x Direct/Passwall
# Usage: sh /tmp/test.sh [label]
#   label: qwrt_only | immortal_only | qwrt_passwall | immortal_passwall
# Output: /tmp/diag_[label].txt
# ============================================================

LABEL="${1:-unknown}"
OUT="/tmp/diag_${LABEL}.txt"
TTY="/dev/ttyUSB3"

> "$OUT"

log() {
    printf '\n========================================\n' | tee -a "$OUT"
    printf '>>> %s\n' "$1" | tee -a "$OUT"
    printf '========================================\n' | tee -a "$OUT"
}

hr() { printf -- '--- %s ---\n' "$1" | tee -a "$OUT"; }

# ============================================================
log "META: ROM & TIME"
# ============================================================
{
    echo "LABEL=$LABEL"
    echo "TIME=$(date)"
    cat /etc/openwrt_release 2>/dev/null | grep -E "DISTRIB_ID|DISTRIB_RELEASE|DISTRIB_DESCRIPTION"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime)"
} | tee -a "$OUT"

# ============================================================
log "1. CPU INFO"
# ============================================================
{
    hr "CPU model"
    cat /proc/cpuinfo | grep -E "model name|processor|BogoMIPS" | head -8

    hr "CPU governor"
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "$cpu: $(cat $cpu 2>/dev/null)"
    done

    hr "CPU frequency"
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        echo "$cpu: $(cat $cpu 2>/dev/null) Hz"
    done

    hr "CPU usage snapshot (top)"
    top -bn1 | head -15
} | tee -a "$OUT"

# ============================================================
log "2. MEMORY"
# ============================================================
{
    free -m
    echo ""
    cat /proc/meminfo | grep -E "MemTotal|MemFree|MemAvailable|Buffers|Cached"
} | tee -a "$OUT"

# ============================================================
log "3. MODEM DRIVER"
# ============================================================
{
    hr "lsmod qmi/wwan"
    lsmod | grep -iE "qmi|wwan|hnat|ppe|offload|flow"

    hr "wwan interfaces"
    ip link show | grep wwan

    hr "wwan driver symlink"
    ls -la /sys/class/net/wwan0/device/driver 2>/dev/null

    hr "qmap_mode / qmap_size"
    echo "qmap_mode=$(cat /sys/class/net/wwan0/qmap_mode 2>/dev/null || echo N/A)"
    echo "qmap_size=$(cat /sys/class/net/wwan0/qmap_size 2>/dev/null || echo N/A)"
    echo "raw_ip=$(cat /sys/class/net/wwan0/qmi/raw_ip 2>/dev/null || echo N/A)"
    echo "mtu_wwan0=$(cat /sys/class/net/wwan0/mtu 2>/dev/null)"
    echo "mtu_wwan0_1=$(cat /sys/class/net/wwan0_1/mtu 2>/dev/null)"
} | tee -a "$OUT"

# ============================================================
log "4. HARDWARE OFFLOAD STATUS"
# ============================================================
{
    hr "Kernel config: HNAT/PPE/FLOW_OFFLOAD"
    zcat /proc/config.gz 2>/dev/null | grep -iE "HNAT|PPE|FLOW_OFFLOAD|MEDIATEK_SOC" || echo "(config.gz not available)"

    hr "HNAT/PPE/offload modules"
    find /lib/modules -name "*hnat*" -o -name "*ppe*" -o -name "*flow*" 2>/dev/null | grep -v ppp_mppe

    hr "dmesg: hnat/ppe/offload/extif"
    dmesg | grep -iE "hnat|ppe|flow.offload|extif_set|offload" | head -20

    hr "nf_conntrack offload entries (should be > 0 if offload works)"
    cat /proc/net/nf_conntrack 2>/dev/null | grep -c "offload" || echo "0 offload entries"

    hr "nftables flow tables"
    nft list ruleset 2>/dev/null | grep -A5 -iE "flowtable|flow table|offload" | head -30 || echo "nft not found"

    hr "UCI firewall offload settings"
    uci get firewall.@defaults[0].flow_offloading 2>/dev/null && \
    uci get firewall.@defaults[0].flow_offloading_hw 2>/dev/null || echo "not set"
} | tee -a "$OUT"

# ============================================================
log "5. PASSWALL / PROXY STATUS"
# ============================================================
{
    hr "Proxy processes running"
    ps | grep -iE "sing.box|singbox|xray|v2ray|mihomo|clash|neko|trojan|hy2|hysteria" | grep -v grep

    hr "quectel-CM-M process"
    ps | grep quectel | grep -v grep

    hr "Passwall package version"
    opkg info passwall 2>/dev/null | grep -E "Package|Version"
    opkg info luci-app-passwall 2>/dev/null | grep -E "Package|Version"
    opkg info sing-box 2>/dev/null | grep -E "Package|Version"
    opkg info xray-core 2>/dev/null | grep -E "Package|Version"

    hr "Passwall binary version"
    sing-box version 2>/dev/null | head -3
    xray version 2>/dev/null | head -3

    hr "Passwall/bypass config mode"
    uci show passwall 2>/dev/null | grep -iE "server|node|type|protocol|bypass|mode" | head -30

    hr "Passwall iptables/nftables rules (proxy redirect)"
    nft list ruleset 2>/dev/null | grep -iE "redirect|tproxy|mark|dnat" | head -30
    iptables -t nat -L -n 2>/dev/null | grep -iE "REDIRECT|DNAT|passwall" | head -20
    iptables -t mangle -L -n 2>/dev/null | grep -iE "TPROXY|MARK" | head -20
} | tee -a "$OUT"

# ============================================================
log "6. NETWORK STACK SETTINGS"
# ============================================================
{
    hr "TCP congestion control"
    cat /proc/sys/net/ipv4/tcp_congestion_control
    cat /proc/sys/net/ipv4/tcp_available_congestion_control

    hr "Network buffers"
    sysctl net.core.rmem_max net.core.wmem_max net.core.rmem_default net.core.wmem_default 2>/dev/null
    sysctl net.ipv4.tcp_rmem net.ipv4.tcp_wmem 2>/dev/null

    hr "IP forwarding"
    cat /proc/sys/net/ipv4/ip_forward
    cat /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null

    hr "Softnet stats (CPU packet drops?)"
    cat /proc/net/softnet_stat

    hr "IRQ distribution (USB / network)"
    cat /proc/interrupts | grep -iE "xhci|eth|wwan|usb" | head -20
} | tee -a "$OUT"

# ============================================================
log "7. INTERFACE STATS (snapshot 1)"
# ============================================================
{
    for iface in wwan0 wwan0_1 br-lan eth0 eth1; do
        if ip link show "$iface" > /dev/null 2>&1; then
            hr "$iface stats"
            cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null | xargs -I{} echo "rx_bytes: {}"
            cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null | xargs -I{} echo "tx_bytes: {}"
            cat /sys/class/net/$iface/statistics/rx_dropped 2>/dev/null | xargs -I{} echo "rx_dropped: {}"
            cat /sys/class/net/$iface/statistics/tx_dropped 2>/dev/null | xargs -I{} echo "tx_dropped: {}"
        fi
    done
} | tee -a "$OUT"

# ============================================================
log "8. INTERFACE STATS (wait 5s, snapshot 2 for throughput estimate)"
# ============================================================
{
    echo "Sleeping 5 seconds..."
    sleep 5
    for iface in wwan0 wwan0_1 br-lan; do
        if ip link show "$iface" > /dev/null 2>&1; then
            hr "$iface stats after 5s"
            cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null | xargs -I{} echo "rx_bytes: {}"
            cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null | xargs -I{} echo "tx_bytes: {}"
        fi
    done
} | tee -a "$OUT"

# ============================================================
log "9. AT COMMAND: NETWORK MODE & CELL INFO"
# ============================================================
{
    _at() {
        local DESC="$1" CMD="$2"
        hr "$DESC"
        printf '%s\r\n' "$CMD" > "$TTY" 2>/dev/null
        sleep 1.5
        dd if="$TTY" count=1 bs=1024 2>/dev/null | tr -d '\r' | grep -v '^$'
    }

    _at "Network mode preference" 'AT+QNWPREFCFG="mode_pref"'
    _at "5G disable mode"         'AT+QNWPREFCFG="nr5g_disable_mode"'
    _at "Serving cell (FULL)"     'AT+QENG="servingcell"'
    _at "Signal strength"         'AT+QRSRP'
    _at "USB net mode"            'AT+QCFG="usbnet"'
    _at "QMAP data format"        'AT+QCFG="data_interface"'
    _at "Modem model"             'ATI'
} | tee -a "$OUT"

# ============================================================
log "10. DIAL LOG (last 30 lines)"
# ============================================================
{
    LOGFILE=$(find /var/run/qmodem -name "dial_log" 2>/dev/null | head -1)
    if [ -n "$LOGFILE" ]; then
        echo "File: $LOGFILE"
        tail -30 "$LOGFILE"
    else
        echo "No dial_log found"
    fi
} | tee -a "$OUT"

# ============================================================
log "11. QMODEM CONFIG"
# ============================================================
{
    hr "uci show qmodem"
    uci show qmodem 2>/dev/null

    hr "/etc/config/qmodem"
    cat /etc/config/qmodem 2>/dev/null

    hr "passwall server config (node info)"
    uci show passwall 2>/dev/null | grep -iE "type|address|port|protocol|transport|tls" | head -20
} | tee -a "$OUT"

# ============================================================
log "DONE"
# ============================================================
echo "" | tee -a "$OUT"
echo "Report saved: $OUT" | tee -a "$OUT"
echo ""
echo "============ HOW TO COPY REPORT ============"
echo " scp root@192.168.1.1:$OUT ./"
echo "============================================"
