"""Exercise production plugin activation and validate each host's complete Niri config."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

for host in json.loads(Path(sys.argv[1]).read_text()):
    with tempfile.TemporaryDirectory(prefix=host['name']) as directory:
        root = Path(directory)
        config = root / 'config'
        environment = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(config),
                           XDG_DATA_HOME=str(root / 'data'), PATH='/no-ambient-tools')
        # This also ensures the tested native postCheck is a dependency of this check.
        subprocess.run([host['configure']], env=environment, check=True)
        settings = json.loads((config / 'DankMaterialShell/settings.json').read_text())
        managed = json.loads(Path(host['settings']).read_text())
        assert settings['enableFprint'] == managed['enableFprint'], host['name']
        assert settings['barConfigs'] == managed['barConfigs'], host['name']
        plugins = config / 'DankMaterialShell/plugin_settings.json'
        expected = json.loads(Path(host['pluginSettings']).read_text())
        for initial in [None, {'custom': {'enabled': True, 'option': 9},
                               **{key: {'enabled': False, 'localOption': 7} for key in expected}}]:
            if initial is None:
                plugins.unlink(missing_ok=True)
            else:
                plugins.write_text(json.dumps(initial))
            subprocess.run([host['plugins']], env=environment, check=True)
            result = json.loads(plugins.read_text())
            for key, value in expected.items():
                assert result[key]['enabled'] == value['enabled'], host['name']
                if initial is not None:
                    assert result[key]['localOption'] == 7, host['name']
            if initial is not None:
                assert result['custom'] == initial['custom'], host['name']
            before = plugins.read_bytes()
            subprocess.run([host['plugins']], env=environment, check=True)
            assert plugins.read_bytes() == before, host['name']
        for name, source in host['files'].items():
            target = config / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)
        subprocess.run([host['niri'], 'validate', '-c', str(config / 'niri/config.kdl')],
                       env=environment, check=True)
        print(f"{host['name']}: production activation, plugins and complete Niri config passed", flush=True)
