# CI/CD 自动化构建与签名配置指南

本指南将详细介绍如何生成 Android 和 Windows 的签名证书，并将其配置到 GitHub Secrets 中，以便使用自动化工作流 (`.github/workflows/release.yml`) 进行构建和发布。

---

## 1. 准备工作：控制开关

我们在项目根目录增加了一个文件 `CI_PERMISSION.md`。
*   **开启构建**：文件内容为 `true`
*   **关闭构建**：文件内容为 `false`

每次发布前，请确保该文件内容为 `true`，否则即使打上了 Tag，GitHub Actions 也会自动跳过构建，为您节省额度。

---

## 2. Android 签名配置 (APK)

Android 应用发布需要一个密钥库文件 (`.jks`)。

### 第一步：生成密钥库 (Keystore)

如果您安装了 Android Studio 或 Java JDK，电脑上应该已经有 `keytool` 工具。

1.  打开终端 (Terminal) 或 PowerShell。
2.  运行以下命令（请修改 `my-upload-key.jks` 为您想要的文件名，`my-key-alias` 为您想要的别名）：

    ```bash
    keytool -genkey -v -keystore my-upload-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias my-key-alias
    ```

3.  **按提示输入信息**：
    *   **输入密钥库口令**: 设置一个强密码（例如 `123456`，请务必记住！）。
    *   **您的名字与姓氏是什么？**: 随便填（例如 `N-T-AI Dev`）。
    *   后续问题（组织单位、城市等）可以回车跳过或随便填。
    *   **是否正确？**: 输入 `y` 并回车。

    完成后，当前目录下会生成一个 `my-upload-key.jks` 文件。

### 第二步：获取 Base64 编码

GitHub 不能直接上传文件作为 Secret，我们需要把文件转换成一串文本（Base64 编码）。

*   **Windows (PowerShell)**:
    ```powershell
    [Convert]::ToBase64String([IO.File]::ReadAllBytes("my-upload-key.jks")) | Set-Clipboard
    ```
    *(执行后，编码内容已自动复制到剪贴板)*

*   **Mac / Linux**:
    ```bash
    base64 -i my-upload-key.jks | pbcopy
    ```

### 第三步：配置 GitHub Secrets

1.  打开您的 GitHub 仓库页面。
2.  点击顶部菜单的 **Settings** (设置)。
3.  在左侧侧边栏找到 **Secrets and variables** -> **Actions**。
4.  点击 **New repository secret** (新建仓库密钥)。

我们需要添加以下 4 个密钥：

| Name (密钥名称) | Value (密钥值) | 说明 |
| :--- | :--- | :--- |
| `ANDROID_KEYSTORE_BASE64` | (粘贴刚才复制的一长串 Base64 字符) | 密钥库文件的文本形式 |
| `ANDROID_STORE_PASSWORD` | `123456` (您设置的密码) | 密钥库的密码 |
| `ANDROID_KEY_PASSWORD` | `123456` (通常与上面相同) | 别名的密码 |
| `ANDROID_KEY_ALIAS` | `my-key-alias` (您设置的别名) | 密钥的别名 |

---

## 3. Windows 签名配置 (MSIX)

Windows 应用发布需要一个 PFX 证书。

### 第一步：生成自签名证书

在 Windows 电脑上，打开 **PowerShell (以管理员身份运行)**，执行以下命令：

```powershell
# 1. 创建证书
$cert = New-SelfSignedCertificate -Type Custom -Subject "CN=N-T-AI" -KeyUsage DigitalSignature -FriendlyName "N-T-AI-Cert" -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

# 2. 设置密码 (请将 YourPassword 替换为您的密码)
$password = ConvertTo-SecureString -String "YourPassword" -Force -AsPlainText

# 3. 导出为 PFX 文件 (文件将保存在当前目录)
Export-PfxCertificate -Cert $cert -FilePath "certificate.pfx" -Password $password
```

完成后，当前目录下会生成一个 `certificate.pfx` 文件。

### 第二步：获取 Base64 编码

同样，我们需要把 PFX 文件转为文本。

*   **Windows (PowerShell)**:
    ```powershell
    [Convert]::ToBase64String([IO.File]::ReadAllBytes("certificate.pfx")) | Set-Clipboard
    ```
    *(执行后，编码内容已自动复制到剪贴板)*

### 第三步：配置 GitHub Secrets

回到 GitHub 的 Secrets 页面，添加以下 2 个密钥：

| Name (密钥名称) | Value (密钥值) | 说明 |
| :--- | :--- | :--- |
| `WINDOWS_PFX_BASE64` | (粘贴刚才复制的 Base64 字符) | PFX 证书的文本形式 |
| `WINDOWS_CERT_PASSWORD` | `YourPassword` (您设置的密码) | 证书密码 |

---

## 4. 如何触发自动发布

配置完成后，您**不需要**手动运行本地脚本。只需按照以下流程操作：

1.  **修改代码**：在本地完成开发。
2.  **更新日志**：编辑 `CHANGELOG.md`，在顶部添加新版本号和更新内容。
    *   *注意：请严格保持格式，例如 `## [0.3.4] - 2025-12-08`*
3.  **检查开关**：确保根目录的 `CI_PERMISSION.md` 内容为 `true`。
4.  **提交并推送**：将代码推送到 GitHub。
5.  **打标签 (Tag)**：
    *   **方法 A (GitHub Desktop)**: 暂时不支持直接打 Tag，建议使用命令行。
    *   **方法 B (命令行)**:
        ```bash
        git tag v0.3.4
        git push origin v0.3.4
        ```
    *   **方法 C (GitHub 网页)**: 在仓库首页点击 "Releases" -> "Draft a new release" -> "Choose a tag" (输入新版本号) -> 点击 "Publish release" (这也会触发 Action)。

**触发后发生什么？**
1.  GitHub Actions 会自动检测 `CI_PERMISSION.md`，如果是 `false` 则停止。
2.  它会自动运行 `update_version.ps1` 脚本，将 `CHANGELOG.md` 中的版本号同步到 `pubspec.yaml`。
3.  构建 Android APK 和 Windows MSIX。
4.  自动截取 `CHANGELOG.md` 中最新版本的更新说明。
5.  在 GitHub Releases 页面发布正式版本，并附带安装包。
