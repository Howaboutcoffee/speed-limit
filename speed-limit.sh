#!/bin/bash
# ======================================================
# VPS 限速管理脚本（上行 + 下行）
# 功能：交互式设置或清除限速
# ======================================================

# 自动检测主网卡（排除 lo、ifb、docker、veth 等虚拟接口）
DEV=$(ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|ifb|docker|veth' | head -n1)

# 检查 root 权限
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ 请使用 root 权限运行此脚本"
  exit 1
fi

# 检查 ifb 模块
modprobe ifb 2>/dev/null
ip link add ifb0 type ifb 2>/dev/null
ip link set dev ifb0 up 2>/dev/null

clear
echo "======================================================"
echo " 🧩 VPS 限速管理工具"
echo "======================================================"
echo " 检测到的主网卡：$DEV"
echo "------------------------------------------------------"
echo " 1️⃣ 设置限速"
echo " 2️⃣ 清除限速"
echo " 3️⃣ 查看当前限速状态"
echo " 0️⃣ 退出"
echo "------------------------------------------------------"
read -rp "请输入选项编号: " CHOICE

case "$CHOICE" in
1)
  read -rp "请输入限速值 (单位 Mbps，例如 50): " SPEED
  if ! [[ "$SPEED" =~ ^[0-9]+$ ]]; then
    echo "❌ 输入错误，请输入整数（如 50）"
    exit 1
  fi
  RATE="${SPEED}mbit"
  BURST="4mb"

  echo "------------------------------------------------------"
  echo "🚧 清除旧限速规则..."
  tc qdisc del dev $DEV root 2>/dev/null
  tc qdisc del dev $DEV ingress 2>/dev/null
  tc qdisc del dev ifb0 root 2>/dev/null

  echo "⚙️  配置上行限速（出站 ${RATE}）..."
  tc qdisc add dev $DEV root handle 1: htb default 11
  tc class add dev $DEV parent 1: classid 1:11 htb rate $RATE ceil $RATE burst $BURST
  tc filter add dev $DEV protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:11

  echo "⚙️  配置下行限速（入站 ${RATE}）..."
  tc qdisc add dev $DEV ingress
  tc filter add dev $DEV parent ffff: protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev ifb0
  tc qdisc add dev ifb0 root tbf rate $RATE burst 32kbit latency 400ms

  echo "------------------------------------------------------"
  echo "✅ VPS 已限速：上行 ${SPEED} Mbps + 下行 ${SPEED} Mbps"
  echo "------------------------------------------------------"
  ;;

2)
  echo "🚧 正在清除限速规则..."
  tc qdisc del dev $DEV root 2>/dev/null
  tc qdisc del dev $DEV ingress 2>/dev/null
  tc qdisc del dev ifb0 root 2>/dev/null
  echo "✅ 已清除所有限速规则"
  ;;

3)
  echo "------------------------------------------------------"
  echo "📊 当前限速状态："
  echo
  tc qdisc show dev $DEV
  tc qdisc show dev ifb0
  echo "------------------------------------------------------"
  ;;

0)
  echo "👋 已退出。"
  exit 0
  ;;

*)
  echo "❌ 无效选项。"
  ;;
esac
