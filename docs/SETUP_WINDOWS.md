# Windows 开发环境配置（N-T-AI）

本文档说明在 Windows 上配置本项目所需的开发工具、环境变量与常见问题的排查步骤（中文）。

## 概览
- Flutter SDK（已安装）
- Visual Studio 2022（Community/Professional/Enterprise）
- CMake（建议 >= 3.26，项目已兼容更高版本）
- Windows 10/11 SDK（通过 Visual Studio 安装）
- NuGet CLI（用于插件恢复）
- 可选：Android SDK（仅在需要 Android 构建时）

## 推荐安装步骤
1. 安装 Flutter（按官方文档）并把 `flutter/bin` 加入 PATH。验证：`flutter --version`
2. 安装 Visual Studio 2022，并使用 Installer 勾选工作负载：
   - **Desktop development with C++**（必须，包含 MSVC、cl、Windows SDK）
   - 可选：.NET/其他工作负载（按需要）
3. 安装 CMake（推荐通过官方安装器或 Chocolatey），验证：`cmake --version`
4. 获取 NuGet CLI：
   - 下载地址：https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
   - 建议放置：`C:\Tools\nuget\nuget.exe`
5. 将以下路径加入“用户”级 PATH（以你安装目录为准）：
   - `C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin`
   - `C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE`
   - `C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\<version>\bin\Hostx64\x64`（替换 `<version>`）
   - `C:\Tools\nuget`

> 提示：修改用户 PATH 后需要重新打开终端（或注销/重启）才能生效。

## 项目构建与运行（在仓库根）
```pwsh
# 进入项目
cd flutter_application
# 清理并获取依赖
flutter clean
flutter pub get
# 运行（调试）
flutter run -d windows
# 打包（发布）
flutter build windows --release
```

## 常见问题与排查
- `MissingPluginException`：通常是插件在构建期间未正确生成/链接到可执行文件。常见原因：
  - 构建环境（MSBuild / cl / nuget）未在 PATH 中，或 Visual Studio 未安装 C++ 工作负载。请确保 `where msbuild`、`where cl`、`where nuget` 能找到可执行路径。
  - 解决办法：确保上面的 PATH 配置正确，然后 `flutter clean && flutter pub get && flutter run -d windows`。

- CMake 警告（如 CMP0175）：属于开发者级别的警告，不会阻止构建。我们在 `windows/CMakeLists.txt` 中已加入策略以减少这些噪声。如果你希望完全清洁输出，可把 CMake 升级到 >= 3.26，并确保项目顶层 `CMakeLists.txt` 中包含策略设置。

- 网络资源检查失败（如 `flutter doctor` 报告 Maven/Git 超时）：通常为网络问题，不影响本地 Windows 构建本地插件，但可能影响 Android 构建或依赖解析。请确保代理/网络通畅。

## 我们在仓库做的改动（有用记录）
- `windows/CMakeLists.txt`：提高了 CMake policy 版本并设置 CMP0175 为 NEW，且设置 `CMAKE_SUPPRESS_DEVELOPER_WARNINGS`，以减少插件 CMake 带来的开发者级警告。
- 在 Flutter 层实现了应用内的 Live2D 悬浮控制（替代 web 内部按钮），并对 Live2D 前端做了响应式布局优化。
- 将 `nuget.exe` 建议放在 `C:\Tools\nuget`。

## 如果你想让我帮忙（可选）
- 我可以在你的环境里执行 `flutter clean && flutter pub get && flutter run -d windows` 并把详细日志返回。
- 我也可以帮助把上述 PATH 更新脚本写成 `.ps1` 文件，供你执行。请告知你偏好哪个方式。

---
文档维护：开发团队（自动生成/手动更新）。
