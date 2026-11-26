# MonitorLight for Windows

MonitorLight 是一个 Windows 托盘工具，通过 DDC/CI 调节外接显示器的硬件背光与蓝通道冷暖。

## 下载与使用

1. 下载 [MonitorLight-Windows-x64.zip](https://github.com/zhuolin272-dotcom/MonitorLight/releases/download/windows-v1.0.0/MonitorLight-Windows-x64.zip)，解压后运行 `MonitorLight.exe`。
2. 首次打开会读取外接屏的当前档位。关闭窗口可收起面板，点击任务栏通知区域的太阳图标再次打开。图标可能显示在通知区域的折叠菜单里。右键托盘图标可退出程序。
3. 选择外接屏并拖动亮度滑块，或使用 15%、45%、80% 预设。`Ctrl + Alt + ↑ / ↓` 每次调节 5%，快捷键被占用时仍可使用面板。
4. 显示器支持读取 RGB 增益时，可勾选“启用蓝通道冷暖（未校准）”。偏冷增加蓝增益，偏暖降低蓝增益，两端幅度为蓝通道上限的 10%，并受硬件档位限制。首次改变蓝增益前会保存该屏的原始 RGB。“标准”和“恢复原色”将蓝增益恢复原始档位，红绿通道不参与写入。

本发布包适用于 **Windows 11 x64**，内含 .NET 运行时，无需额外安装。程序无管理员权限要求，启动、切屏、唤醒与重新检测时仅读取硬件设置。程序不自动加入登录项，EXE 当前无代码签名。

## 连接和兼容性

- 显示器 OSD 需要开启 DDC/CI（如果有该选项）。优先试 HDMI、DisplayPort 或 USB-C 直连。HDR、显示器图像模式、转接器或扩展坞可能限制亮度或 RGB 读写。
- Windows 需能独立识别目标外接屏。多屏建议使用“扩展”模式。内置屏、虚拟屏和无法区分目标的复制连接会被跳过。
- 亮度和冷暖分别读取。硬件拒绝或读回不匹配时，面板显示错误。冷暖失败时会尝试恢复调节前的蓝增益。
- 冷暖是相对色调，不表示绝对色温或 Kelvin 校准。原色按 Windows 显示器设备路径保存在 `%LOCALAPPDATA%\MonitorLight\`，同一台屏换接口后可能有不同记录。切换图像模式导致基线不匹配时，请切回保存原色时的模式。
- 应用运行时无联网或遥测。

## 实机验证

已在 Windows 11 x64 的 HKC G27M7Pro 外接屏上核验。应用快捷键将亮度 45% 调到 50% 后恢复至 45%。同一硬件通信层将 RGB 从 44/44/50 调到 44/44/49 后恢复原值。多屏切换、热插拔和其他型号仍需实机验证。

## 从源码构建

在 Windows x64 上安装 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)。在仓库根目录的 PowerShell 中运行以下命令。脚本先测试再打包，生成 `dist/MonitorLight-Windows-x64.zip`。

```powershell
./Windows/build.ps1
```

只运行逻辑测试，或对本机实际连接做只读探测：

```powershell
dotnet run --project Windows/MonitorLight.Tests -c Release
dotnet run --project Windows/MonitorLight.Tests -c Release -- --probe
```

显示器枚举使用 [Windows 活动显示路径](https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-querydisplayconfig)，硬件通信使用 [Win32 DDC/CI](https://learn.microsoft.com/windows/win32/monitor/using-the-low-level-monitor-configuration-functions)。
