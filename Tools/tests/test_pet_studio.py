from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
import zipfile
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
STUDIO = ROOT / "Tools" / "pet_studio.py"
sys.path.insert(0, str(STUDIO.parent))
spec = importlib.util.spec_from_file_location("pet_studio", STUDIO)
assert spec and spec.loader
studio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(studio)


class PetStudioTests(unittest.TestCase):
    def test_updates_manifest_and_exports_without_private_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pack = root / "pet"
            (pack / "animations" / "walk").mkdir(parents=True)
            manifest = {
                "schema_version": 2,
                "id": "pet",
                "personality": {},
                "animations": {"walk": {"fps": 4, "frames": []}, "behaviors": {"play_toy": {"fps": 2}}},
            }
            (pack / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            (pack / ".petpack-local.json").write_text('{"references":["/private/pet.jpg"]}', encoding="utf-8")
            (pack / "generation-plan.md").write_text("plan", encoding="utf-8")

            studio.update_personality(pack, {"playfulness": 1.8, "calmness": -.2})
            studio.update_animation(pack, "play_toy", 3.4, 4, 1.2)
            updated = studio.load_manifest(pack)
            self.assertEqual(updated["personality"]["playfulness"], 1)
            self.assertEqual(updated["personality"]["calmness"], 0)
            self.assertEqual(updated["animations"]["behaviors"]["play_toy"]["playback_loops"], 4)

            archive_path = studio.export_pack(pack, root / "share.zip")
            with zipfile.ZipFile(archive_path) as archive:
                names = archive.namelist()
                self.assertTrue(any(name.endswith("manifest.json") for name in names))
                self.assertFalse(any(".petpack-local.json" in name for name in names))
                self.assertNotIn("/private/pet.jpg", "\n".join(names))


if __name__ == "__main__":
    unittest.main()
