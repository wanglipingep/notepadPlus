# NotepadPlus Mac App Store 发布检查表

## 账号和应用标识

- [ ] Apple Developer Program 会员有效
- [ ] Xcode 已登录开发者账号
- [ ] 确认 `com.wanglp.notepadplus` 尚未被当前团队占用；如需修改，必须在首次上传前同步修改工程和 App Store Connect
- [ ] 在 Xcode 的 `NotepadPlus → Signing & Capabilities` 中选择正确 Team
- [ ] 确认 Release 使用 Automatically manage signing
- [ ] 在 App Store Connect 创建 macOS 应用记录，主要语言选择简体中文
- [ ] 接受 App Store Connect 最新协议

## 工程配置

- [x] 应用显示名称为 NotepadPlus
- [x] 当前构建版本号为 2.7，构建号为 18
- [x] App Sandbox 已启用
- [x] User Selected Files 为 Read/Write
- [x] 安全作用域书签支持跨启动恢复文件授权
- [x] 隐私清单声明 UserDefaults 的 CA92.1 用途
- [x] 无广告、统计 SDK 和网络权限
- [x] 非豁免加密声明为否
- [x] App Icon 为 1024 × 1024 且无透明通道

## 上架资料

- [ ] 将 `PRIVACY_POLICY_ZH.md` 发布为公开 HTTPS 页面
- [ ] 将 `SUPPORT_ZH.md` 发布为公开 HTTPS 页面
- [ ] 把正式 URL 填入 App Store Connect
- [ ] 填写 `APP_STORE_METADATA_ZH.md` 中的名称、描述、关键词和更新说明
- [ ] App Privacy 选择“不收集数据”，前提是最终代码的数据行为未发生变化
- [ ] 完成年龄分级问卷
- [ ] 选择价格和销售区域

## 截图

- [ ] 准备 1 至 10 张 Mac 截图
- [ ] 使用 16:10 尺寸：1280×800、1440×900、2560×1600 或 2880×1800
- [ ] 截图不包含透明通道、个人文件路径或敏感内容
- [ ] 至少展示多标签、Markdown 预览、列模式、正则查找替换和快捷键管理

## 发布前测试

- [ ] 全新安装后可以启动
- [ ] 新建、打开、保存、另存为和重命名正常
- [ ] 重启应用后，最近文件和工作区仍可访问
- [ ] 自动保存和未保存关闭提示正常
- [ ] Markdown 大文件预览不卡顿
- [ ] 列选择的输入、复制、粘贴和删除正常
- [ ] 中文菜单、工具栏提示、弹窗和设置无遗漏
- [ ] Release 构建无编译错误

## 归档与上传

- [ ] Scheme 选择 NotepadPlus
- [ ] 运行目标选择 My Mac (Mac Catalyst)
- [ ] 执行 Product → Archive
- [ ] 在 Organizer 中执行 Validate App
- [ ] 选择 Distribute App → TestFlight & App Store
- [ ] 先通过 TestFlight 完成安装和文件权限验证
- [ ] 选择正确构建并填写 `APP_REVIEW_NOTES_ZH.md`
- [ ] Add for Review → Submit for Review
