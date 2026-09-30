---

## 下载 · Download

| 文件 · File | 说明 · Notes |
| --- | --- |
| `MiVibe-{{VERSION}}-arm64.dmg` | 推荐。打开后把 MiVibe 拖进「应用程序」。 Recommended: open it and drag MiVibe into Applications. |
| `MiVibe-{{VERSION}}-arm64.zip` | 同一个 App 的压缩包，解压即用。 The same app as a zip. |

需要 Apple Silicon Mac、macOS 14 及以上，以及一支小米蓝牙语音遥控器（已验证 VID `0x2717` / PID `0x32B8`、固件 2671）。
Requires an Apple Silicon Mac on macOS 14 or later and a Xiaomi Bluetooth voice remote (verified VID `0x2717` / PID `0x32B8`, firmware 2671).

<details>
<summary><b>安装说明（中文）</b></summary>

1. 打开 DMG，把 **MiVibe** 拖进 **应用程序**。
2. 这个版本没有经过苹果公证，首次打开会提示"无法验证开发者"。打开 **系统设置 → 隐私与安全性**，在页面底部点 **仍要打开**。也可以在终端执行下面这行，去掉下载隔离标记：
   ```sh
   xattr -dr com.apple.quarantine /Applications/MiVibe.app
   ```
3. 在 **系统设置 → 蓝牙** 配对遥控器，然后从菜单栏打开 MiVibe 的设置：
   - **识别**：填豆包 API Key，或下载一个本地识别模型。
   - **权限**：按提示授予蓝牙、辅助功能与事件投递；开启按键接管时还需要输入监控。
4. 把光标放进任意输入框，按住遥控器语音键说话，松手后文字写入。

**升级提示：** 这里的安装包是 CI 用临时签名打的，每个版本的签名都不同。覆盖安装后 macOS 可能把它当成新应用，需要在「隐私与安全性」里重新勾选辅助功能和输入监控（先删掉旧条目再添加最稳妥）。

</details>

<details>
<summary><b>Install guide (English)</b></summary>

1. Open the DMG and drag **MiVibe** into **Applications**.
2. This build is not notarized. On first launch macOS says the developer cannot be verified: open **System Settings → Privacy & Security** and click **Open Anyway**, or remove the quarantine flag:
   ```sh
   xattr -dr com.apple.quarantine /Applications/MiVibe.app
   ```
3. Pair the remote in **System Settings → Bluetooth**, then open MiVibe's settings from the menu bar: add a Doubao API key or download a local model under **识别 (Recognition)**, and grant the permissions it asks for.
4. Focus a text field, hold the voice key, speak, and release.

**Upgrading:** each CI build is ad-hoc signed with a different signature, so after upgrading you may need to re-enable Accessibility and Input Monitoring for MiVibe (removing the old entry first is the most reliable).

</details>

更多说明见 [README](https://github.com/taliove/MiVibe#readme) · More in the [English README](https://github.com/taliove/MiVibe/blob/main/README.en.md) · [更新记录 · Changelog](https://github.com/taliove/MiVibe/blob/main/CHANGELOG.md)
