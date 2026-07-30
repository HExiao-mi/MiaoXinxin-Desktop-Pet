# 跨平台、多物种桌宠实现说明

本文是项目的实现依据和维护入口。它说明哪些能力继承自 DockCat，哪些是喵心心版本新增，以及如何仅凭用户在对话中附上的照片和视频制作猫、狗、兔子、雪貂或其他宠物。

## 1. 交付范围

项目现在包含两个原生客户端和一套共享资源协议：

| 层 | 目录 | 作用 |
| --- | --- | --- |
| macOS | `DockCatApp/` | Swift + AppKit；透明浮动面板、程序坞/桌面移动、提醒、出门、收藏品、设置 |
| Windows | `WindowsPet/` | C# + .NET 8 WPF；透明置顶窗口、拖动、随机/锁定动作、散步、摸摸和鼠标跟随 |
| 共享宠物包 | `manifest.json` + `poses/` + `animations/` | 两个平台读取完全相同的 PNG 帧和动作节奏 |
| 对话式制作 | `AGENTS.md`、`Tools/petpack.py` | 从附件建立身份描述、动作计划、目录和严格校验 |

macOS 12+ 使用 AppKit；Windows 客户端目标框架为 `net8.0-windows`，建议 Windows 10/11。

## 2. 数据流

```text
对话附件（照片/视频）
  -> 身份锁（物种、品种、体型、花纹、配饰）
  -> petpack.py init
  -> manifest + generation-plan
  -> 按物种生成/整理透明 PNG 动画帧
  -> contact sheet + GIF/视频预览
  -> petpack.py validate --strict
  -> 同一资源包分别由 macOS / Windows 加载
```

原始媒体只用于生成期间的本地参考。`pet_request.json` 仅保存文件名和 SHA-256，绝对路径放入被 Git 忽略的 `.petpack-local.json`；项目不会自动上传相册或素材。

## 3. 资源包协议

最小 manifest：

```json
{
  "id": "my-pet",
  "name": "My Pet",
  "author": "Pet owner",
  "profile": {
    "species": "rabbit",
    "breed": null,
    "body_traits": ["compact_body", "upright_ears"],
    "identity_features": ["white_nose", "brown_left_ear"],
    "motion_notes": ["hind_limbs_drive_hop"]
  },
  "canvas_width": 1024,
  "canvas_height": 1024,
  "default_anchor": {"x": 0.5, "y": 0.88},
  "poses": {
    "resting": "poses/resting",
    "held": "poses/held",
    "dialogue": "poses/dialogue",
    "transition": "poses/transition"
  },
  "animations": {
    "walk": {"fps": 4, "frames": []},
    "behaviors": {
      "binky": {
        "fps": 2.4,
        "frames": [],
        "playback_loops": 2,
        "autonomous_weight": 0.8
      }
    }
  }
}
```

关键规则：

- `profile.species` 首选 `cat`、`dog`、`rabbit`、`ferret`；其他动物使用 `other`。
- `animations.behaviors` 可分别覆盖 `fps`、`playback_loops`、`autonomous_weight` 和 `sleep`，不再把所有速度写死在客户端。
- `frames` 为向后兼容字段；当前客户端按文件名扫描 `animations/<动作>/`。
- 同一动画必须使用统一画布、主体缩放和脚底基线；新资源包也应尽量跨动作统一画布。透明 PNG 是严格交付格式。
- 自定义包缺少某个动作时，菜单不会显示该动作；这样不会让小狗、兔子或雪貂突然播放默认猫动画。

## 4. 动作模型

所有宠物共享这些语义槽位：

- `walk`：移动循环，建议 8 帧以上。
- `play_toy`：适合该物种的玩具互动。
- `grooming`：真实的自我清洁动作。
- `belly_roll`：物种合理的翻滚或放松动作。
- `sleep_curled`、`sleep_side`、`sleep_loaf`：三个睡眠槽位；外观不必强行使用猫的“揣手”形态。
- `eating`、`drinking`：头、口鼻与容器接触连续。
- `pet_response`：用户单击或选择“摸摸”时的配合动作，结束后恢复原锁定状态。
- `look`：左、近处、右、上四个鼠标跟随方向。
- 物种专属槽位：猫 `pounce`、狗 `tail_wag`、兔 `binky`、雪貂 `war_dance`，其他动物 `signature_move`。

