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
| 可视化制作 | `Tools/pet_studio.py` | 本地导入引用、预览动画、调节个性/FPS、校验和隐私安全导出 |
| 发布 | `.github/workflows/release.yml` | 标签触发 macOS DMG/ZIP、Windows ZIP/安装器与 GitHub Release |

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
  "schema_version": 2,
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
  "personality": {
    "playfulness": 0.7,
    "sociability": 0.6,
    "calmness": 0.7,
    "appetite": 0.6,
    "sleepiness": 0.6,
    "curiosity": 0.8
  },
  "toys": [
    {"id": "ball", "kind": "ball", "enabled": true},
    {"id": "food", "kind": "food", "enabled": true}
  ],
  "extensions": [],
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
- 六个 `personality` 数值均为 0–1；客户端把它们与实时精力/饱腹/水分/心情和时间共同用于随机动作加权，不用于给品种贴固定标签。
- `toys[].kind` 支持 `ball / laser / wand / box / food / water`。扩展包必须使用资源包内相对路径，包含绝对路径或 `..` 会被校验器拒绝。
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

`PetBehaviorCatalog`（Swift）与 `BehaviorCatalog`（C#）使用相同映射；manifest 可以对每只宠物单独调速和调低/关闭随机权重。玩具是独立透明桌面窗口：小球→玩球、逗宠棒→仰躺挥爪、纸箱→趴睡、饭碗→吃饭、水碗→喝水；激光点跟随鼠标并做限频反应，在互动停止 220 ms 后恢复用户锁定的状态。

## 5. 运行时状态

### macOS

`CatStateMachine` 管理 `transitioning / walking / resting / dragged / dialogue / outing`。可玩的动作是 resting 内部的子活动；右键锁定动作会写入 `AppSettings.petBehaviorMode`。提醒、拖动或外出结束时会回到锁定状态；只有选择 `random` 才恢复自主切换。

`SpriteAnimator` 只负责逐帧推进。水平移动使用独立 30 Hz timer，因此动画 FPS 与位移速度可以分别调整。`PetBehaviorCatalog` 从 manifest 解析动作节奏；随机选择使用资源权重、个性、生命状态和昼夜时段的组合权重。

`PetLifeState` 本地保存精力、饱腹、水分、心情、亲密、好奇、互动次数、睡眠/进食统计和最爱玩具。它是温和模拟：数值下限为 5，低数值只提高休息、进食或喝水概率，不会死亡、生病或消失。睡眠恢复精力，摸摸提高心情和亲密，玩具偏好由实际交互次数形成。

`DesktopEnvironmentMonitor` 侦测低电量模式和前台全屏窗口。安静模式/全屏隐藏会同时隐藏宠物及玩具；恢复时回到原位置。减少动态会降低帧率，节能模式在低电量时限制动画 FPS。登录启动使用 macOS 13+ 的 `SMAppService.mainApp`，旧系统安全忽略该选项。

### Windows

`MainWindow` 是透明、无边框、置顶 WPF 窗口。`DispatcherTimer` 分别推进动画帧、30 Hz 水平位移、随机行为、睡眠结束、生命状态和鼠标跟随。`DesktopEnvironment` 按当前显示器工作区约束移动，并用 DPI 比例换算桌面坐标；还负责前台全屏检测、电池检测和当前用户 Run 注册表登录启动。右键菜单根据当前包的实际目录动态生成；选择和窗口位置会持久化到 `%LOCALAPPDATA%/MiaoXinxin/settings.json`。

Windows 程序可接受资源包路径作为第一个启动参数；不传时使用构建时从 `DockCatApp/.../DefaultCat` 链接复制的默认包。

## 6. 从照片和视频完成一只宠物

用户侧最短流程只有一步：把同一只宠物的清晰照片和视频附在对话里，并说“做成桌宠”。仓库里的 `AGENTS.md` 要求编码代理自动完成后续步骤。

不熟悉命令行的用户可启动跨平台本地工作室：

```bash
python3 Tools/pet_studio.py
```

工作室可添加照片/视频引用、创建资源包、复制对话制作指令、预览当前动画、调整 FPS/循环/自主权重和个性、运行严格校验并导出 ZIP。引用媒体本身不复制；`.petpack-local.json` 只存本机绝对路径并在导出时强制排除。

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

