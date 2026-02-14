# x86 平台 pxe 启动验证

## 结论

根据 https://github.com/orgs/arceos-hypervisor/discussions/347 基本于 wsl+qemu 环境成功复现测试 但有部分细节差异 思考在真实开发板上验证

## 验证流程

1.准备内核
```
sudo cp target/x86_64-unknown-none/release/axvisor /path/to/kernel
```

2.新建 `boot.ipxe`
```
#!ipxe
kernel tftp://10.0.2.2/kernel
boot
```

3.以如下指令启动 qemu
```
qemu-system-x86_64 \
  -m 128M \
  -smp 1 \
  -machine q35 \
  -device virtio-blk-pci,drive=disk0 \
  -drive id=disk0,if=none,format=raw,file=tmp/images/qemu_x86_64_nimbos/rootfs.img \
  #启用 QEMU 内置的 NAT 网络、DHCP 和 TFTP 服务
  -netdev user,id=u1 ,tftp=/path/to/tftp,bootfile=boot.ipxe \
  -device e1000,netdev=u1 \
  -boot n \
  -nographic \
  -accel kvm \
  -cpu host
```
## 差异

### 服务器配置相关

系统中 `eth0` 对应的 DHCP 端口似乎被 wsl 内部服务占用 现有环境无法通过文档中 dnsmasq 配置 DHCP 服务器

#### 解决方法

先使用 qemu 自带的 DHCP TFTP 服务验证后续流程 后续再尝试其他途径

### PXELINUX 相关

目前 axvisor 仓库中 执行 `cargo xtask build` 生成的文件格式为 elf 使用 PXELINUX 会有报错
```
Booting kernel failed: Invalid argument
```

#### 解决方法

使用 QEMU 内置 iPXE 成功启动内核