### 物种动作差异

| 物种 | 散步/移动 | 梳理 | 放松/翻滚 | 专属动作 |
| --- | --- | --- | --- | --- |
| 猫 | 四足交替步态，明确接触和摆动相位 | 舔爪、洗脸、舔侧身 | 翻肚皮后回正 | 伏低瞄准后轻扑 |
| 狗 | 犬科四足步态，肩胛与脊背随步伐起伏 | 舔爪、挠耳、抖毛 | 开心打滚 | 摇尾并带动臀部 |
| 兔 | 后肢同时推进，前肢先后落地 | 双前爪洗脸、理耳 | 放松侧倒（flop） | 开心蹦跳（binky） |
| 雪貂 | 低重心、长躯干柔和波动 | 抓挠或快速理毛 | 贴地鳄鱼翻滚 | 拱背、侧跳、转身战舞 |

`PetBehaviorCatalog`（Swift）与 `BehaviorCatalog`（C#）使用相同映射；manifest 可以对每只宠物单独调速和调低/关闭随机权重。

## 5. 运行时状态

### macOS

`CatStateMachine` 管理 `transitioning / walking / resting / dragged / dialogue / outing`。可玩的动作是 resting 内部的子活动；右键锁定动作会写入 `AppSettings.petBehaviorMode`。提醒、拖动或外出结束时会回到锁定状态；只有选择 `random` 才恢复自主切换。

`SpriteAnimator` 只负责逐帧推进。水平移动使用独立 30 Hz timer，因此动画 FPS 与位移速度可以分别调整。`PetBehaviorCatalog` 从 manifest 解析动作节奏；随机选择使用 `autonomous_weight` 加权。

### Windows

`MainWindow` 是透明、无边框、置顶 WPF 窗口。`DispatcherTimer` 分别推进动画帧、30 Hz 水平位移、随机行为、睡眠结束和鼠标跟随。右键菜单根据当前包的实际目录动态生成；选择会持久化到 `%LOCALAPPDATA%/MiaoXinxin/settings.json`。

Windows 程序可接受资源包路径作为第一个启动参数；不传时使用构建时从 `DockCatApp/.../DefaultCat` 链接复制的默认包。

## 6. 从照片和视频完成一只宠物

用户侧最短流程只有一步：把同一只宠物的清晰照片和视频附在对话里，并说“做成桌宠”。仓库里的 `AGENTS.md` 要求编码代理自动完成后续步骤。

维护者可手动复现：

```bash
python3 Tools/petpack.py init \
  --name "团子" \
  --species rabbit \
  --reference /absolute/path/front.jpg \
  --reference /absolute/path/walking.mov \
  --output /absolute/path/TuanziPet
```

生成后按照 `generation-plan.md` 准备帧，最后运行：

```bash
python3 Tools/petpack.py validate /absolute/path/TuanziPet --strict
```

`prompt` 子命令可生成一段可直接复制到对话框的请求：

```bash
python3 Tools/petpack.py prompt --reference front.jpg --reference walking.mov
```

## 7. 动画验收

严格校验检查目录、最小帧数、同一动画内 PNG 尺寸一致和 alpha 通道；跨动作画布不同会给出警告。模型/人工视觉 QA 还必须检查：

- 每帧保持同一只宠物、同一花纹和固定配饰。
- 耳朵、前肢、后肢和尾巴数量正确；睡眠帧尤其不能出现三只耳朵或三只前爪。
- 散步存在真正的换脚和接触相位；着地脚不能随身体在地面滑行。
- 玩具和翻滚动作有过渡帧，速度与路径连续；循环首尾不跳。
- 三种睡姿的轮廓确实不同，呼吸只造成小幅变化。
- 画布、主体缩放和基线稳定，不出现突然放大、缩小或上下跳。

## 8. 上游继承与本项目更新

### 继承自 Auwuua/DockCat v0.7.0

