import importlib.util
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path
from unittest.mock import patch

import yaml


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ufsvrf_setup", ROOT / "parm" / "setup.py")
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


class MDTSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        with (ROOT / "parm" / "config_base.yaml").open() as stream:
            self.base = yaml.safe_load(stream)
        with (ROOT / "parm" / "config_mdt.yaml").open() as stream:
            self.mdt = yaml.safe_load(stream)

    def generate(self, base, script_dir=None):
        config_path = self.directory / "base.yaml"
        config_path.write_text(yaml.safe_dump(base))
        generator = setup.ConfigGenerator(config_path)
        with (ROOT / "parm" / "config_platform.yaml").open() as stream:
            generator.platform_config = yaml.safe_load(stream)
        if script_dir is not None:
            generator.script_dir = script_dir
        with (
            patch.object(generator, "load_config_platform"),
            patch.object(generator, "get_output_dir", return_value=self.directory),
            patch.object(generator, "generate_job_cards", return_value=[]),
            patch.object(generator, "generate_ecflow_files", return_value=[]),
        ):
            generator.generate()
        return generator

    def test_selected_mdt_sections_and_existing_task(self):
        base = deepcopy(self.base)
        base["task_list"] = ["vx_grid2grid", "mdt_tmp", "mdt_wind", "mdt_aod"]
        self.generate(base)

        for task in base["task_list"][1:]:
            output = yaml.safe_load((self.directory / f"config_{task}.yaml").read_text())
            expected = {
                section: {name: self.mdt[section][name] for name in names}
                for section, names in base["tasks"][task]["groups"].items()
            }
            self.assertEqual(output, expected)

        existing = yaml.safe_load((self.directory / "config_vx_grid2grid.yaml").read_text())
        self.assertEqual(existing["ncdiffs"], base["vx_grid2grid"]["ncdiffs"])
        self.assertIn("variables", existing)

        wind = yaml.safe_load((self.directory / "config_mdt_wind.yaml").read_text())
        self.assertEqual(wind["plots"]["conditional_quantile_wind"]["kwargs"]["obs_col"], "ws")
        self.assertEqual(wind["plots"]["spatial_bias_wind"]["kwargs"]["col1"], "ws")
        self.assertEqual(self.mdt["plots"]["conditional_quantile_temp"]["kwargs"]["obs_col"], "t2m")
        self.assertEqual(self.mdt["plots"]["spatial_bias"]["kwargs"]["col1"], "t2m")

    def test_new_mdt_task_and_invalid_references(self):
        base = deepcopy(self.base)
        base["task_list"] = ["mdt_new"]
        base["tasks"]["mdt_new"] = {"groups": {"data": ["gfs_model"]}}
        self.generate(base)
        output = yaml.safe_load((self.directory / "config_mdt_new.yaml").read_text())
        self.assertEqual(output, {"data": {"gfs_model": self.mdt["data"]["gfs_model"]}})

        for groups, error in (
            (["data"], "'groups' must be a mapping"),
            ({"unknown": ["x"]}, "unknown MDT section"),
            ({"data": ["missing"]}, "unknown data entries"),
            ({"data": "gfs_model"}, "invalid names"),
        ):
            with self.subTest(groups=groups):
                base["tasks"]["mdt_new"]["groups"] = groups
                with self.assertRaisesRegex(ValueError, error):
                    self.generate(base)

    def test_mdt_file_is_required_only_for_mdt_tasks(self):
        base = deepcopy(self.base)
        base["task_list"] = ["vx_grid2grid"]
        self.generate(base, script_dir=self.directory)

        base["task_list"] = ["mdt_tmp"]
        with self.assertRaises(FileNotFoundError):
            self.generate(base, script_dir=self.directory)


if __name__ == "__main__":
    unittest.main()
