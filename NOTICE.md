# 来源与资源说明

本仓库仅保存 macOS 实现源码、构建脚本和说明，不随仓库分发官方驱动安装包、固件、DLL、皮肤、图片或字体。

## 官方资源

资源准备脚本使用用户提供的厂商下载地址：

<https://cdn.aulacn.com/keyboard/AULA%20F108Pro%20Driver-1.0.0.3.exe>

安装包大小为 11,601,591 bytes，固定 SHA-256：

```text
62babdfdca614e5c27919d26278c845c549f3943bf2076cef0b7d56ae7e2afe8
```

脚本只静态提取本机构建所需资源，不运行安装程序。原版品牌标识、皮肤、字体和其他第三方素材的权利仍归其相应权利人，本仓库不替它们授予再分发许可。

## 协议参考

- 对指定版本 `DeviceDriver.exe` 的本地静态分析，使用 REA / Ghidra。
- 用户补充的 macOS LCD 工具：<https://github.com/jiarong0423/aula-f108pro-lcd-tool-macos>，用于交叉核对校时、RGB565 和 LCD 分包行为。

参考项目的 C 源码、官方二进制、固件和反编译结果未捆绑到本仓库。协议说明描述观察到的数据格式，不等同于全部功能已经完成硬件验证。
