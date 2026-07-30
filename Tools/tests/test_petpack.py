from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "Tools" / "petpack.py"


class PetPackCLITests(unittest.TestCase):
    def test_initializes_species_specific_rabbit_pack_without_copying_media(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reference = root / "rabbit.jpg"
            reference.write_bytes(b"reference-only")
            output = root / "pack"

            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL),
                    "init",
                    "--name",
                    "Tuanzi",
                    "--species",
                    "rabbit",
                    "--reference",
                    str(reference),
                    "--output",
                    str(output),
                ],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 0, result.stderr)
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            request = json.loads((output / "pet_request.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["profile"]["species"], "rabbit")
            self.assertEqual(manifest["schema_version"], 2)
            self.assertIn("personality", manifest)
            self.assertEqual({toy["kind"] for toy in manifest["toys"]}, {"ball", "laser", "wand", "box", "food", "water"})
            self.assertIn("binky", manifest["animations"]["behaviors"])
            self.assertTrue((output / "animations" / "binky").is_dir())
            self.assertFalse((output / reference.name).exists())
            self.assertEqual(request["references"][0]["filename"], reference.name)
            self.assertNotIn(str(root), (output / "pet_request.json").read_text(encoding="utf-8"))

    def test_strict_validation_reports_missing_frames(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "pack"
            init = subprocess.run(
                [
                    sys.executable,
                    str(TOOL),
                    "init",
                    "--name",
                    "Fufu",
                    "--species",
                    "ferret",
                    "--output",
                    str(output),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(init.returncode, 0, init.stderr)

            result = subprocess.run(
                [sys.executable, str(TOOL), "validate", str(output), "--strict"],
                text=True,
                capture_output=True,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("animations/war_dance", result.stdout)
            self.assertIn("errors=", result.stdout)

    def test_validation_rejects_unsafe_extension_path(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "pack"
            result = subprocess.run(
                [sys.executable, str(TOOL), "init", "--name", "Mimi", "--species", "cat", "--output", str(output)],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            manifest_path = output / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["extensions"] = [{"id": "bad", "kind": "behavior-pack", "path": "../private"}]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            validation = subprocess.run(
                [sys.executable, str(TOOL), "validate", str(output)],
                text=True, capture_output=True, check=False,
            )
            self.assertEqual(validation.returncode, 1)
            self.assertIn("扩展路径必须留在资源包内", validation.stdout)


if __name__ == "__main__":
    unittest.main()
