import { dirname, join } from 'std/path/mod.ts';

export function read() {
  try {
    return Deno.readTextFileSync(apiKeyFilePath);
  } catch (err) {
    if (err.name !== 'NotFound') throw err;

    return undefined;
  }
}

export function write(apiKey: string) {
  Deno.mkdirSync(dirname(apiKeyFilePath), { recursive: true });
  Deno.writeTextFileSync(apiKeyFilePath, apiKey);
}

export function remove() {
  try {
    Deno.removeSync(apiKeyFilePath);
  } catch (err) {
    if (err.name !== 'NotFound') throw err;
  }
}

const configHome = Deno.env.get('XDG_CONFIG_HOME') || join(Deno.env.get('HOME')!, '.config');
const apiKeyFilePath = join(configHome, 'ddbj-repository', 'api-key');
