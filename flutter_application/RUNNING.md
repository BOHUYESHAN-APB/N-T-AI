Windows — 在 PowerShell 中安装与运行 Flutter（为本仓库的 `flutter_application` 项目）

下面是一步步、可复制的操作，适用于在 Windows（PowerShell / pwsh）上安装 Flutter、配置 PATH 并运行仓库中的 Flutter 项目。

重要说明：请在管理员权限或普通用户权限下按需执行命令。修改 PATH 后，重新打开 PowerShell 以使改动生效（或者在当前会话临时更新 PATH）。

一、下载 Flutter SDK

1. 打开浏览器访问：https://flutter.dev/docs/get-started/install/windows ，下载最新的 Flutter Windows SDK 压缩包（stable channel）。
2. 将压缩包解压到一个不需要管理员权限写入的位置，例如：

   解压到 C:\src\flutter

二、把 Flutter 加入 PATH（用户级）

下面的命令把 Flutter 的 bin 目录加入当前用户 PATH。请在 PowerShell（pwsh）中执行：

```powershell
# 将 Flutter SDK 解压到 C:\src\flutter 后运行（按需修改路径）
[Environment]::SetEnvironmentVariable('Path', $env:Path + ';C:\src\flutter\bin', 'User')

```

或者用 setx（注意：setx 有长度限制，推荐使用上面的方法）：

```powershell
setx PATH "%PATH%;C:\src\flutter\bin"
```

完成后关闭并重新打开 PowerShell（或启动新的终端），以便 PATH 生效。

三、验证安装

在新的 PowerShell 中运行：

```powershell
flutter --version
flutter doctor -v
```

如果看到 Flutter 版本与诊断输出，说明 CLI 可用。请按 flutter doctor 的建议安装缺失项（例如 Android SDK、Visual Studio 工作负载等）。

四、Windows 桌面与 Android 的必要依赖

- Windows 桌面：请安装 Visual Studio 2022（Community/Professional）并在安装时勾选“Desktop development with C++”工作负载（包含 MSVC、Windows SDK）。
- Android：安装 Android Studio，打开 SDK Manager 安装 Android SDK Platform（建议 SDK 31+）和 Android SDK Platform-Tools；同时安装一个 Android 模拟器或连接真实设备。

五、在仓库中运行项目（以 `flutter_application` 为例）

在 PowerShell 中切换到项目目录（示例路径请改为你的实际路径）：

```powershell
cd 'D:\-Users-\Documents\GitHub\N-T-AI\flutter_application'

# 获取依赖
flutter pub get

# 运行到 Windows（桌面）
flutter run -d windows

# 如果要运行 Android（确保已连接设备或启动模拟器）
flutter devices
flutter run -d <device-id>
```

如果你使用了不同的入口（比如 `lib/ui_main.dart`），可以指定入口文件：

```powershell
flutter run -t lib/ui_main.dart -d windows
```

六、常见问题与排查

- 问：PowerShell 报错 “flutter: The term 'flutter' is not recognized as the name of a cmdlet…”
  - 原因：Flutter 的 bin 没有加入当前用户或系统 PATH，或者你没有重启终端。
  - 解决：关闭并重新打开 PowerShell；或在当前会话临时运行：

    ```powershell
    $env:Path += ';C:\src\flutter\bin'
    flutter doctor -v
    ```

- 问：`flutter doctor` 报缺少 Visual Studio 或 Android 工具链
  - 解决：按 `flutter doctor` 的建议安装对应组件（Visual Studio 的 Desktop C++ 工作负载、Android Studio 与 SDK）。安装后重新运行 `flutter doctor`。

- 问：`ERROR: Unable to locate Android SDK` 或 构建 Android 失败
  - 设置 ANDROID_HOME / ANDROID_SDK_ROOT 环境变量，指向 Android SDK 路径（通常：C:\Users\<you>\AppData\Local\Android\Sdk）。可在 PowerShell 中临时设置：

    ```powershell
    $env:ANDROID_SDK_ROOT = 'C:\Users\<you>\AppData\Local\Android\Sdk'
    [Environment]::SetEnvironmentVariable('ANDROID_SDK_ROOT', 'C:\Users\<you>\AppData\Local\Android\Sdk', 'User')
    ```

七、如果你希望我继续：

- 我可以把我们之前的 Flutter UI 原型（聊天/笔记/社交的示例屏幕和 mock 数据）合并到本工程的 `lib/` 中，替换或作为新入口文件（如 `lib/ui_main.dart`）。请确认：
  1) 是否现在就把原型合并到 `flutter_application/lib/`？
  2) 你更希望覆盖当前 `main.dart`（默认模板）还是添加一个新的入口 `lib/ui_main.dart` 并保留原始 `main.dart`？

- 我也可以在项目根添加一个简短的 run 脚本（PowerShell）来自动执行 `flutter pub get` 与 `flutter run`，但这只在你本地安装 Flutter 后有用。

八、快速参考命令（复制粘贴用）

```powershell
# 在 PowerShell 中（按需修改路径）
[Environment]::SetEnvironmentVariable('Path', $env:Path + ';C:\src\flutter\bin', 'User')
cd 'D:\-Users-\Documents\GitHub\N-T-AI\flutter_application'
flutter pub get
flutter run -d windows
```

祝运行顺利！如果你愿意，我现在可以把我们的 UI 原型合并到 `flutter_application/lib/`（以新入口或覆盖方式）。请确认你的偏好（覆盖 main.dart 或 新建 ui_main.dart）。

项目级镜像已应用
- 我已在项目的 `android/settings.gradle.kts` 与 `android/build.gradle.kts` 中添加了阿里云 Maven 镜像（优先使用），以减少访问 maven.google.com 的超时问题。若你需要改回官方源或使用其他镜像（清华、USTC），我可以替你替换。

如果你希望我把这些更改回滚或改成其他镜像，请告诉我要使用的镜像 URL。

功能更新（最近）
- 聊天页已支持：
  - 表情面板（点击输入框左侧的笑脸按钮，弹出底部面板，点选后会插入到光标处）
  - 附件选择（点击回形针按钮，支持多选文件，会以“附件气泡”形式显示在消息中并持久化到本地）
  - 消息长按菜单可复制文本；若消息仅含附件会复制文件名列表
提示：首次在此工程运行前，请先执行一次 `flutter pub get`（上文有命令）。
