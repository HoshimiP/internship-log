## qemu uboot 测试记录

### minicom相关

- 执行 `loady ${loadaddr}` 选择 `axvisor.bin` 后执行 `go ${loadaddr}`

    没有输出 疑似卡死
- 改用 `booti ${loadaddr} - ${fdt_addr}`

    成功进入 arceos 但没有看到 axvisor 输出 疑似卡死
- 在 `loady ${loadaddr}` 前 `loady ${fdt_addr}` 选定 `virt.dtb` 发送

    成功进入 axvisor shell 接下来尝试挂载 linux 启动
- 按相同步骤挂载 linux 启动
  卡死在 `Initialize interrupt handlers...`

### xtask uboot 相关

- 修改配置文件后执行 `cargo xtask uboot`

    报错
  ```
  Error: inflate() returned -5
  Image too large: increase CONFIG_SYS_BOOTM_LEN
  Must RESET board to recover
  Resetting the board...
  ```
- 在 `.u-boot.toml` 中添加 `fit_load_addr = "0xa0000000"` 设置更高加载地址

    成功进入启动流程 但仍然卡死在 `Initialize interrupt handlers...`
- 编译 `configs/vms/linux-aarch64-qemu-smp1.dts` 并于 `linux-aarch64-qemu-smp1.toml` 中指定

    偶尔出现 axvisor 输出 但都在进入 linux 前卡死 且测试结果无规律 暂时放弃

### 结论

在 qemu 环境模拟 uboot 启动存在困难 思考使用真实开发板复现
