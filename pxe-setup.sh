#!/bin/bash

set -e

shell_die() { echo "[ERROR] $*" >&2; exit 1; }
shell_info() { echo "[INFO] $*"; }
shell_warn() { echo "[WARN] $*" >&2; }

# 网络配置                  
NETWORK_INTERFACE="eth0"               # 主网络接口
TAP_INTERFACE="tap0"                   # TAP 接口（用于 QEMU）
PXE_SERVER_IP="192.168.1.200"          # PXE 服务器 IP
GATEWAY="192.168.1.1"                  # 网关 IP
DNS_SERVER="8.8.8.8"                   # DNS 服务器

# DHCP 地址池
DHCP_START="192.168.1.100"
DHCP_END="192.168.1.150"
DHCP_LEASE_TIME="12h"

# TFTP 配置
TFTP_ROOT="/var/lib/tftpboot"
IPXE_SCRIPT="$TFTP_ROOT/boot.ipxe"

# 参数解析

show_usage() {
    cat << EOF
用法:
  sudo bash pxe-setup.sh [options] [interface] [pxe_ip] [gateway]

选项:
  --qemu                启用 QEMU 网桥配置
  --iface IFACE         指定物理网卡名称
  --ip IP               指定 PXE 服务器 IP
  --skip-ipxe-download  跳过 iPXE 文件下载
  --gateway GW          指定网关 IP
  -h, --help            显示帮助
  cleanup               清理部署的配置

示例:
  sudo bash pxe-setup.sh --qemu ens33
  sudo bash pxe-setup.sh --iface ens33 --ip 192.168.79.128 --gateway 192.168.79.2
  sudo bash pxe-setup.sh cleanup
EOF
}

require_arg() {
    if [ -z "$2" ]; then
        shell_die "参数 $1 需要值"
    fi
}

MODE="deploy"
QEMU=false
iface_set=false
ip_set=false
gw_set=false
ipxe_download=true
POSITIONAL=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        cleanup)
            MODE="cleanup"
            shift
            ;;
        --qemu)
            QEMU=true
            shift
            ;;
        --iface)
            require_arg "$1" "$2"
            NETWORK_INTERFACE="$2"
            iface_set=true
            shift 2
            ;;
        --ip)
            require_arg "$1" "$2"
            PXE_SERVER_IP="$2"
            ip_set=true
            shift 2
            ;;
        --gateway)
            require_arg "$1" "$2"
            GATEWAY="$2"
            gw_set=true
            shift 2
            ;;
        --skip-ipxe-download)
            ipxe_download=false
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -* )
            shell_die "未知参数: $1"
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

