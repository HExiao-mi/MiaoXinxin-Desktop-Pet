#!/usr/bin/env python3
"""Local visual studio for creating, previewing, validating and exporting pet packs."""

from __future__ import annotations

import json
import subprocess
import sys
import zipfile
from pathlib import Path
from typing import Any

from petpack import DEFAULT_PERSONALITY, SPECIES, conversation_prompt, image_files


PRIVATE_EXPORT_NAMES = {".petpack-local.json", ".DS_Store"}


def load_manifest(pack: Path) -> dict[str, Any]:
    return json.loads((pack / "manifest.json").read_text(encoding="utf-8"))


def save_manifest(pack: Path, manifest: dict[str, Any]) -> None:
    destination = pack / "manifest.json"
    temporary = destination.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(destination)


def update_personality(pack: Path, values: dict[str, float]) -> dict[str, Any]:
    manifest = load_manifest(pack)
    personality = manifest.setdefault("personality", {})
    for key, value in values.items():
        if key not in DEFAULT_PERSONALITY["other"]:
            raise ValueError(f"Unknown personality field: {key}")
        personality[key] = round(max(0.0, min(1.0, float(value))), 2)
    save_manifest(pack, manifest)
    return manifest


def update_animation(pack: Path, name: str, fps: float, loops: int, weight: float) -> dict[str, Any]:
    manifest = load_manifest(pack)
    animations = manifest.setdefault("animations", {})
    if name == "walk":
        spec = animations.setdefault("walk", {})
    else:
        spec = animations.setdefault("behaviors", {}).setdefault(name, {})
    spec["fps"] = round(max(0.1, min(30.0, float(fps))), 2)
    if name != "walk":
        spec["playback_loops"] = max(1, min(20, int(loops)))
        spec["autonomous_weight"] = round(max(0.0, min(10.0, float(weight))), 2)
    save_manifest(pack, manifest)
    return manifest


def export_pack(pack: Path, destination: Path) -> Path:
    destination = destination.with_suffix(".zip")
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(pack.rglob("*")):
            if not path.is_file() or path.name in PRIVATE_EXPORT_NAMES or "references" in path.relative_to(pack).parts:
                continue
            archive.write(path, Path(pack.name) / path.relative_to(pack))
    return destination


