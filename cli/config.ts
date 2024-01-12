import { dirname, join } from 'std/path/mod.ts';
import { parse } from 'std/jsonc/mod.ts';

export type Config = {
  endpoint: string;
  apiKey?: string;
};

export const defaultConfig = {
  endpoint: 'https://repository-dev.ddbj.nig.ac.jp/api',
};

export async function readConfig() {
  try {
    return parse(await Deno.readTextFile(configFilePath));
  } catch (err) {
    if (err.name === 'NotFound') {
      return {};
    } else {
      throw err;
    }
  }
}

export async function writeConfig(config: object) {
  const newConfig = Object.assign({}, await readConfig(), config);

  await Deno.mkdir(dirname(configFilePath), { recursive: true });
  await Deno.writeTextFile(configFilePath, JSON.stringify(newConfig, null, '  '));
}

const configHome = Deno.env.get('XDG_CONFIG_HOME') || join(Deno.env.get('HOME')!, '.config');
const configFilePath = join(configHome, 'ddbj-repository', 'config.jsonc');
