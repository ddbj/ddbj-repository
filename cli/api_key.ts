import { dirname } from 'std/path/dirname.ts';
import { join } from 'std/path/join.ts';

const configHome = Deno.env.get('XDG_CONFIG_HOME') || join(Deno.env.get('HOME')!, '.config');
const apiKeyFilePath = join(configHome, 'ddbj-repository', 'api-key');

function read() {
  try {
    return Deno.readTextFileSync(apiKeyFilePath);
  } catch (err) {
    if (err instanceof Error && err.name === 'NotFound') {
      return undefined;
    } else {
      throw err;
    }
  }
}

function write(apiKey: string) {
  Deno.mkdirSync(dirname(apiKeyFilePath), { recursive: true });
  Deno.writeTextFileSync(apiKeyFilePath, apiKey);
}

function remove() {
  try {
    Deno.removeSync(apiKeyFilePath);
  } catch (err) {
    if (err instanceof Error && err.name === 'NotFound') {
      // do nothing
    } else {
      throw err;
    }
  }
}

export const _internals = {
  read,
  write,
  remove,
};