### 多轮成长和扩展包

生命状态随设置备份保存，替换资源包不会抹掉陪伴统计。manifest v2 的 `extensions` 是向前兼容声明；当前客户端会安全忽略未知扩展，严格校验会拒绝越出资源包根目录的路径。后续动作包、节日装扮或语音包可以沿此入口增加，而无需修改基础姿态协议。

## 7. 安装、更新与发布

- macOS：`Tools/package_macos.sh` 构建 Intel + Apple Silicon 通用 App，同时生成拖拽安装 DMG 和 ZIP。
- Windows：`WindowsPet/Package.ps1` 生成 .NET 8 自包含单文件目录/ZIP；`WindowsPet/installer.iss` 生成当前用户安装器、卸载项和可选快捷方式/启动项。
- 推送 `v*` 标签会触发 `.github/workflows/release.yml`，两平台产物汇总后由 GitHub CLI 创建 Release。
- 两个客户端最多每天查询一次公开的 GitHub “latest release” API。发现更高语义版本后提示并打开项目 Release 页；安装由用户明确确认，不做静默执行或绕过平台安全检查。

签名、Apple notarization 和发布前检查见 [DISTRIBUTION.md](DISTRIBUTION.md)。

## 8. 动画验收

严格校验检查目录、最小帧数、同一动画内 PNG 尺寸一致和 alpha 通道；跨动作画布不同会给出警告。模型/人工视觉 QA 还必须检查：

- 每帧保持同一只宠物、同一花纹和固定配饰。
- 耳朵、前肢、后肢和尾巴数量正确；睡眠帧尤其不能出现三只耳朵或三只前爪。
- 散步存在真正的换脚和接触相位；着地脚不能随身体在地面滑行。
- 玩具和翻滚动作有过渡帧，速度与路径连续；循环首尾不跳。
- 三种睡姿的轮廓确实不同，呼吸只造成小幅变化。
- 画布、主体缩放和基线稳定，不出现突然放大、缩小或上下跳。

## 9. 上游继承与本项目更新

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
- 温和生命状态、个性化随机权重、互动偏好和自然昼夜作息。
- 可拖动桌面玩具、食物/水、安静/全屏/节能/减少动态和登录启动。
- 本地宠物工作室、扩展包协议、双平台安装包、发布流水线和更新检查。

更细的文件级对照见 [CHANGELOG_FROM_UPSTREAM.md](CHANGELOG_FROM_UPSTREAM.md)。

## 10. 参考资料

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
13. Apple, `SMAppService.mainApp` 与 `register()`，主应用登录启动及用户授权模型：<https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp>、<https://developer.apple.com/documentation/servicemanagement/smappservice/register()>
14. Microsoft, “Developing a Per-Monitor DPI-Aware WPF Application”，WPF 跨显示器 DPI、窗口尺寸和位图处理依据：<https://learn.microsoft.com/en-us/windows/win32/hidpi/declaring-managed-apps-dpi-aware>
15. GitHub, “REST API endpoints for releases”，公开 latest release、标签和下载页字段：<https://docs.github.com/en/rest/releases/releases>
16. Python, `tkinter` 标准库文档，macOS/Windows 本地宠物工作室 UI：<https://docs.python.org/3/library/tkinter.html>
17. Inno Setup, `[Files]`、`PrivilegesRequired` 与命令行文档，Windows 当前用户安装器：<https://jrsoftware.org/ishelp/topic_filessection.htm>、<https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm>

## 11. 已知边界

- 照片/视频到透明动画帧需要当前对话环境具备图像生成或图像编辑能力；仓库本身不内置云端模型和密钥。
- 自动校验能发现结构、帧数、尺寸和 alpha 问题，但身份漂移、三只耳朵、错误步态仍需要 contact sheet 和动态预览的视觉 QA。
- Windows 项目由 `windows-latest` CI 做最终编译/安装包验证；本地 macOS 无 .NET SDK 时不能直接运行 WPF。
- 未配置开发者证书的 fork 会生成未签名产物。公开分发应配置签名/notarization；应用不会自动执行未验证下载。
