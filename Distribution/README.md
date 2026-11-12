# Universal DMG 打包

在项目根目录构建同时支持 Apple 芯片与 Intel 的 Release：

```sh
xcodebuild -project NotepadPlus.xcodeproj -scheme NotepadPlus \
  -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /tmp/notepadplus-release \
  CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO SWIFT_USE_INTEGRATED_DRIVER=NO build

bash Distribution/package-dmg.sh \
  /tmp/notepadplus-release/Build/Products/Release-maccatalyst/NotepadPlus.app
```

脚本读取应用中的版本号，校验正式 Bundle ID 和两个架构，在副本中保留有效签名或执行本地签名，再生成 `dist/NotepadPlus-版本号-universal.dmg` 及 SHA-256 文件。

DMG 使用标准 DiskImages 流程创建 HFS+ 文件系统和 UDZO 压缩，避免 `makehybrid` 附加的 Finder 元数据破坏应用签名。生成后自动只读挂载，严格核验包内签名、双架构、版本、`/Applications` 入口和日志，成功后卸载并输出安装包。镜像包含应用、指向 `/Applications` 的快捷入口、安装说明和版本日志。双击 DMG 后将应用拖入“应用程序”即可安装。

当前安装包采用本地签名，未进行 Apple Developer ID 公证；首次打开方式见 `首次打开说明.txt`。指定相同版本号时，脚本会替换对应的 DMG 与校验文件。
