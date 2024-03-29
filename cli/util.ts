import { format } from 'std/datetime/mod.ts';

import { colorize } from 'json_colorize/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';

import { _internals } from './api_key.ts';

export const defaultApiUrl = 'https://repository-dev.ddbj.nig.ac.jp/api';

export function ensureLogin() {
  const apiKey = _internals.read();

  if (!apiKey) {
    console.error(`First you need to log in; run ${colors.bold('`ddbj-repository auth login`')}.`);
    Deno.exit(1);
  }

  return apiKey;
}

export async function ensureSuccess(res: Response) {
  if (res.ok) return;

  const type = res.headers.get('content-type');

  if (type?.includes('application/json')) {
    const payload = await res.json();

    colorize(JSON.stringify(payload, null, 2));
  } else {
    console.error(`Error: ${res.status} ${await res.text()}`);
  }

  Deno.exit(1);
}

export function formatDatetime(date: string | null) {
  if (!date) return undefined;

  return format(new Date(date), 'yyyy-MM-dd HH:mm:ss');
}
