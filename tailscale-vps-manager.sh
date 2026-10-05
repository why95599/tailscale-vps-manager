#!/bin/bash
# TS_Manager.sh
# Tailscale Manager - Ubuntu VPS
# Menu based management script

set -e

CONFIG_DIR="/etc/ts-manager"
CONFIG_FILE="$CONFIG_DIR/config.conf"
TS_BIN="/usr/bin/tailscale"

mkdir -p "$CONFIG_DIR"

pause() {
    read -rp "按回车返回菜单..."
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "请使用 root 用户运行"
        exit 1
    fi
}

install_ts() {
    echo "[+] 安装 Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    echo "[OK] 安装完成"
    pause
}

upgrade_ts() {
    echo "[+] 升级 Tailscale..."
    apt update
    apt install --only-upgrade tailscale -y
    echo "[OK] 升级完成"
    pause
}

login_ts() {
    echo "[+] 登录 Tailscale"
    tailscale up
    pause
}

status_ts() {
    echo "====== Tailscale 状态 ======"
    tailscale status || true
    echo
    tailscale netcheck || true
    pause
}

select_exit() {
    echo "当前 Exit Node:"
    tailscale status | head -20
    echo
    read -rp "请输入 Exit Node IP: " NODE
    tailscale set --exit-node="$NODE"
    echo "[OK] 已设置 Exit Node $NODE"
    pause
}

cancel_exit() {
    tailscale set --exit-node=
    echo "[OK] 已取消 Exit Node"
    pause
}

enable_forward() {
    echo "[+] 开启 IPv4 转发"

    cat >/etc/sysctl.d/99-tailscale.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

    sysctl --system

    echo "[OK] IP 转发已固化"
    pause
}

self_exit() {
    echo "[+] 设置本机为 Exit Node"
    tailscale up --advertise-exit-node
    echo "[OK] 请在 Tailscale 控制台批准该节点"
    pause
}

disable_self_exit() {
    tailscale up --advertise-exit-node=false
    echo "[OK] 已关闭本机 Exit Node"
    pause
}

uninstall_manager() {
    echo "仅删除 TS Manager，不删除 Tailscale"
    read -rp "确认删除? (y/n): " Y
    if [ "$Y" = "y" ]; then
        rm -rf "$CONFIG_DIR"
        rm -f /usr/local/bin/TS_Manager.sh
        echo "[OK] 已删除"
    fi
    pause
}

menu() {
while true
do
clear
echo "============================================================"
echo "                 Tailscale Manager"
echo "============================================================"
echo
echo "1. 安装 Tailscale"
echo "2. 升级 Tailscale"
echo "3. 登录 Tailscale"
echo "4. 查看状态"
echo "5. 设置 Exit Node"
echo "6. 取消 Exit Node"
echo "7. 开启并固化 IP 转发"
echo "8. 本机设置为 Exit Node"
echo "9. 关闭本机 Exit Node"
echo "10. 安全卸载 TS Manager"
echo "0. 退出"
echo
read -rp "请选择: " CHOICE

case $CHOICE in
1) install_ts ;;
2) upgrade_ts ;;
3) login_ts ;;
4) status_ts ;;
5) select_exit ;;
6) cancel_exit ;;
7) enable_forward ;;
8) self_exit ;;
9) disable_self_exit ;;
10) uninstall_manager ;;
0) exit 0 ;;
*) echo "错误选择"; sleep 1 ;;
esac
done
}

check_root
menu
