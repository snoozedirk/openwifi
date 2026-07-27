#!/bin/bash
#==============================================================================
# 写入 10 个数据到 config_ram_if 的 addr 0~9，并读回验证
# 用法: ./test_rw.sh
#==============================================================================

DEV="sdr0"
SDRCTL="./sdrctl"

# ---- 要写入的 10 个数据 (16进制) ----
DATA_LIST=(
    deadbeef   # addr 0
    8badf00d   # addr 1
    badc0fe    # addr 2
    c0a80101   # addr 3
    11223344   # addr 4
    aabbcc
    #3232235972   # addr 4
    #3232235969   # addr 5
    #0            # addr 6
    #286331153    # addr 7
    #572662306    # addr 8
    #858993459    # addr 9
    #85858585     # addr 10
    #44332255     # addr 11
    #45456688     # addr 12
    #2021161080    # addr 13

)

# ---- 读寄存器 (取最后字段, 返回的是8位十六进制字符串) ----
get_reg() {
    $SDRCTL dev $DEV get reg tx_intf $1 2>/dev/null | grep 'val:' | awk '{print $NF}'
}

# ---- 写寄存器 ----
set_reg() {
    $SDRCTL dev $DEV set reg tx_intf $1 $2 >/dev/null 2>&1
}

# ---- 每次 WRITE ----
write_one() {
    local addr=$1 data=$2 seq=$3
    local cmd_raw reg30 ack_valid ack_seq

    echo -n "  [WRITE] addr=$addr data=$data seq=$seq ... "

    set_reg 19 $((0x$data))
    cmd_raw=$(( 1 << 30 | seq << 22 | addr << 14 ))
    set_reg 18 $cmd_raw

    for i in $(seq 1 500); do
        reg30=$(get_reg 30)
        [ -z "$reg30" ] && { sleep 0.001; continue; }
        reg30=$(( 0x$reg30 ))   #turn hex (string) to (decimal) number
        ack_valid=$(( (reg30 >> 8) & 1 ))
        ack_seq=$((   reg30        & 0xFF ))

        [ "$ack_valid" = "1" ] && [ "$ack_seq" = "$seq" ] && break
        sleep 0.001
    done

    if [ "$ack_valid" != "1" ] || [ "$ack_seq" != "$seq" ]; then
        echo "FAIL (ack_valid=$ack_valid ack_seq=$ack_seq expected=$seq)"
        return 1
    fi

    set_reg 18 0   # NOP
    echo "OK"
}

# ---- 每次 READ ----
read_one() {
    local addr=$1 seq=$2
    local cmd_raw reg30 read_valid data_raw

    cmd_raw=$(( 2 << 30 | seq << 22 | addr << 14 ))
    set_reg 18 $cmd_raw

    for i in $(seq 1 500); do
        reg30=$(get_reg 30)
        [ -z "$reg30" ] && { sleep 0.001; continue; }
        reg30=$(( 0x$reg30 ))  #turn hex string to decimal
        read_valid=$(( (reg30 >> 9) & 1 ))

        [ "$read_valid" = "1" ] && break
        sleep 0.001
    done

    if [ "$read_valid" != "1" ]; then
        echo "FAIL (read_valid=0)"
        return 1
    fi

    data_raw=$(get_reg 29)
    set_reg 18 0   # NOP

    echo "$data_raw"
}

#==============================================================================
# 主流程
#==============================================================================

echo "=== Phase 1: 写入 14 个地址 ==="
seq=0
for addr in $(seq 0 5); do
    write_one $addr ${DATA_LIST[$addr]} $seq || exit 1
    seq=$(( (seq + 1) & 0xFF ))
done
echo "写入 14 条完成"

echo ""
echo "=== Phase 2: 读回验证 ==="
seq=0
for addr in $(seq 0 5); do
    result=$(read_one $addr $seq )
    # 将 DATA_LIST 中的十进制数据转换为 8 位十六进制字符串
    expected=$(printf "%08x" 0x${DATA_LIST[$addr]})
    if [ "$result" = "$expected" ]; then
        echo "  [READ] addr=$addr: $result == $expected  OK"
    else
        echo "  [READ] addr=$addr: $result != $expected  MISMATCH"
    fi
    seq=$(( (seq + 1) & 0xFF ))
done

echo ""
echo "=== 完成 ==="