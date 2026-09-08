# 遥控器音频与按键如何独立接入

Type: research
Label: wayfinder:research
Status: resolved
Assignee: remote
Parent: ../map.md
Blocked by: none

## Question

如何独立实现小米遥控器 2 Pro 的 BLE 语音及 HID 按键接入？参考 mi-ao 源码与协议一手资料，区分仓库声明、协议事实和待真机验证事项。核实音频编码、配对、权限、共存、断连；不得复制实现。

## Answer

独立接入路线可行：CoreBluetooth + ATVV v1.0 接收音频、独立 ADPCM 解码为 PCM，HID 单独接入。参考项目的固件 2671 真机结果不替代用户设备验收；按键控制器源码抓取失败，HID 权限和拦截策略仍需真机验证。应新增协议探测任务，特别检查 AUDIO_STOP 尾音、断连恢复、原生按键重复和输入监听权限。详见 [遥控器接入研究](../research/remote.md)。
