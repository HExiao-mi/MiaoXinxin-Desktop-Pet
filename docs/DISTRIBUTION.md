# 双平台发行与安全检查

## 自动产物

推送形如 `v0.8.0` 的标签后，`.github/workflows/release.yml` 会生成：

- `MiaoXinxin-macOS-universal.dmg`：包含 Intel/Apple Silicon 通用 App 和 Applications 快捷入口。
- `MiaoXinxin-macOS-universal.zip`：用于手动更新或调试。
- `MiaoXinxin-Windows-win-x64.zip`：.NET 8 自包含便携版。
- `MiaoXinxin-Windows-x64-Setup.exe`：当前用户 Inno Setup 安装器，可正常卸载。

客户端检查 GitHub 最新 Release 的 `tag_name`，仅在版本更高时提示打开 `html_url`。下载、安装和系统权限始终由用户确认。

## macOS 签名与 notarization

`Tools/package_macos.sh` 在存在 `MACOS_SIGNING_IDENTITY` 时启用 hardened runtime 签名；否则自动进行完整的 ad-hoc 签名，因此没有开发者证书的源码构建也可以在本机启动。正式公开发行仍应在受保护的 CI 环境配置 Developer ID Application 证书，完成 `notarytool submit --wait`，然后 `stapler staple` DMG。证书、Apple ID/app-specific password 或 App Store Connect API key 不得写入仓库。

Apple Silicon Mac 可用下面的快速命令生成本机 ZIP 和 DMG；默认不设置 `MACOS_ARCHS` 时仍构建 Intel/Apple Silicon 通用包：

```bash
MACOS_ARCHS=arm64 ONLY_ACTIVE_ARCH=YES bash Tools/package_macos.sh dist/local-arm64
```

ZIP 与 DMG 内的应用统一命名为 `MiaoXinxin.app`。构建脚本会在打包前执行 `codesign --verify --deep --strict`，避免生成无法启动的本地包。

## Windows 签名

`installer.iss` 使用稳定 `AppId`，安装到当前用户目录，不要求管理员权限。正式发行应在 Inno Setup 编译后使用组织持有的 Authenticode 证书和时间戳服务签名 `MiaoXinxin.exe` 与 Setup EXE。PFX、密码和硬件令牌配置不得写入仓库。

## 发布清单

1. `python3 -m unittest discover -s Tools/tests -v`
2. `python3 Tools/petpack.py validate DockCatApp/DockCat/Resources/DefaultCat --strict`
3. macOS `xcodebuild ... test` 和 Windows `dotnet build -c Release` 均通过。
4. 用 contact sheet/动态预览复查耳朵、四肢、项链、步态接触相位和循环连续性。
5. 在实际多显示器、不同 DPI、全屏、睡眠/唤醒和电池模式下冒烟测试。
6. 更新版本号与变更说明，创建带注释的 `v*` 标签；确认 Release 中每个产物的摘要和签名。
