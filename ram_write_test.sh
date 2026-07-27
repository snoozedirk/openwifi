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
    echo $(printf "hi16=%04X lo32=%08X\n" $hi16 $lo32)
}
echo "=== 写入地址 ==="
for i in $(seq 0 $((${#ADDR[@]} - 1))); do
   write_one ${ADDR[$i]} ${DATA[$i]} || exit 1
#echo "${ADDR[$i]} "
done
echo "=== 完成 ==="