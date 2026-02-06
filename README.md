# 实习日志

## 任务一、完善自动测试系统部署

### 目标：简化自动测试的部署，尽量实现一键部署本地测试的脚本，并完善测试的文档。

时间：1.25 - 2.13(暂定)

### 工作计划
- week1 1.25 - 1.31
  
  复现已有的测试，阅读源码理解现有的自动测试结构，制定下一步工作计划
- week2 2.1 - 2.6
  
  在 qemu 尝试使用 uboot 和 pxe 加载内核并运行，完善文档

- week3 2.8 - 
  尝试在 xtask 中添加 pxe 相关指令，思考使用真实开发板复现相关测试


## 任务二、完善 x86 平台的集成测试支持

## 任务三、为其他组件添加测试用例

## 日志

### 第一周
1.25 - 1.31

- 按 https://arceos-hypervisor.github.io/axvisorbook/docs/quickstart/qemu 上的步骤成功复现 qemu 平台的测试
- 按 https://arceos-hypervisor.github.io/axvisorbook/docs/design/test/runner 部署 github-runner 成功运行 qemu 平台的 ci
- 尝试使用 uboot 在 qemu-aarch64 模拟真实开发板测试流程 学习 uboot 使用与 qemu 配置 并尝试挂载 linux 启动

### 第二周

2.2 - 2.6

- 尝试在 qemu 环境使用 uboot 启动 linux 客户机时多次卡死 修改配置无果 暂时跳过 具体测试记录见 [uboot_log](notes/uboot_log.md)
- 成功使用 uboot 在 qemu 环境启动 arceos 客户机
- 按照 https://github.com/orgs/arceos-hypervisor/discussions/347 成功验证测试流程 运行 nimbos 客户机 具体实现与原文有差异 见 [pxe_log](notes/pxe_log.md)
- 尝试扩展 xtask 需要进一步计划具体实现