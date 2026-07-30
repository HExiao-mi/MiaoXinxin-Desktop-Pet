# 相对 DockCat v0.7.0 的改动清单

上游基线：<https://github.com/Auwuua/DockCat>，README 标示版本 v0.7.0。本仓库最初导入时记录的上游提交短哈希为 `9dd4c4b`。由于当前仓库从未保留上游 Git 历史，本文件按功能和文件归属进行可审计标注，而不伪造逐行 ancestry。

| 范围 | 上游能力 | 本项目新增/修改 | 主要文件 |
| --- | --- | --- | --- |
| 角色 | 默认 DockCat 猫 | 替换为喵心心个体身份、矮脚比例和蓝色珠链 | `DockCatApp/DockCat/Resources/DefaultCat/`（本地 `Art/` 中间稿不随 Git 发布） |
| 行为 | 休息、散步、过渡、抱起、对话、出门 | 玩具、梳理、翻滚、三种睡姿、吃饭、喝水、摸摸、鼠标转头 | `DockCatApplication.swift`、资源包 `animations/` |
| 状态控制 | 随机长状态 | 右键动作锁定、持久化选择、互动后恢复、随机动作权重 | `AppSettings.swift`、`CatMenuController.swift`、`DockMenuController.swift` |
| 动画连续性 | 基础帧循环 | 8 帧交替步态、稳定源画布、位移/帧率分离、慢速过渡 | `SpriteAnimator.swift`、`PoseRenderer.swift`、`DockCatApplication.swift` |
| 资源协议 | 猫资源包和 walk 元数据 | manifest v2 的物种、品种、身份、动作 FPS/循环/权重 | `AssetManifest.swift`、`PetBehaviorCatalog.swift` |
| 多物种 | 自定义图片可不限猫，但无物种语义 | 猫/狗/兔/雪貂/其他的步态、理毛、放松和专属动作映射 | `PetBehaviorCatalog.swift`、`Tools/petpack.py` |
| 跨平台 | macOS | 新增 Windows 10/11 WPF 客户端，共享同一资源包 | `WindowsPet/` |
| 制作流程 | 手工参考提示词和文件夹 | 对话附件契约、资源包脚手架、严格自动校验、隐私边界 | `AGENTS.md`、`Tools/petpack.py`、`docs/IMPLEMENTATION.md` |
| 陪伴模拟 | 无生命数值/个性 | 温和生命状态、性格加权、最爱玩具、昼夜作息和本地成长记录 | `AppSettings.swift`、`PetSettings.cs`、两个 `BehaviorCatalog` |
| 桌面交互 | 拖动宠物 | 小球、激光点、逗宠棒、纸箱、饭碗和水碗独立透明窗口 | `DesktopToyController.swift`、`DesktopToyWindow.cs` |
| 系统适配 | macOS Dock 变化 | 双平台多显示器、DPI、全屏隐藏、睡眠/唤醒、节能、减少动态和登录启动 | `Core/System/`、`DesktopEnvironment.cs` |
| 制作工具 | 无 GUI | Tkinter 宠物工作室：引用、预览、参数编辑、校验、隐私安全导出 | `Tools/pet_studio.py` |
| 发行更新 | 上游手工 ZIP | macOS DMG/通用 ZIP、Windows 自包含 ZIP/Setup、标签 Release 和版本检查 | `.github/workflows/release.yml`、`docs/DISTRIBUTION.md` |

所有上游文件继续受仓库根目录 `LICENSE.txt` 的 PolyForm Noncommercial 条款约束。本项目新增代码随整体派生作品按同一非商业条款分发，除非权利人另行书面说明。
