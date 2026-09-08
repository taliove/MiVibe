# macOS 跨应用直接输入研究

调研日期：2026-09-08。性质：文档研究，未进行真机注入验证。

## 建议结论

第一版采用非沙盒原生菜单栏应用，通过辅助功能定位当前输入目标；松手取得最终转写后，校验焦点仍有效，再执行一次文本输入。常见应用使用受控剪贴板粘贴；对经过实测、支持写入选区的控件可用 Accessibility selected-text 插入，避免剪贴板副作用。不要以整段 AXValue 替换输入框全文。此处是工程建议，尚非兼容性实测结论。

用户已决定“直接输入”，因此正常路径不增加预览确认；焦点变化、目标不明、权限缺失等异常保存本次结果供用户恢复，不自动猜测目标或重发。语音结束只插入文本，不附加 Return；Codex 的发送是另一个用户触发动作。

## 已核实的平台事实

- AX 提供当前焦点窗口/元素、选中文字及字符范围等属性；但获取某个属性不代表可写，须调用 `AXUIElementIsAttributeSettable`。目标应用可能不实现完整 AX，调用也可能超时或元素失效。[Apple AX 属性](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes?changes=_8&language=objc)、[Apple AX API](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions?preferredLanguage=occ)、[AX 失败类型](https://developer.apple.com/documentation/applicationservices/1462057-axuielementpostkeyboardevent?changes=_8)
- `AXIsProcessTrustedWithOptions` 用于判断辅助功能授权；请求提示是异步的，不能弹出提示后即假定授权完成。Quartz 提供独立的事件投递权限预检函数。[授权检测](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions?preferredLanguage=occ)、[CGPreflightPostEventAccess](https://developer.apple.com/documentation/coregraphics/cgpreflightposteventaccess%28%29)
- Unicode 键盘事件不是万能文本注入：Apple 明确指出应用框架可能忽略其中 Unicode 字符串，而按键码和事件状态自行转换。因此不建议把逐字 CGEvent 作为唯一通用输入路径。[Apple Unicode 事件说明](https://developer.apple.com/documentation/coregraphics/cgevent/keyboardsetunicodestring%28stringlength%3Aunicodestring%3A%29)
- NSPasteboard 是进程间共享资源，可以含多项、多种数据表示；通用剪贴板还参与 Universal Clipboard。`changeCount` 可用于判断自上次写入后是否仍拥有剪贴板，不能证明目标已消费粘贴内容。[NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard?changes=_8)、[changeCount](https://developer.apple.com/documentation/appkit/nspasteboard/changecount?changes=_9__5)
- `.nonactivatingPanel` 不激活所属应用，可用于录音状态浮层，减少自身抢焦点。[Apple NSPanel 样式](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel?changes=_9)
- 安全文本控件隐藏内容并禁止剪切/复制其值。这不等同于证明所有密码框都禁止粘贴，但足以说明普通输入框假设不能直接套用；建议第一版排除识别为受保护的输入目标，不尝试绕过。[Apple NSSecureTextFieldCell](https://developer.apple.com/documentation/appkit/nssecuretextfieldcell?language=objc)
- Apple 当前 App Sandbox 文档将辅助应用使用 Accessibility API 列为不兼容功能。建议自用阶段非沙盒构建，外部分发走 Developer ID 签名、公证与 Hardened Runtime；不把 Mac App Store 作为初版分发前提。公证不等于 App Review。[Sandbox 限制](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)、[Developer ID](https://developer.apple.com/developer-id/)、[公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution?changes=_5)

## 建议的输入事务（设计推论）

1. 按下语音键时记录前台进程、焦点窗口/元素及选区标识；不读取整个输入框正文作为常规行为。
2. 状态浮层不夺取键盘焦点；等待豆包最终结果，流式中间结果只用于状态显示。
3. 写入前重新校验目标。进程、窗口或输入框改变、元素失效或焦点不可确认时，暂存文本并提示恢复；不激活旧窗口强行写回。选区改变也应中止，避免覆盖用户刚修改的文本。
4. 经验证支持 AX selected-text 的适配器可定点插入；否则仅在已经验证的可编辑目标使用剪贴板+粘贴。不要先写 AX 后在结果不确定时自动再粘贴，防止重复。
5. 剪贴板事务必须串行。快照所有可实际读取的项及类型，写入文本并保存 changeCount；若第三方已改动剪贴板，停止恢复旧内容。惰性提供的数据未必可完整恢复；需实测和明确降级，不能宣称无损。
6. 全局粘贴前即使再次检查焦点，检查与键盘事件之间仍有竞争窗口；尽量缩短间隔、使用目标应用定向事件与应用适配器，但不声称绝对避免错误目标。没有通用“粘贴完成”确认时，固定延时恢复只是启发式；不盲目重试。
7. 通用输入不得附带提交键，也不得把语音识别出的“发送”解释为提交命令。对于终端，多行粘贴本身也可能产生执行效果，必须单独验证其 bracketed paste 行为；在支持前不归入兼容承诺。

## 权限与验收边界

文本输入路径需要辅助功能/事件投递权限验证；不因此自动要求屏幕录制、Apple Events 自动化或全局键盘监听。蓝牙与 HID 接收所需权限由硬件研究单独确定。

首轮验收覆盖 TextEdit、浏览器 textarea/contenteditable、Codex、VS Code 编辑区与内置终端，以及中文/英文/emoji、长文本、选区替换。异常覆盖：录音中切应用、最终结果到达前切输入框、目标关闭、锁屏、AX 授权撤销、同时复制内容、富文本剪贴板、网络延迟/重复最终包、安全输入框。Codex 和终端未实测前只能称“目标支持”，不能称已兼容。

后续待决定：剪贴板是否短暂保留识别文本或尝试恢复；不可靠目标如何显示待恢复文本；最低 macOS 版本及测试机器。这些属于产品/原型决策，不由研究替用户决定。
