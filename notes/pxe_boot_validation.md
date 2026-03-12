# 虚拟环境下 x86 架构测试方案验证报告

## 验证环境

本次 PXE 启动流程的验证在虚拟环境中进行 具体配置如下:

- 测试系统：Ubuntu 22.04
- qemu：qemu-system-x86_64 version 10.2.50
- PXE 网络模式：tap-only（QEMU ↔ tap0 ↔ dnsmasq）

## PXE 服务端架构

```
┌──────────────────────────────────────────────────────────────┐
│                     QEMU (PXE Client)                        │
└───────────────────────┬──────────────────────────────────────┘
                        │
                        │ DHCP Discover / Offer / Request / Ack
                        │ TFTP 下载 boot.ipxe / kernel
                        ▼
┌──────────────────────────────────────────────────────────────┐
│                     TAP 接口（tap0）                          │
└───────────────────────┬──────────────────────────────────────┘
                        ▼
┌──────────────────────────────────────────────────────────────┐
│                     PXE 服务器（dnsmasq）                    │
│  DHCP Server + TFTP Server + iPXE 镜像 + kernel 镜像         │
└──────────────────────────────────────────────────────────────┘

```

## 验证流程
以下步骤描述本验证环境中完成 PXE 启动的具体实施过程
### 服务器配置

- 安装并配置 dnsmasq 

编辑 `/etc/dnsmasq.d/pxe.conf`
```
# 关闭本地 DNS 功能，只启用 DHCP/TFTP
port=0

interface=tap0
bind-interfaces

dhcp-range=192.168.1.100,192.168.1.150,12h

dhcp-option=3,192.168.1.1            # 默认网关
dhcp-option=6,8.8.8.8                # DNS 服务器

dhcp-boot=undionly.kpxe              # PXE 阶段加载的第一个文件：iPXE 的 BIOS 镜像

pxe-service=x86PC, "iPXE", boot.ipxe # iPXE 阶段的链式加载：启动后从 TFTP 获取并执行 boot.ipxe 脚本

enable-tftp
tftp-root=/var/lib/tftpboot
```
确保 dnsmasq 主配置文件启用了子配置目录：
```
sudo vim /etc/dnsmasq.conf
# 取消注释：
conf-dir=/etc/dnsmasq.d/,*.conf
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
kernel tftp://192.168.1.200/kernel #根据环境修改
boot
```
### 准备内核 
```
sudo cp axvisor /var/lib/tftpboot/kernel
# axvisor 由在 axvisor 仓库中执行 `cargo xtask build` 得到
```
### 下载 iPXE 镜像
```
wget -O /var/lib/tftpboot/undionly.kpxe https://boot.ipxe.org/undionly.kpxe
```
### 创建二层接口(用于qemu tap)
```
ip tuntap add dev tap0 mode tap  multi_queue user "$USER"
ip link set tap0 up
ip addr add 192.168.1.200/24 dev tap0
# tap0 的 IP 即 PXE 服务器 IP，dnsmasq 会将该地址作为 next-server 返回给 iPXE
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
  -cpu host \
  -enable-kvm \
  -netdev tap,id=mynet0,ifname=tap0,script=no,downscript=no,vhost=off,queues=2 \
  -device virtio-net-pci,netdev=mynet0,mac=52:54:00:12:34:56 \
  -device virtio-blk-pci,drive=disk0 \
  -drive id=disk0,if=none,format=raw,file=tmp/images/qemu_x86_64_nimbos/rootfs.img \
  -nographic
# rootfs.img 由 `cargo xtask image download qemu_x86_64_nimbos --output-dir tmp/images` 得到
```

## 验证结果

- 成功通过 PXE 完成 DHCP、TFTP、iPXE 等启动流程，并成功加载 AxVisor 内核，启动 nimbos 客户机。

## PXE 启动流程分析

在上述环境中，PXE 启动链路如下：

1. QEMU 内置 iPXE ROM 发起 DHCP Discover
2. dnsmasq(监听 tap0)返回 `DHCP Offer`，并指定 `undionly.kpxe`
3. iPXE 通过 TFTP 从 `192.168.1.200:/var/lib/tftpboot` 下载 `boot.ipxe`
4. `boot.ipxe` 中指定通过 TFTP 加载 `kernel`

## 未完成项
- 本报告中的验证结果仅覆盖 QEMU 环境真实硬件平台的启动流程仍需在具备可控网络与硬件条件后进一步测试

## 后续工作

- [x] 尝试将 PXE 部署流程与已有 runner 结合 形成可复用的自动测试路径
- [x] 验证 runner-wrapper 适配情况

### 2.22更新
修改了错误的结论 更新启动链路 新增了pxe部署脚本(见 pxe-setup.sh)
### 3.12更新
解决部分环境问题 成功启动 nimbos 客户机 同步进度