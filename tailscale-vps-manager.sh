#!/usr/bin/env bash
# tailscale-vps-manager.sh
# Ubuntu/Debian VPS Tailscale 管理脚本

set -u

MANAGER_PATH="/usr/local/bin/tailscale-vps-manager"
SYSCTL_FILE="/etc/sysctl.d/99-tailscale-forwarding.conf"

pause() {
    echo
    read -r -p "按回车返回菜单..." _
}

require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        echo "[ERROR] 请使用 root 用户运行。"
        echo "例如：sudo tailscale-vps-manager"
        exit 1
    fi
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

tailscale_installed() {
    has_cmd tailscale
}

install_tailscale() {
    echo "============================================================"
    echo " 安装 Tailscale"
    echo "============================================================"

    if tailscale_installed; then
        echo "[INFO] Tailscale 已安装："
        tailscale version 2>/dev/null | head -n 1 || true
        pause
        return
    fi

    if ! has_cmd curl; then
        echo "[INFO] 未检测到 curl，正在安装..."
        apt-get update && apt-get install -y curl || {
            echo "[ERROR] curl 安装失败。"
            pause
            return
        }
    fi

    echo "[INFO] 正在使用 Tailscale 官方安装脚本..."
    if curl -fsSL https://tailscale.com/install.sh | sh; then
        echo "[OK] Tailscale 安装完成。"
    else
        echo "[ERROR] Tailscale 安装失败。"
    fi
    pause
}

upgrade_tailscale() {
    echo "============================================================"
    echo " 升级 Tailscale"
    echo "============================================================"

    if ! tailscale_installed; then
        echo "[ERROR] 尚未安装 Tailscale，请先执行菜单 1。"
        pause
        return
    fi

    echo "[INFO] 当前版本："
    tailscale version 2>/dev/null | head -n 1 || true
    echo
    echo "[INFO] 正在检查并升级..."

    if apt-get update && apt-get install --only-upgrade -y tailscale; then
        echo
        echo "[OK] 升级完成。当前版本："
        tailscale version 2>/dev/null | head -n 1 || true
    else
        echo "[ERROR] 升级失败。"
    fi
    pause
}

login_tailscale() {
    echo "============================================================"
    echo " 登录 / 启用 Tailscale"
    echo "============================================================"

    if ! tailscale_installed; then
        echo "[ERROR] 尚未安装 Tailscale，请先执行菜单 1。"
        pause
        return
    fi

    systemctl enable --now tailscaled >/dev/null 2>&1 || true

    echo "[INFO] 如果本机尚未登录，将显示认证链接。"
    if tailscale up; then
        echo "[OK] Tailscale 已启用。"
    else
        echo "[ERROR] Tailscale 登录/启用失败。"
    fi
    pause
}

show_status() {
    echo "============================================================"
    echo " Tailscale 状态"
    echo "============================================================"

    if ! tailscale_installed; then
        echo "[INFO] Tailscale 未安装。"
        pause
        return
    fi

    echo "[版本]"
    tailscale version 2>/dev/null | head -n 1 || true
    echo

    echo "[服务]"
    if systemctl is-active --quiet tailscaled 2>/dev/null; then
        echo "tailscaled: RUNNING"
    else
        echo "tailscaled: NOT RUNNING"
    fi
    echo

    echo "[节点状态]"
    tailscale status 2>/dev/null || true
    echo

    echo "[IP 转发]"
    printf "IPv4: "
    sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "未知"
    printf "IPv6: "
    sysctl -n net.ipv6.conf.all.forwarding 2>/dev/null || echo "未知"

    pause
}

enable_forwarding() {
    echo "============================================================"
    echo " 开启并固化 IP 转发"
    echo "============================================================"

    cat >"$SYSCTL_FILE" <<'EOF'
# Managed by tailscale-vps-manager
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF

    if sysctl -p "$SYSCTL_FILE"; then
        echo "[OK] IPv4 / IPv6 转发已开启并固化。"
        echo "[INFO] 配置文件：$SYSCTL_FILE"
    else
        echo "[ERROR] IP 转发设置失败。"
    fi
    pause
}

