# AULA F108Pro Driver for macOS

使用 Swift、AppKit 和 IOKit 为 AULA F108Pro 键盘重建的 macOS 配置工具，沿用原版界面素材和键盘布局。当前为实验版本，最低 macOS 13；现有构建在 Apple Silicon 上验证。

**USB 校时及实时灯光通信已收到实机确认；2.4G 协议与界面已接入，但配置握手尚未通过实机验证。** 不能把系统接受输出报文视为键盘已应用设置。

## 功能

- USB 校时、灯效模式、亮度、速度、颜色和方向。
- 普通层/Fn 层改键，多媒体、鼠标及宏绑定。
- 宏录制与编辑、逐键灯光、实时灯光帧、系统音频律动。
- 240×135 图片/GIF 编辑、RGB565 编码与 USB 上传。
- 休眠、响应档位和本地配置导入/导出。
- 自动、有线、2.4G 通道选择。

固件升级不在本项目范围内。部分高级快捷动作、全部宏播放模式及 Windows 配置格式兼容尚未实现。

## 从源码构建

需要 Xcode Command Line Tools、Swift、Python 3、`curl` 和 `innoextract`。应用本身没有第三方运行依赖。

```sh
brew install innoextract
git clone ssh://git@github.com/wujingke/aula-f108pro-driver-macos.git
cd aula-f108pro-driver-macos
sh tools/fetch-driver-assets.sh
sh tools/build-app.sh
open 'build/AULA F108Pro.app'
```

官方安装包、皮肤、字体和固件不存放在 Git 仓库中。`fetch-driver-assets.sh` 从厂商 CDN 下载指定版本，验证 SHA-256 后仅静态提取界面所需资源，不运行 Windows 安装程序。来源与权利说明见 [NOTICE.md](NOTICE.md)。

输出为 `build/AULA F108Pro.app`，使用本地 ad-hoc 签名，没有 Apple Developer ID 公证。

## 使用

1. 用数据线连接键盘，切换为 USB 模式；原配无线接收器可通过右上角选择器选中。
2. 编辑本地配置，点击应用后才会向设备写入。
3. 没有检测到所选配置接口时，设备写入按钮禁用。

“接收器已接入”只表示 USB 接收器枚举成功，不表示键盘无线配置链路在线。无线写入前会验证握手，失败就报错，不会继续发送配置数据。

原驱动无线菜单未开放的 TFT 上传和实时逐键帧，在本应用的无线模式中同样隐藏。

### 数据和权限

- 页面显示本地方案，不是设备完整配置的读回。
- 改键表、宏库、屏幕动画是整块替换；写入前会提示确认，未定义的按键恢复默认。
- 全局宏录制在开始录制时需要输入监控权限；Esc 停止。
- 音乐律动在开始时需要系统音频采集权限。
- 配置保存在用户的 Application Support 目录，不应放入 Git 仓库。

## 离线检查

```sh
'build/AULA F108Pro.app/Contents/MacOS/F108Pro' --self-test
'build/AULA F108Pro.app/Contents/MacOS/F108Pro' --ui-test
```

`--self-test` 检查 USB/2.4G 固定报文向量、校验和、改键和宏编码、RGB565、GIF 往返及配置边界。

`--ui-test` 检查有线9页、无线7页、模式切换、104键位点击区域及本地编辑，并生成 `build/previews/`。滑块还会进行13次来回拖动，将当前图层逐帧与干净绘制比较。

这两个命令不发送设备设置命令。离线检查不代替实机验证。

## 实机验证状态

| 项目 | 当前状态 |
| --- | --- |
| USB 校时 | 控制应答及完整日期时间回显通过 |
| USB 实时颜色推送 | 蓝/绿两次推送及恢复灯效命令均收到确认，视觉效果需人工观察 |
| USB RGB 查询 | 可读取9个64字节报文，共576字节；不等于完整配置备份 |
| 2.4G 接口识别 | 已确认原配 F108Pro Dongle 的32字节配置接口 |
| 2.4G 配置握手 | 尚未收到匹配应答，其他无线设置不能标为实机通过 |
| 改键、宏库和 GIF 上传 | 编码/离线检查通过，尚未进行覆盖式实机验收 |

实机测试工具源码在 `tools/hardware-check.swift` 和 `tools/wireless-hardware-check.swift`。只应在准备好接收设备改动时运行；无线灯效测试会恢复应用的本地灯光方案，不代表恢复了设备原方案。

## 独立校时 CLI

```sh
swiftc -parse-as-library -O f108-time.swift -o f108-time
./f108-time --list
./f108-time --dry-run
./f108-time --self-test
./f108-time --sync
```

也可在生成 CLI 后双击 `同步键盘时间.command`。

## 源码组织

- `Sources/DriverController.swift`、各页面文件：窗口、界面和交互。
- `Sources/Skin.swift`、`SkinControls.swift`：原版素材和自绘控件。
- `Sources/KeyboardDevice.swift`：通道选择和功能限制。
- `Sources/USBKeyboard.swift`、`USBStreaming.swift`：有线配置与传输。
- `Sources/WirelessKeyboard.swift`、`WirelessSettings.swift`：无线报文和应答校验。
- `Sources/Checks.swift`、`WirelessChecks.swift`、`SliderChecks.swift`：离线回归检查。
- `tools/`：资源准备、构建、应用元数据和针对性验证工具。

接口和协议摘要见 [docs/protocol.md](docs/protocol.md)。安装包、构建产物、分析转储、日志、缓存和用户数据均被 `.gitignore` 排除。
