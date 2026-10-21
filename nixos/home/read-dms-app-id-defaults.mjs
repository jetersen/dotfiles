import { readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import vm from 'node:vm';

const shell = process.argv[2];
const common = process.argv[3];
const modules = new Map();

// Load QML JavaScript imports using the same shared library as the shell build.
// The flake source's DCommon submodule is supplied by a separate Nix input.
function load(filename) {
  const prefix = join(shell, 'quickshell/DCommon') + '/';
  if (filename.startsWith(prefix)) {
    filename = join(common, 'DCommon', filename.slice(prefix.length));
  }
  if (modules.has(filename)) return modules.get(filename);
  const context = vm.createContext({ console });
  modules.set(filename, context);
  const source = readFileSync(filename, 'utf8')
    .replace(/^\s*\.pragma\b.*$/gm, '')
    .replace(/^\s*\.import\s+"([^"]+)"\s+as\s+(\w+)\s*$/gm, (_, path, name) => {
      context[name] = load(resolve(dirname(filename), path));
      return '';
    });
  vm.runInContext(source, context, { filename });
  return context;
}

const defaults = load(join(shell, 'quickshell/Common/settings/SettingsSpec.js')).SPEC.appIdSubstitutions.def;
process.stdout.write(JSON.stringify(defaults));