if [ ${#POSITIONAL[@]} -gt 0 ] && [ "$iface_set" = false ]; then
    NETWORK_INTERFACE="${POSITIONAL[0]}"
fi
if [ ${#POSITIONAL[@]} -gt 1 ] && [ "$ip_set" = false ]; then
    PXE_SERVER_IP="${POSITIONAL[1]}"
fi
if [ ${#POSITIONAL[@]} -gt 2 ] && [ "$gw_set" = false ]; then
    GATEWAY="${POSITIONAL[2]}"
fi

if [ "$QEMU" = true ]; then
    DHCP_INTERFACE="$TAP_INTERFACE"
else
    DHCP_INTERFACE="$NETWORK_INTERFACE"
fi

# 前置检查

check_root() {
    if [ "$EUID" -ne 0 ]; then
        shell_die "此脚本需要 root 权限，请使用 sudo 运行"
    fi
}

check_interface() {
    if ! ip link show "$NETWORK_INTERFACE" > /dev/null 2>&1; then
        shell_info "可用接口："
        ip link show | grep "^[0-9]" | awk '{print "  - " $2}'
        shell_die "网络接口 $NETWORK_INTERFACE 不存在"
    fi
}

# 安装依赖

install_dependencies() {
    shell_info "更新软件包列表..."
    apt-get update

    shell_info "安装依赖软件..."
    apt-get install -y dnsmasq bridge-utils iputils-ping > /dev/null 2>&1

    shell_info "✓ 依赖安装完成"
}

download_ipxe() {
    if [ "$ipxe_download" = true ]; then
        shell_info "下载 iPXE 引导文件..."
        mkdir -p "$TFTP_ROOT"
        wget -q -O "$TFTP_ROOT/undionly.kpxe" https://boot.ipxe.org/undionly.kpxe || shell_die "下载 iPXE 引导文件失败"
        chmod 644 "$TFTP_ROOT/undionly.kpxe"
        shell_info "✓ iPXE 文件下载完成: $TFTP_ROOT/undionly.kpxe"
    else
        shell_info "跳过 iPXE 文件下载(用户选择跳过下载)"
    fi
}

# 网络配置

setup_tap0() {
    shell_info "创建二层接口..."
    if ip link show "$TAP_INTERFACE" >/dev/null 2>&1; then
        shell_warn "TAP 接口 $TAP_INTERFACE 已存在，跳过创建"
    else
        ip tuntap add dev "$TAP_INTERFACE" mode tap user "$USER"
    fi
    ip link set "$TAP_INTERFACE" up
    if ip addr show "$TAP_INTERFACE" | grep -q "$PXE_SERVER_IP"; then
        shell_warn "TAP 接口 $TAP_INTERFACE 已配置 IP, 跳过"
    else
        ip addr add "$PXE_SERVER_IP"/24 dev "$TAP_INTERFACE"
    fi
}

configure_dnsmasq() {
    shell_info "配置 dnsmasq DHCP/TFTP 服务..."

    # 创建 dnsmasq 配置目录
    mkdir -p /etc/dnsmasq.d

    # 生成 PXE 配置文件
    cat > /etc/dnsmasq.d/pxe.conf << EOF
port=0

interface=$DHCP_INTERFACE
bind-interfaces

dhcp-range=$DHCP_START,$DHCP_END,$DHCP_LEASE_TIME

dhcp-option=3,$GATEWAY              # 默认网关
dhcp-option=6,$DNS_SERVER           # DNS 服务器

dhcp-boot=undionly.kpxe

pxe-service=x86PC, "iPXE", boot.ipxe

enable-tftp
tftp-root=$TFTP_ROOT
EOF

    shell_info "✓ dnsmasq 配置完成"
    shell_info "配置文件位置: /etc/dnsmasq.d/pxe.conf"
}

# TFTP 根目录设置

setup_tftp_root() {
    shell_info "创建 TFTP 根目录..."

    mkdir -p "$TFTP_ROOT"

    chmod 755 "$TFTP_ROOT"

    shell_info "✓ TFTP 根目录创建完成: $TFTP_ROOT"
}

# iPXE 脚本生成

create_ipxe_script() {
    shell_info "生成 iPXE 引导脚本..."

    cat > "$IPXE_SCRIPT" << 'EOF'
#!ipxe

echo "PXE Boot Started"
echo "Server: ${next-server}"

echo "Loading kernel from TFTP..."
kernel tftp://${next-server}/kernel

boot
EOF

    chmod 644 "$IPXE_SCRIPT"
    shell_info "✓ iPXE 脚本创建完成: $IPXE_SCRIPT"
    shell_info ""
    shell_info "iPXE 脚本内容(可根据需要修改):"
    cat "$IPXE_SCRIPT"
}

# 服务启动与自启配置

start_services() {
    shell_info "启动服务..."

    systemctl stop dnsmasq 2>/dev/null || true

    systemctl start dnsmasq
    systemctl enable dnsmasq

    shell_info "✓ 服务启动完成"
}

# 验证/状态检查

verify_setup() {
    shell_info "验证 PXE 服务配置..."
    echo ""

    shell_info "TAP 接口状态:"
    if [ "$QEMU" = true ]; then
        if ip link show "$TAP_INTERFACE" > /dev/null 2>&1; then
            echo "  ✓ TAP 接口 $TAP_INTERFACE 已创建"
            ip addr show "$TAP_INTERFACE" | grep "inet "
        else
            shell_warn "  ✗ TAP 接口未创建"
        fi
    else
        echo "  - 未启用 TAP 接口(未指定 --qemu)"
    fi
    echo ""

    shell_info "DHCP/TFTP 服务状态:"
    if systemctl is-active dnsmasq; then
        echo "  ✓ dnsmasq 运行中"
    else
        shell_warn "  ✗ dnsmasq 未运行"
    fi
    echo ""

    shell_info "TFTP 文件:"
    if [ -f "$IPXE_SCRIPT" ]; then
        echo "  ✓ $IPXE_SCRIPT 存在"
    else
        shell_warn "  ✗ $IPXE_SCRIPT 不存在"
    fi

    if [ -f "$TFTP_ROOT/kernel" ]; then
        echo "  ✓ kernel 文件存在"
    else
        shell_warn "  ✗ kernel 文件未找到(需要手动复制)"
    fi
    echo ""

    shell_info "端口监听:"
    netstat -tlnup 2>/dev/null | grep -E ":(53|67|69)" || echo "  检查端口监听..."
    ss -tulnup 2>/dev/null | grep -E ":(53|67|69)" || echo "  检查端口监听..."
}

# 使用说明

print_instructions() {
    shell_info "PXE 服务部署完成！"
    if [ "$QEMU" = true ]; then
        qemu_status="true"
    else
        qemu_status="false"
    fi
    echo ""
    echo "                        配置信息汇总"
    echo ""
    echo " 网络接口:           $NETWORK_INTERFACE"
    echo " QEMU 模式:          $qemu_status"
    echo " TAP 接口名称:       $TAP_INTERFACE"
    echo " PXE 服务器 IP:      $PXE_SERVER_IP"
    echo " DHCP 地址池:        $DHCP_START - $DHCP_END"
    echo " TFTP 根目录:        $TFTP_ROOT"
    echo " iPXE 脚本:          $IPXE_SCRIPT"
    echo ""
    echo "                       后续操作"
    echo ""
    echo " 1. 复制启动内核到 TFTP 目录:"
    echo "    sudo cp /path/to/kernel $TFTP_ROOT/kernel"
    echo ""
    echo " 2. 修改 iPXE 脚本 (如需要):"
    echo "    sudo vim $IPXE_SCRIPT"
    echo ""
    echo " 3. 卸载/清理 (如需要):"
    echo "    sudo bash pxe-setup.sh cleanup"
    echo ""
    if [ "$QEMU" = true ]; then
        echo " 4. 查看 QEMU 启动命令:"
        echo "    sudo qemu-system-x86_64 \\"
        echo "      -boot n \\"
        echo "      -m 128M \\"
        echo "      -machine q35 \\"
        echo "      -netdev tap,id=mynet0,ifname=$TAP_INTERFACE,script=no \\"
        echo "      -device e1000,netdev=mynet0 \\"
        echo "      -device virtio-blk-pci,drive=disk0 \\"
        echo "      -drive id=disk0,if=none,format=raw,file=/path/to/rootfs.img \\"
        echo "      -nographic"
    fi
    echo ""
}

# 清理/卸载函数

cleanup() {
    shell_warn "开始清理 PXE 服务..."

    shell_info "停止服务..."
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl disable dnsmasq 2>/dev/null || true

    # 移除 TAP 接口
    if ip link show "$TAP_INTERFACE" > /dev/null 2>&1; then
        ip link del "$TAP_INTERFACE" 2>/dev/null || true
    fi

    # 移除配置文件
    rm -f /etc/dnsmasq.d/pxe.conf

    shell_info "✓ 清理完成"
}

# 主函数

main() {
    # 处理清理命令
    if [ "$MODE" = "cleanup" ]; then
        check_root
        cleanup
        exit 0
    fi

    # 正常部署流程
    check_root
    if [ "$QEMU" = false ]; then
        check_interface
    fi

    shell_info "开始部署 PXE 服务..."
    shell_info "目标接口: $NETWORK_INTERFACE"
    shell_info "服务器 IP: $PXE_SERVER_IP"
    shell_info "QEMU 模式: $QEMU"
    echo ""

    install_dependencies
    if [ "$QEMU" = true ]; then
        setup_tap0
    else
        shell_info "跳过 TAP 接口配置(未指定 --qemu)"
    fi
    configure_dnsmasq
    setup_tftp_root
    download_ipxe
    create_ipxe_script
    start_services
    sleep 2
    verify_setup
    print_instructions
}

main "$@"
