# 虚拟环境下 x86 架构测试方案验证报告

## 环境限制分析

在此前的多种环境中，PXE 启动均无法正常完成，主要受以下限制影响：

- wsl 的虚拟交换机基于 NAT ，不支持二层广播，导致 DHCP Discover 无法到达 PXE 服务器，VMware 的 NAT 模式同理
- QEMU 在 WSL 中无法创建可桥接的 TAP 设备，只能使用 usernet，而 usernet 不支持 PXE 所需的 DHCP 与 TFTP 协议
- 由于家用路由器限制 VMware 桥接模式也无法提供稳定的二层广播环境，PXE 启动无法正常进行

## 验证环境

本次 PXE 启动流程的验证在虚拟环境中进行 具体配置如下:

- 虚拟化平台：VMware
- 网络模式：Host‑Only
- 测试系统：Ubuntu 22.04（运行于 VMware 虚拟机内）
- qemu：qemu-system-x86_64 version 10.2.50

## PXE 服务端架构

```
┌─────────────────────────────────────────────────────────────┐
│                     QEMU (PXE Client)                       │
│                运行在 VMware 虚拟机内部                      │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        │ DHCP Discover / Offer / Request / Ack
                        │ TFTP 下载 boot.ipxe
                        ▼
┌──────────────────────────────────────────────────────────────┐
│              VMware Host‑Only虚拟交换机                       │
│                                                              │
└───────────────────────┬──────────────────────────────────────┘
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                     PXE 服务器（虚拟机）                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ DHCP Server │  │ TFTP Server │  │ 启动镜像             │  │
│  │ (dnsmasq)   │  │ (tftpd-hpa) │  │ - ipxe              │  │
│  │             │  │             │  │ - kernel            │  │
│  │             │  │             │  │                     │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## 验证流程
以下步骤描述本验证环境中完成 PXE 启动的具体实施过程
### 服务器配置

- 安装并配置 dnsmasq 

编辑 `/etc/dnsmasq.d/pxe.conf`
```
# 关闭本地 DNS 功能，只启用 DHCP/TFTP
port=0

# 指定监听的接口（根据环境修改）
interface=br0
bind-interfaces

# DHCP 地址池（根据网段修改）
dhcp-range=192.168.79.50,192.168.79.150,12h

# DHCP 选项：网关和 DNS（根据环境修改）
dhcp-option=3,192.168.79.2      # 网关
dhcp-option=6,8.8.8.8           # DNS

# PXE 启动配置（根据宿主机 IP 修改）
dhcp-boot=boot.ipxe,192.168.79.128

# 启用 TFTP 并指定根目录（路径可保持不变）
enable-tftp
tftp-root=/var/lib/tftpboot
```
确保 dnsmasq 主配置文件启用了子配置目录：
```
sudo vim /etc/dnsmasq.conf
# 取消注释：
conf-dir=/etc/dnsmasq.d/,*.conf
```
- 安装并配置 tftpd-hpa
编辑 `/etc/default/tftpd-hpa`
```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure"
```
- 创建 tftp 根目录
```
sudo mkdir -p /var/lib/tftpboot
sudo chmod -R 777 /var/lib/tftpboot
```
### 创建 ipxe 脚本
编辑 `/var/lib/tftpboot/boot.ipxe`
```
#!ipxe
kernel tftp://192.168.79.128/kernel #根据环境修改
boot
```
### 准备内核 
```
sudo cp axvisor /var/lib/tftpboot/kernel
# axvisor 由在 axvisor 仓库中执行 `cargo xtask build` 得到
```
### 桥接接口
```
sudo ip link add name br0 type bridge
sudo ip link set ens33 master br0
sudo ip tuntap add dev tap0 mode tap user $(whoami)
sudo ip link set tap0 master br0
sudo ip link set br0 up
sudo ip link set ens33 up
sudo ip link set tap0 up
sudo ip addr add 192.168.79.128/24 dev br0
ip addr show br0  #验证
```
### 启动服务器
```
sudo systemctl start dnsmasq
sudo systemctl enable dnsmasq
```
### qemu 启动指令
```
sudo qemu-system-x86_64 \
  -boot n \
  -m 128M \
  -smp 1 \
  -machine q35 \
  -netdev tap,id=mynet0,ifname=tap0,script=no,downscript=no \
  -device e1000,netdev=mynet0 \
  -device virtio-blk-pci,drive=disk0 \
  -drive id=disk0,if=none,format=raw,file=tmp/images/qemu_x86_64_nimbos/rootfs.img \
  -nographic
# rootfs.img 由 `cargo xtask image download qemu_x86_64_nimbos --output-dir tmp/images` 得到
```

## 验证结果

- 成功通过 PXE 完成 DHCP、TFTP、iPXE 等启动流程，并成功加载 AxVisor 内核。
- 由于测试环境为 AMD 处理器，AxVisor 无法启用 Intel VMX 虚拟化扩展，导致无法继续启动 NimbOS。

## PXE 启动流程分析

在上述环境中，PXE 启动链路如下：

1. QEMU 使用内置 iPXE ROM 从网卡发起 DHCP Discover
2. dnsmasq 通过 br0 接收到广播，返回 DHCP Offer 并通过 dhcp-boot 指定 boot.ipxe
3. iPXE 通过 TFTP 从 `192.168.79.128:/var/lib/tftpboot` 下载 `boot.ipxe`
4. `boot.ipxe` 中指定通过 TFTP 加载 `kernel`

## 未完成项

- 受家用路由器与桥接模式限制，当前无法在真实物理网络环境中完成 PXE 启动验证
- 当前处理器为 AMD 架构，而 AxVisor 的 x86 虚拟化模块仅支持 Intel VMX，不支持 AMD‑V（SVM）,即使 VMware 提供了嵌套虚拟化能力，AxVisor 仍无法启用硬件虚拟化，导致无法进入 NimbOS
- 本报告中的验证结果仅覆盖虚拟环境（VMware + QEMU） 真实硬件平台的启动流程仍需在具备可控网络与硬件条件后进一步测试

## 后续工作

尝试将 PXE 部署流程与已有 runner 结合 形成可复用的自动测试路径