- macOS AppKit 工程结构、程序坞边桌宠定位。
- 基础休息/散步/过渡/抱起/对话/出门状态。
- 喝水和活动提醒、设置、出门事件、收藏品与自定义资源包入口。
- PolyForm Noncommercial 许可及上游版权要求。

### 喵心心项目自行更新

- 喵心心身份素材：灰白矮脚体型、金色圆眼、蓝色圆珠/银色隔珠项链。
- 8 帧短腿交替步态；动画画布稳定、位移与帧率分离。
- 玩玩具、理毛、翻肚皮、吃饭、喝水、摸摸回应、鼠标转头。
- 三组独立睡姿和逐帧肢体数量 QA。
- 右键锁定任意状态、持久化选择、随机加权自主活动。
- manifest v2：物种/品种/个体特征、动作速度和随机权重。
- 猫、狗、兔、雪貂和其他动物的专属动作模型。
- Windows WPF 客户端和 macOS/Windows 共享资源包。
- 对话式附件工作流、隐私边界和依赖-free 严格校验器。

更细的文件级对照见 [CHANGELOG_FROM_UPSTREAM.md](CHANGELOG_FROM_UPSTREAM.md)。

## 9. 参考资料

以下资料用于确定系统实现或动作语义，不代表复制其代码或素材：

1. Auwuua, *DockCat* v0.7.0，项目结构、原始功能和许可来源：<https://github.com/Auwuua/DockCat>
2. Apple, `NSPanel`，macOS 辅助/浮动窗口模型：<https://developer.apple.com/documentation/appkit/nspanel>
3. Apple, `Timer`，macOS 定时状态和逐帧调度：<https://developer.apple.com/documentation/foundation/timer>
4. Apple, `NSEvent.mouseLocation`，桌面坐标中的鼠标跟随：<https://developer.apple.com/documentation/appkit/nsevent/mouselocation>
5. Microsoft, `DispatcherTimer`，WPF UI dispatcher 上的动画计时：<https://learn.microsoft.com/en-us/dotnet/api/system.windows.threading.dispatchertimer>
6. Evenson & Eckerlin, “Ferret Behavior”，雪貂四足移动、war dance 与 alligator roll 行为描述：<https://pmc.ncbi.nlm.nih.gov/articles/PMC7158301/>
7. Crawford et al., “Behavioral assessment of well-being in the naïve laboratory ferret”，雪貂 ethogram 中的 war dance、自我梳理和物体探索：<https://pmc.ncbi.nlm.nih.gov/articles/PMC11615330/>
8. Rooney et al., “Ear health and quality of life in pet rabbits...”，将 binky 作为兔子玩耍/积极福利行为指标：<https://pmc.ncbi.nlm.nih.gov/articles/PMC10355490/>
9. Ruis et al., “Evaluation of a Configurable... Floor-Pen System for Group-Housing of Laboratory Rabbits”，兔子后肢推进跳跃与洗脸/理毛 ethogram：<https://pmc.ncbi.nlm.nih.gov/articles/PMC8066506/>
10. Byosiere et al., “Investigating the Function of Play Bows in Dog and Wolf Puppies”，犬类 play bow 的动作与互动语义：<https://pmc.ncbi.nlm.nih.gov/articles/PMC5199004/>
11. Hildebrand, “The Quadrupedal Gaits of Vertebrates,” *BioScience* 39(11), 1989，四足步态接触相位的经典分类，DOI: `10.2307/1311182`。
12. Thomas & Johnston, *The Illusion of Life: Disney Animation*, 1981，动作预备、缓入缓出、弧线和连续性的动画原则。

## 10. 已知边界

- 照片/视频到透明动画帧需要当前对话环境具备图像生成或图像编辑能力；仓库本身不内置云端模型和密钥。
- 自动校验能发现结构、帧数、尺寸和 alpha 问题，但身份漂移、三只耳朵、错误步态仍需要 contact sheet 和动态预览的视觉 QA。
- Windows 项目只能在安装 .NET 8 SDK 的 Windows 机器上完成最终编译/运行验证；macOS 环境只能做源码和协议测试。
