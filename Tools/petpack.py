#!/usr/bin/env python3
"""Scaffold and validate one cross-platform MiaoXinxin pet asset pack."""

from __future__ import annotations

import argparse
import hashlib
import json
import queue
import re
import struct
import sys
import threading
from pathlib import Path
from typing import Any


IMAGE_EXTENSIONS = {".png", ".webp", ".jpg", ".jpeg", ".heic"}
VIDEO_EXTENSIONS = {".mp4", ".mov", ".m4v", ".avi", ".webm"}
COMMON_BEHAVIORS: dict[str, dict[str, Any]] = {
    "play_toy": {"fps": 2.2, "playback_loops": 2, "autonomous_weight": 1.0, "minimum_frames": 6},
    "grooming": {"fps": 2.5, "playback_loops": 2, "autonomous_weight": 0.8, "minimum_frames": 4},
    "belly_roll": {"fps": 1.9, "playback_loops": 1, "autonomous_weight": 0.65, "minimum_frames": 6},
    "sleep_curled": {"fps": 1.4, "sleep": True, "autonomous_weight": 0.7, "minimum_frames": 4},
    "sleep_side": {"fps": 1.4, "sleep": True, "autonomous_weight": 0.7, "minimum_frames": 4},
    "sleep_loaf": {"fps": 1.4, "sleep": True, "autonomous_weight": 0.7, "minimum_frames": 4},
    "eating": {"fps": 2.0, "playback_loops": 2, "autonomous_weight": 0.65, "minimum_frames": 4},
    "drinking": {"fps": 2.0, "playback_loops": 2, "autonomous_weight": 0.65, "minimum_frames": 4},
    "pet_response": {"fps": 2.2, "playback_loops": 1, "autonomous_weight": 0.0, "minimum_frames": 4},
    "look": {"fps": 2.0, "playback_loops": 1, "autonomous_weight": 0.0, "minimum_frames": 4},
}
SPECIES: dict[str, dict[str, Any]] = {
    "cat": {
        "signature": "pounce",
        "signature_label": "压低身体、瞄准后轻扑",
        "gait": "四足交替步态；前后脚接触与摆动清楚，脚掌着地阶段不能滑动",
        "grooming": "舔前爪、洗脸或舔身体侧面",
        "roll": "翻肚皮并缓慢回正",
    },
    "dog": {
        "signature": "tail_wag",
        "signature_label": "尾巴带动臀部自然摇摆，可配合期待抬头",
        "gait": "犬科四足步态；对角肢有明确相位差，脊背和肩胛随步伐轻微起伏",
        "grooming": "舔爪、挠耳或抖毛，避免使用猫式舔脸剪影",
        "roll": "开心打滚或响应翻滚指令",
    },
    "rabbit": {
        "signature": "binky",
        "signature_label": "开心蹦跳（binky），短暂腾空并轻微扭身后稳定落地",
        "gait": "兔类跳跃步态；后腿同时发力、前腿先后落地，不能套用猫狗交替步",
        "grooming": "双前爪洗脸、理耳或侧身理毛",
        "roll": "放松侧倒（flop），不是犬类翻滚",
    },
    "ferret": {
        "signature": "war_dance",
        "signature_label": "拱背、侧向跳步、转身组成的开心战舞",
        "gait": "鼬科低重心长身体步态；躯干有柔和波动，四足接触仍保持连续",
        "grooming": "坐姿抓挠或快速梳理身体侧面",
        "roll": "贴地鳄鱼翻滚，身体保持细长柔韧",
    },
    "other": {
        "signature": "signature_move",
        "signature_label": "根据参考视频提取该动物最有辨识度、无伤害性的动作",
        "gait": "根据物种骨骼与参考视频设计接触相位；禁止直接套用猫步",
        "grooming": "根据物种真实的自我清洁方式设计",
        "roll": "根据物种可自然完成的放松动作设计，不强制翻滚",
    },
}
POSE_PATHS = {
    "resting": "poses/resting",
    "held": "poses/held",
    "dialogue": "poses/dialogue",
    "transition": "poses/transition",
}


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9_-]+", "-", value.lower()).strip("-")
    return slug or "my-pet"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def media_kind(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix in IMAGE_EXTENSIONS:
        return "image"
    if suffix in VIDEO_EXTENSIONS:
        return "video"
    raise ValueError(f"不支持的参考文件格式：{path.name}")


def behavior_manifest(species: str) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for name, values in COMMON_BEHAVIORS.items():
        result[name] = {key: value for key, value in values.items() if key != "minimum_frames"}
        result[name]["frames"] = []
    signature = SPECIES[species]["signature"]
    result[signature] = {
        "fps": 2.4,
        "frames": [],
        "playback_loops": 2,
        "autonomous_weight": 0.8,
    }
    return result


def generation_plan(name: str, species: str, breed: str | None, references: list[Path]) -> str:
    profile = SPECIES[species]
    reference_list = "\n".join(f"- `{path.name}`（{media_kind(path)}）" for path in references) or "- 无；请先补充照片或视频"
    return f"""# {name} 跨平台桌宠生成计划

## 身份锁

- 物种：`{species}`
- 品种：`{breed or '由参考媒体判断；不能确定时保持 other/unknown'}`
- 参考文件：
{reference_list}

先从多角度照片和视频中建立同一只宠物的身份特征表：毛色/花纹、脸型、耳朵、眼睛、鼻口、四肢比例、尾巴、项圈或其他固定配饰。每一帧都必须保持这些特征，不得把通用品种外观覆盖到个体身份上。

## 动作语义

- 散步：{profile['gait']}。
- 梳理：{profile['grooming']}。
- 翻滚/放松：{profile['roll']}。
- 物种专属动作 `{profile['signature']}`：{profile['signature_label']}。
- 通用动作：休息、三种合理睡姿、玩玩具、吃饭、喝水、回应抚摸、跟随鼠标转头。

## 帧与连续性

1. 全部输出透明背景 PNG，并使用同一画布、同一缩放、同一脚底基线。
2. `walk` 至少 8 帧，包含接触、下沉、经过、抬升等连续相位；循环首尾相接。
3. 玩具和翻滚至少 6 帧，关键姿势之间必须有过渡帧；玩具在相邻帧中的位置连续。
4. 睡眠每种至少 4 帧，只做细微呼吸/耳尾动作；逐帧检查耳朵、前爪、后爪数量。
5. `look` 固定 4 帧：左、近处、右、上；不得改变花纹或配饰。
6. 资源生成后运行 `python3 Tools/petpack.py validate <资源包路径> --strict`。

## 目录任务

- 静态姿态：`poses/resting`、`poses/held`、`poses/dialogue`、`poses/transition`
- 通用动画：`walk`、`play_toy`、`grooming`、`belly_roll`、三种 `sleep_*`、`eating`、`drinking`、`pet_response`、`look`
- 专属动画：`{profile['signature']}`

macOS 与 Windows 读取同一份资源包，不要制作平台专属帧。
"""


def command_init(args: argparse.Namespace) -> int:
    output = Path(args.output).expanduser().resolve()
    references = [Path(value).expanduser().resolve() for value in args.reference]
    for path in references:
        if not path.is_file():
            raise ValueError(f"参考文件不存在：{path}")
        media_kind(path)
    if output.exists() and any(output.iterdir()) and not args.force:
        raise ValueError(f"输出目录不是空目录：{output}（需要覆盖时加 --force）")
    output.mkdir(parents=True, exist_ok=True)
    species = args.species
    pet_id = slugify(args.id or args.name)
    signature = SPECIES[species]["signature"]
    directories = list(POSE_PATHS.values()) + [
        "animations/walk",
        *(f"animations/{name}" for name in COMMON_BEHAVIORS),
        f"animations/{signature}",
        "app_icons",
        "qa/previews",
    ]
    for directory in directories:
        (output / directory).mkdir(parents=True, exist_ok=True)

    manifest = {
        "id": pet_id,
        "name": args.name,
        "author": args.author,
        "profile": {
            "species": species,
            "breed": args.breed,
            "body_traits": args.body_trait,
            "identity_features": args.identity_feature,
            "motion_notes": [SPECIES[species]["gait"]],
        },
        "canvas_width": args.canvas_size,
        "canvas_height": args.canvas_size,
        "default_anchor": {"x": 0.5, "y": 0.88},
        "poses": POSE_PATHS,
        "animations": {
            "walk": {"fps": args.walk_fps, "frames": []},
            "behaviors": behavior_manifest(species),
        },
        "app_icons": {"sleep": "app_icons/icon_sleep.png", "empty": "app_icons/icon_empty.png"},
    }
    intake = {
        "schema_version": 1,
        "pet_id": pet_id,
        "name": args.name,
        "species": species,
        "references": [
            {"filename": path.name, "kind": media_kind(path), "sha256": sha256(path)} for path in references
        ],
    }
    local = {"references": [str(path) for path in references]}
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "pet_request.json").write_text(json.dumps(intake, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / ".petpack-local.json").write_text(json.dumps(local, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "generation-plan.md").write_text(
        generation_plan(args.name, species, args.breed, references), encoding="utf-8"
    )
    print(output)
    return 0


def image_files(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(
        (path for path in directory.iterdir() if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS),
        key=lambda path: path.name.lower(),
    )


def png_info(path: Path) -> tuple[int, int, bool] | None:
    if path.suffix.lower() != ".png":
        return None
    result: queue.Queue[bytes | None] = queue.Queue(maxsize=1)

    def read_header() -> None:
        try:
            # Some macOS file-provider assets can block in read(2). Keep structural
            # validation bounded so one unavailable source image cannot hang CI.
            with path.open("rb", buffering=0) as stream:
                result.put(stream.read(26), block=False)
        except (OSError, queue.Full):
            try:
                result.put(None, block=False)
            except queue.Full:
                pass

    threading.Thread(target=read_header, daemon=True).start()
    try:
        header = result.get(timeout=1.0)
    except queue.Empty:
        return None
    if header is None:
        return None
    if len(header) < 26 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    width, height = struct.unpack(">II", header[16:24])
    color_type = header[25]
    return width, height, color_type in {4, 6}


def command_validate(args: argparse.Namespace) -> int:
    root = Path(args.pack).expanduser().resolve()
    errors: list[str] = []
    warnings: list[str] = []
    try:
        manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR manifest.json 无法读取：{exc}")
        return 1
    species = manifest.get("profile", {}).get("species", "cat")
    if species not in SPECIES:
        errors.append(f"profile.species 不支持：{species}")
        species = "other"
    required: dict[str, int] = {"walk": 6}
    required.update({name: int(values["minimum_frames"]) for name, values in COMMON_BEHAVIORS.items()})
    signature = SPECIES[species]["signature"]
    declared_behaviors = manifest.get("animations", {}).get("behaviors", {})
    if signature in declared_behaviors:
        required[signature] = 6

    for pose, relative in POSE_PATHS.items():
        count = len(image_files(root / manifest.get("poses", {}).get(pose, relative)))
        if count == 0:
            errors.append(f"{relative} 缺少图片")

    pack_sizes: set[tuple[int, int]] = set()
    for animation, minimum in required.items():
        files = image_files(root / "animations" / animation)
        if not files:
            errors.append(f"animations/{animation} 缺少动画帧")
            continue
        if args.strict and len(files) < minimum:
            errors.append(f"animations/{animation} 只有 {len(files)} 帧，至少需要 {minimum} 帧")
        expected_size: tuple[int, int] | None = None
        for file in files:
            info = png_info(file)
            if info is None:
                warnings.append(f"{file.relative_to(root)} 不是可检查的 PNG")
                continue
            width, height, has_alpha = info
            if expected_size is None:
                expected_size = (width, height)
            elif (width, height) != expected_size:
                errors.append(f"{file.relative_to(root)} 尺寸 {width}x{height} 与 {expected_size[0]}x{expected_size[1]} 不一致")
            if not has_alpha:
                errors.append(f"{file.relative_to(root)} 没有 alpha 通道")
        if expected_size is not None:
            pack_sizes.add(expected_size)

    if len(pack_sizes) > 1:
        warnings.append("不同动作使用了不同 PNG 画布；客户端会按 manifest 画布归一化，但新资源包建议统一尺寸")

    for warning in warnings:
        print(f"WARN  {warning}")
    for error in errors:
        print(f"ERROR {error}")
    print(f"checked={root} errors={len(errors)} warnings={len(warnings)}")
    return 1 if errors else 0


def command_prompt(args: argparse.Namespace) -> int:
    files = "、".join(Path(value).name for value in args.reference) or "我随后附上的照片/视频"
    print(
        f"请使用本仓库的跨平台宠物工作流，把 {files} 中的同一只宠物制作成 macOS 和 Windows 通用桌宠资源包。"
        "请从媒体判断物种、品种、体型、花纹和固定配饰；保持身份一致，并生成散步、休息、三种合理睡姿、玩玩具、"
        "梳理、放松/翻滚、吃饭、喝水、摸摸回应、跟随鼠标转头和物种专属动作。不要向我索要已经能从媒体判断的信息。"
        "完成后运行严格校验，给出资源包路径和 QA 结果。"
    )
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    commands = root.add_subparsers(dest="command", required=True)
    init = commands.add_parser("init", help="从宠物资料初始化资源包和生成计划")
    init.add_argument("--name", required=True)
    init.add_argument("--id")
    init.add_argument("--species", choices=sorted(SPECIES), required=True)
    init.add_argument("--breed")
    init.add_argument("--author", default="Pet owner")
    init.add_argument("--reference", action="append", default=[])
    init.add_argument("--body-trait", action="append", default=[])
    init.add_argument("--identity-feature", action="append", default=[])
    init.add_argument("--canvas-size", type=int, default=1024)
    init.add_argument("--walk-fps", type=float, default=4)
    init.add_argument("--output", required=True)
    init.add_argument("--force", action="store_true")
    init.set_defaults(handler=command_init)
    validate = commands.add_parser("validate", help="校验跨平台资源包")
    validate.add_argument("pack")
    validate.add_argument("--strict", action="store_true")
    validate.set_defaults(handler=command_validate)
    prompt = commands.add_parser("prompt", help="生成可直接放进对话框的请求")
    prompt.add_argument("--reference", action="append", default=[])
    prompt.set_defaults(handler=command_prompt)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return int(args.handler(args))
    except ValueError as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
