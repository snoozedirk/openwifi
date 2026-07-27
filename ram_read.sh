#!/bin/bash
#==============================================================================
# 扫描 FPGA BRAM 全部 128 个 MAC 槽位, 输出非空条目到文件
# 用法: ./ram_read.sh [output_file]
#==============================================================================

DEV="sdr0"
SDRCTL="./sdrctl"
OUTPUT="${1:-addr_data_out.txt}"

get_reg() {
    $SDRCTL dev $DEV get reg tx_intf $1 2>/dev/null | grep 'val:' | awk '{print $NF}'
}
set_reg() {
    $SDRCTL dev $DEV set reg tx_intf $1 $2 >/dev/null 2>&1
}

# ---- 读一条 MAC (48-bit) ----
read_one() {
    local addr=$1 cmd_raw reg30 read_valid lo32 hi16 mac

    # 发送 READ
    cmd_raw=$(( 2 << 30 | addr << 22 ))   # hi16=0, lo32=0
    set_reg 18 $cmd_raw

#轮询 read_valid
    for i in $(seq 1 500); do
        reg30=$(get_reg 30); [ -z "$reg30" ] && { sleep 0.001; continue; }
        reg30=$(( 0x$reg30 ))
        read_valid=$(( (reg30 >> 9) & 1 ))
        [ "$read_valid" = "1" ] && break
        sleep 0.001
    done

    if [ "$read_valid" != "1" ]; then
        echo "FAIL (read_valid=0)"
        return 1
    fi
    # 低 32: reg29, 高 16: reg30[25:10]
    lo32=$(( 0x$(get_reg 29) ))
    hi16=$(( (reg30 >> 10) & 0xFFFF ))
    set_reg 18 0   # NOP

    # 拼 MAC: AA:BB:CC:DD:EE:FF
    # 过滤空槽: hi16=0 且 lo32=0 → 跳过
    if [ "$hi16" = "0" ] && [ "$lo32" = "0" ]; then
        return 0
    fi
    printf "%d  %02X:%02X:%02X:%02X:%02X:%02X\n" $addr \
        $(( hi16 >> 8 )) $(( hi16 & 0xFF )) \
        $(( (lo32 >> 24) & 0xFF )) $(( (lo32 >> 16) & 0xFF )) \
        $(( (lo32 >> 8) & 0xFF )) $(( lo32 & 0xFF ))
}

#==============================================================================

echo "# addr  MAC" > "$OUTPUT"
#echo "# $(date)"   >> "$OUTPUT"
echo "Scanning all 128 MAC slots, saving to $OUTPUT ..." >&2

for addr in $(seq 0 127); do
    read_one $addr >> "$OUTPUT"
done

echo "Done. $(grep -cv '^#' "$OUTPUT") data saved to $OUTPUT" >&2