enable_exit_node() {
    echo "============================================================"
    echo " 将本机提供为 Exit Node"
    echo "============================================================"

    if ! tailscale_installed; then
        echo "[ERROR] 尚未安装 Tailscale，请先执行菜单 1。"
        pause
        return
    fi

    if [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)" != "1" ]; then
        echo "[INFO] 检测到 IPv4 转发未开启，正在自动开启并固化..."
        cat >"$SYSCTL_FILE" <<'EOF'
# Managed by tailscale-vps-manager
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
        sysctl -p "$SYSCTL_FILE" >/dev/null 2>&1 || true
    fi

    if tailscale set --advertise-exit-node=true; then
        echo "[OK] 本机已开始发布 Exit Node 能力。"
        echo "[INFO] 如管理后台需要审批，请在 Tailscale Admin Console 中批准。"
    else
        echo "[ERROR] 设置 Exit Node 失败。"
    fi
    pause
}

disable_exit_node() {
    echo "============================================================"
    echo " 关闭本机 Exit Node"
    echo "============================================================"

    if ! tailscale_installed; then
        echo "[ERROR] Tailscale 未安装。"
        pause
        return
    fi

    if tailscale set --advertise-exit-node=false; then
        echo "[OK] 本机已停止发布 Exit Node。"
    else
        echo "[ERROR] 操作失败。"
    fi
    pause
}

uninstall_tailscale() {
    echo "============================================================"
    echo " 卸载 Tailscale 程序"
    echo "============================================================"
    echo
    echo "此操作将停止 tailscaled 服务并卸载 Tailscale 软件包。"
    echo "默认保留 /var/lib/tailscale 中的节点状态数据。"
    echo
    read -r -p "确认卸载 Tailscale？请输入 y 继续: " answer

    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "[INFO] 已取消。"
        pause
        return
    fi

    systemctl stop tailscaled >/dev/null 2>&1 || true
    systemctl disable tailscaled >/dev/null 2>&1 || true

    if apt-get remove -y tailscale; then
        echo
        echo "[OK] Tailscale 程序已卸载。"
        echo "[INFO] 节点状态数据仍保留在 /var/lib/tailscale（如原来存在）。"
    else
        echo "[ERROR] Tailscale 卸载失败。"
    fi

    pause
}

uninstall_manager() {
    echo "============================================================"
    echo " 卸载管理器（保留 Tailscale）"
    echo "============================================================"
    echo
    echo "此操作只删除 tailscale-vps-manager 管理脚本，"
    echo "不会卸载 Tailscale，也不会删除 Tailscale 登录状态。"
    echo
    read -r -p "确认卸载管理器？请输入 y 继续: " answer

    if [ "$answer" != "y" ] && [ "$answer" != "Y" ]; then
        echo "[INFO] 已取消。"
        pause
        return
    fi

    if [ -f "$MANAGER_PATH" ]; then
        rm -f "$MANAGER_PATH"
        echo "[OK] 已删除：$MANAGER_PATH"
    else
        echo "[INFO] 未发现固定安装文件：$MANAGER_PATH"
        echo "[INFO] 如果你使用 bash <(curl ...) 临时运行，本身无需卸载。"
    fi

    echo "[INFO] Tailscale 程序已保留。"
    echo
    echo "管理器已卸载，本次脚本运行即将结束。"
    exit 0
}

menu() {
    while true; do
        clear 2>/dev/null || true
        echo "============================================================"
        echo "                 Tailscale VPS Manager"
        echo "============================================================"
        echo
        echo "1. 安装 Tailscale"
        echo "2. 升级 Tailscale"
        echo "3. 登录 Tailscale"
        echo "4. 查看状态"
        echo "5. 开启并固化 IP 转发"
        echo "6. 将本机提供为 Exit Node"
        echo "7. 关闭本机 Exit Node"
        echo "8. 卸载 Tailscale 程序"
        echo "9. 卸载管理器（保留 Tailscale）"
        echo "0. 退出"
        echo

        read -r -p "请选择: " choice

        case "$choice" in
            1) install_tailscale ;;
            2) upgrade_tailscale ;;
            3) login_tailscale ;;
            4) show_status ;;
            5) enable_forwarding ;;
            6) enable_exit_node ;;
            7) disable_exit_node ;;
            8) uninstall_tailscale ;;
            9) uninstall_manager ;;
            0) exit 0 ;;
            *) echo "[ERROR] 无效选项。"; sleep 1 ;;
        esac
    done
}

require_root
menu