class PetStudioApp:
    def __init__(self) -> None:
        import tkinter as tk
        from tkinter import filedialog, messagebox, ttk

        self.tk, self.filedialog, self.messagebox, self.ttk = tk, filedialog, messagebox, ttk
        self.root = tk.Tk()
        self.root.title("MiaoXinxin Pet Studio / 宠物工作室")
        self.root.geometry("980x720")
        self.references: list[Path] = []
        self.pack: Path | None = None
        self.preview_frames: list[Path] = []
        self.preview_index = 0
        self.preview_job: str | None = None

        self.name = tk.StringVar(value="我的宠物")
        self.species = tk.StringVar(value="cat")
        self.breed = tk.StringVar()
        self.author = tk.StringVar(value="Pet owner")
        self.output = tk.StringVar(value=str(Path.home() / "Desktop" / "my-pet"))
        self.selected_animation = tk.StringVar(value="walk")
        self.fps = tk.DoubleVar(value=4)
        self.loops = tk.IntVar(value=2)
        self.weight = tk.DoubleVar(value=0.8)
        self.personality = {
            key: tk.DoubleVar(value=value) for key, value in DEFAULT_PERSONALITY["cat"].items()
        }
        self._build()

    def _build(self) -> None:
        tk, ttk = self.tk, self.ttk
        notebook = ttk.Notebook(self.root)
        notebook.pack(fill="both", expand=True, padx=12, pady=12)
        create = ttk.Frame(notebook, padding=14)
        animate = ttk.Frame(notebook, padding=14)
        qa = ttk.Frame(notebook, padding=14)
        notebook.add(create, text="1. 照片/视频与身份")
        notebook.add(animate, text="2. 动作与个性")
        notebook.add(qa, text="3. 校验与导出")

        fields = [("名字", self.name), ("品种（可空）", self.breed), ("作者", self.author), ("输出目录", self.output)]
        for row, (label, variable) in enumerate(fields):
            ttk.Label(create, text=label).grid(row=row, column=0, sticky="e", padx=6, pady=5)
            ttk.Entry(create, textvariable=variable, width=70).grid(row=row, column=1, columnspan=3, sticky="ew", pady=5)
        ttk.Label(create, text="物种").grid(row=4, column=0, sticky="e", padx=6)
        ttk.Combobox(create, textvariable=self.species, values=list(SPECIES), state="readonly").grid(row=4, column=1, sticky="w")
        ttk.Button(create, text="添加照片/视频", command=self._add_references).grid(row=5, column=0, pady=10)
        ttk.Button(create, text="移除所选", command=self._remove_reference).grid(row=5, column=1, sticky="w")
        self.reference_list = tk.Listbox(create, height=13)
        self.reference_list.grid(row=6, column=0, columnspan=4, sticky="nsew")
        ttk.Label(create, text="原始媒体只记录本地路径和哈希，不复制进资源包，也不会被导出。", foreground="#555").grid(row=7, column=0, columnspan=4, sticky="w", pady=8)
        ttk.Button(create, text="创建资源包", command=self._create_pack).grid(row=8, column=0, pady=8)
        ttk.Button(create, text="打开已有资源包", command=self._open_pack).grid(row=8, column=1, sticky="w")
        ttk.Button(create, text="复制对话制作指令", command=self._copy_prompt).grid(row=8, column=2, sticky="w")
        create.columnconfigure(1, weight=1)
        create.rowconfigure(6, weight=1)

        left = ttk.Frame(animate)
        right = ttk.Frame(animate)
        left.pack(side="left", fill="y", padx=(0, 18))
        right.pack(side="left", fill="both", expand=True)
        ttk.Label(left, text="动作").pack(anchor="w")
        self.animation_list = tk.Listbox(left, width=26, height=19, exportselection=False)
        self.animation_list.pack(fill="y", pady=6)
        self.animation_list.bind("<<ListboxSelect>>", self._select_animation)
        ttk.Button(left, text="刷新", command=self._refresh_pack).pack(fill="x")
        self.preview = ttk.Label(right, text="打开资源包后可预览 PNG 动画", anchor="center")
        self.preview.pack(fill="both", expand=True)
        controls = ttk.Frame(right)
        controls.pack(fill="x", pady=8)
        for column, (label, variable) in enumerate((("FPS", self.fps), ("循环", self.loops), ("自主权重", self.weight))):
            ttk.Label(controls, text=label).grid(row=0, column=column * 2)
            ttk.Entry(controls, textvariable=variable, width=7).grid(row=0, column=column * 2 + 1, padx=(3, 12))
        ttk.Button(controls, text="保存动作参数", command=self._save_animation).grid(row=0, column=6)
        personality_box = ttk.LabelFrame(right, text="个性（0–1）", padding=8)
        personality_box.pack(fill="x")
        for row, (key, variable) in enumerate(self.personality.items()):
            ttk.Label(personality_box, text=key).grid(row=row, column=0, sticky="w")
            tk.Scale(personality_box, variable=variable, from_=0, to=1, resolution=.05, orient="horizontal", length=300).grid(row=row, column=1)
        ttk.Button(personality_box, text="保存个性", command=self._save_personality).grid(row=6, column=1, sticky="e")

        actions = ttk.Frame(qa)
        actions.pack(fill="x")
        ttk.Button(actions, text="普通校验", command=lambda: self._validate(False)).pack(side="left")
        ttk.Button(actions, text="严格校验", command=lambda: self._validate(True)).pack(side="left", padx=8)
        ttk.Button(actions, text="导出分享包 (.zip)", command=self._export).pack(side="left")
        self.log = tk.Text(qa, wrap="word", font=("Menlo", 12))
        self.log.pack(fill="both", expand=True, pady=10)

    def _add_references(self) -> None:
        paths = self.filedialog.askopenfilenames(filetypes=[("Pet media", "*.png *.jpg *.jpeg *.heic *.mp4 *.mov *.m4v *.webm"), ("All", "*")])
        for value in paths:
            path = Path(value)
            if path not in self.references:
                self.references.append(path)
                self.reference_list.insert("end", str(path))

    def _remove_reference(self) -> None:
        selected = list(self.reference_list.curselection())
        for index in reversed(selected):
            self.references.pop(index)
            self.reference_list.delete(index)

    def _create_pack(self) -> None:
        command = [sys.executable, str(Path(__file__).with_name("petpack.py")), "init", "--name", self.name.get(), "--species", self.species.get(), "--author", self.author.get(), "--output", self.output.get()]
        if self.breed.get().strip(): command += ["--breed", self.breed.get().strip()]
        for reference in self.references: command += ["--reference", str(reference)]
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        if result.returncode:
            self.messagebox.showerror("创建失败", result.stderr or result.stdout)
            return
        self.pack = Path(self.output.get()).expanduser().resolve()
        self._refresh_pack()
        self.messagebox.showinfo("已创建", f"资源包已创建：\n{self.pack}\n\n下一步把复制的制作指令与照片/视频发送到对话框。")

    def _open_pack(self) -> None:
        value = self.filedialog.askdirectory(title="选择含 manifest.json 的资源包")
        if value:
            self.pack = Path(value)
            self.output.set(value)
            self._refresh_pack()

    def _copy_prompt(self) -> None:
        prompt = conversation_prompt(self.references)
        self.root.clipboard_clear()
        self.root.clipboard_append(prompt)
        self.messagebox.showinfo("已复制", "制作指令已复制；请连同宠物照片/视频一起发送到对话框。")

    def _refresh_pack(self) -> None:
        if not self._require_pack(): return
        manifest = load_manifest(self.pack)
        names = ["walk", *manifest.get("animations", {}).get("behaviors", {}).keys()]
        self.animation_list.delete(0, "end")
        for name in names: self.animation_list.insert("end", name)
        for key, value in manifest.get("personality", {}).items():
            if key in self.personality: self.personality[key].set(value)
        if names:
            self.animation_list.selection_set(0)
            self._select_animation()

    def _select_animation(self, _event: object | None = None) -> None:
        if not self._require_pack() or not self.animation_list.curselection(): return
        name = self.animation_list.get(self.animation_list.curselection()[0])
        self.selected_animation.set(name)
        manifest = load_manifest(self.pack)
        spec = manifest["animations"]["walk"] if name == "walk" else manifest["animations"]["behaviors"][name]
        self.fps.set(spec.get("fps", 2))
        self.loops.set(spec.get("playback_loops", 2))
        self.weight.set(spec.get("autonomous_weight", 0))
        self.preview_frames = image_files(self.pack / "animations" / name)
        self.preview_index = 0
        if self.preview_job: self.root.after_cancel(self.preview_job)
        self._show_preview()

    def _show_preview(self) -> None:
        if not self.preview_frames:
            self.preview.configure(text="此动作尚无帧", image="")
            return
        try:
            image = self.tk.PhotoImage(file=str(self.preview_frames[self.preview_index]))
            scale = max(1, int(max(image.width(), image.height()) / 440))
            if scale > 1: image = image.subsample(scale, scale)
            self.preview.image = image
            self.preview.configure(image=image, text="")
        except self.tk.TclError:
            self.preview.configure(text=f"无法预览：{self.preview_frames[self.preview_index].name}", image="")
        self.preview_index = (self.preview_index + 1) % len(self.preview_frames)
        delay = int(1000 / max(.1, self.fps.get()))
        self.preview_job = self.root.after(delay, self._show_preview)

    def _save_animation(self) -> None:
        if not self._require_pack(): return
        update_animation(self.pack, self.selected_animation.get(), self.fps.get(), self.loops.get(), self.weight.get())
        self.messagebox.showinfo("已保存", "动作参数已写入 manifest.json")

    def _save_personality(self) -> None:
        if not self._require_pack(): return
        update_personality(self.pack, {key: variable.get() for key, variable in self.personality.items()})
        self.messagebox.showinfo("已保存", "个性参数已写入 manifest.json")

    def _validate(self, strict: bool) -> None:
        if not self._require_pack(): return
        command = [sys.executable, str(Path(__file__).with_name("petpack.py")), "validate", str(self.pack)]
        if strict: command.append("--strict")
        result = subprocess.run(command, text=True, capture_output=True, check=False)
        self.log.delete("1.0", "end")
        self.log.insert("end", result.stdout + result.stderr)

    def _export(self) -> None:
        if not self._require_pack(): return
        destination = self.filedialog.asksaveasfilename(defaultextension=".zip", initialfile=f"{self.pack.name}.zip", filetypes=[("Zip", "*.zip")])
        if destination:
            path = export_pack(self.pack, Path(destination))
            self.messagebox.showinfo("已导出", f"可分享资源包：\n{path}\n\n私人媒体和本地绝对路径未包含在压缩包中。")

    def _require_pack(self) -> bool:
        if self.pack and (self.pack / "manifest.json").is_file(): return True
        self.messagebox.showwarning("未打开资源包", "请先创建或打开资源包。")
        return False

    def run(self) -> None: self.root.mainloop()


def main() -> int:
    PetStudioApp().run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
