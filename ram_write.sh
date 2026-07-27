#!/bin/bash
#==============================================================================
# 写入数据到 config_ram_if 的 addr 
#==============================================================================

DEV="sdr0"
SDRCTL="./sdrctl"
DATA_FILE="${1:-addr_data.txt}"

# ---- 从 txt 加载两列: 地址 数据 ----
declare -a ADDR DATA
while read -r a d; do
    [[ "$a" =~ ^# ]] && continue
    [[ -z "$a" ]]    && continue
    ADDR+=("$a")
    DATA+=("$d")
done < <(grep -v '^\s*$\|^\s*#' "$DATA_FILE")

echo "Loaded ${#ADDR[@]} data from $DATA_FILE"

# ---- 读寄存器 ----
get_reg() {
    $SDRCTL dev $DEV get reg tx_intf $1 2>/dev/null | grep 'val:' | awk '{print $NF}'
}

# ---- 写寄存器 ----
set_reg() {
    $SDRCTL dev $DEV set reg tx_intf $1 $2 >/dev/null 2>&1
}

# ---- 每次 WRITE (支持 MAC 格式 AA:BB:CC:DD:EE:FF 和 hex 格式) ----
write_one() {
    local addr=$1 data=$2
    local cmd_raw reg30 ack_valid ack_addr
    local hi16 lo32

    echo -n "  [WRITE] addr=$addr data=$data ... "


    # MAC 格式: AA:BB:CC:DD:EE:FF → hi16=AABB, lo32=CCDDEEFF
    local mac_clean=${data//:/}
    hi16=$(( 0x${mac_clean:0:4} ))
    lo32=$(( 0x${mac_clean:4:8} ))


    set_reg 19 $lo32
    cmd_raw=$(( 1 << 30 | addr << 22 | hi16 << 6 ))
    set_reg 18 $cmd_raw

    for i in $(seq 1 500); do
        reg30=$(get_reg 30)
        [ -z "$reg30" ] && { sleep 0.001; continue; }
        reg30=$(( 0x$reg30 ))   #turn hex (string) to (decimal) number
        ack_valid=$(( (reg30 >> 8) & 1 ))
        ack_addr=$((   reg30   & 0xFF ))

        [ "$ack_valid" = "1" ] && [ "$ack_addr" = "$addr" ] && break
        sleep 0.001
    done

    if [ "$ack_valid" != "1" ] || [ "$ack_addr" != "$addr" ]; then
        echo "FAIL (ack_valid=$ack_valid ack_addr=$ack_addr expected=$addr)"
        return 1
    fi

    set_reg 18 0   # NOP
    echo "OK"
}
#==============================================================================
# 主流程
#==============================================================================

echo "=== 写入地址 ==="
for i in $(seq 0 $((${#ADDR[@]} - 1))); do
    write_one ${ADDR[$i]} ${DATA[$i]} || exit 1
done
echo "=== 完成 ==="