# 实习日志

## 任务一、完善自动测试系统部署

### 目标：简化自动测试的部署，尽量实现一键部署本地测试的脚本，并完善测试的文档。

时间：1.25 - 2.13(暂定)

### 工作计划
- week1 1.25 - 1.31
  
  复现已有的测试，阅读源码理解现有的自动测试结构，制定下一步工作计划
- week2 2.1 - 2.6
  
  在 qemu 尝试使用 uboot 和 pxe 加载内核并运行，完善文档

## 任务二、完善 x86 平台的集成测试支持

- week3 - week5 2.8 - 2.28
  继续验证[x86测试方案](https://github.com/orgs/arceos-hypervisor/discussions/347) 尝试将 pxe 服务器部署流程与现有[runner](https://github.com/arceos-hypervisor/github-runners)结合 实现服务器配置与ipxe脚本编辑的自动化 并测试其功能 编写完整的部署文档
  
## 任务三、完善 starry-vdso 尝试编写基于 vdso fast path 的用户态线程调度器

## 日志

### 第1周
1.25 - 1.31

- 按 https://arceos-hypervisor.github.io/axvisorbook/docs/quickstart/qemu 上的步骤成功复现 qemu 平台的测试
- 按 https://arceos-hypervisor.github.io/axvisorbook/docs/design/test/runner 部署 github-runner 成功运行 qemu 平台的 ci
- 尝试使用 uboot 在 qemu-aarch64 模拟真实开发板测试流程 学习 uboot 使用与 qemu 配置 并尝试挂载 linux 启动

### 第2周

2.2 - 2.7

- 尝试在 qemu 环境使用 uboot 启动 linux 客户机时多次卡死 修改配置无果 暂时跳过 具体测试记录见 [uboot_log](notes/uboot_log.md)
- 成功使用 uboot 在 qemu 环境启动 arceos 客户机
- 按照 https://github.com/orgs/arceos-hypervisor/discussions/347 成功验证测试流程 运行 nimbos 客户机 具体实现与原文有差异 见 [pxe_log](notes/pxe_log.md)
- 尝试扩展 xtask 需要进一步计划具体实现

### 第3周

2.8 - 2.14

- 解决先前的部分环境问题 成功在本地环境验证完整x86测试方案 并编写[验证报告](notes/pxe_boot_validation.md)
- 阅读现有 runner 源码 分析 pxe 服务自动部署的接入点

### 第5周

2.22 - 2.28

- 对[验证报告](notes/pxe_boot_validation.md)中的错误内容进行更正
- 编写了 pxe 服务的[自动部署脚本](pxe-setup.sh) 包括 VMware + qemu 和真实环境的部署流程 并交付给赵长收老师进行验证
- 拆分 pxe 自动部署脚本 并尝试与已有 runner 结合 已提交到分支 [github-runners](https://github.com/HoshimiP/github-runners/tree/feat/pxe-setup)

- 编写改进后runner的使用文档 见 https://github.com/HoshimiP/github-runners/blob/feat/pxe-setup/docs/pxe-setup-guide.md

### 第6周

3.1 - 3.7

- 修复了 runner 中 pxe 脚本的问题 经验证成功在本地部署可用的 pxe 服务
- 尝试补充 https://arceos-hypervisor.github.io/axvisorbook/docs/design/test 中 x86 部分 初稿已完成 真实环境部署待验证

### 第7周

3.8 - 3.14

- 解决了部分物理环境问题 更新了[验证报告](notes/pxe_boot_validation.md)
- 验证 pxe-qemu 的自动化测试流程
- 验证现有流程与 runner-wrapper 的适配
- 尝试分析 [starry-vdso](https://github.com/Starry-OS/starry-vdso) 源码 编写了部分单元测试

### 第8-9周

3.15 - 3.28

- 将 starry-vdso 接入 starryOS 并编写用户态测试 验证时间相关函数已经能够走 vdso 路径 具体验证结果见[笔记](notes/vdso.md)
- 修改了 x86 架构 getcpu 的初始化实现 为每个 cpu 分配独立 GDT 空间
- 实现了 loongarch64 架构的 vdso_getcpu

    遇到的问题

-  loongarch64 / aarch64 / riscv64 的 musl 中缺少部分 vdso 入口 libc 调用会直接走 syscall 具体见[笔记](notes/vdso.md)

### 第10-11周

- 使用 vdso-helper 编译了包含自定义 fast path 的 .so 文件
- 优化了 starry-vdso 的 vvar 映射逻辑 使用户态可以正常通过 vdso基地址+偏移量 调用自定义 vdso 接口
- 在已有可加载模块 `modules/kebpf` 中增加 vdso 数据页的更新逻辑。当有 ebpf 程序执行时，会将结果从 map 写入 vvar ，用户态可以直接通过 fast path 访问而避免使用系统调用读 map
- 在 `api/src/lib.rs` 处增加 vdso 数据页的更新逻辑。每次 `register_timer_callback` 时会在 vvar 更新当前任务快照
