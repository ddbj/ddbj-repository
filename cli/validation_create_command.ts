import { basename } from 'std/path/basename.ts';
import { delay } from 'std/async/delay.ts';
import { resolve } from 'std/path/resolve.ts';
import { toFileUrl } from 'std/path/to_file_url.ts';

import { Command } from 'cliffy/command/mod.ts';
import { colorize } from 'json_colorize/mod.ts';

import dbs from '../schema/db.json' with { type: 'json' };
import { defaultApiUrl, ensureLogin, ensureSuccess } from './util.ts';

import type { DBSchema, ObjSchema } from '../schema/db.d.ts';

type Options = {
  apiUrl?: string;
  [key: string]: string | undefined | ObjOption;
};

type ObjOption = {
  file: string;
  destination?: string;
};

const _createCommand = new Command<Options>()
  .description('Validate the specified files.')
  .action(() => _createCommand.showHelp());

export default createDatabaseCommands()
  .reduce((cmd, [name, subCmd]) => cmd.command(name, subCmd).reset(), _createCommand);

function createDatabaseCommands(): [string, Command<Options>][] {
  return dbs.map((db) => {
    const _cmd = new Command<Options>()
      .description(`Validate ${db.id} files.`);

    const cmd = db.objects
      .reduce((cmd, { id, ext, required, multiple }) => (
        cmd
          .option(
            `--${id.toLowerCase()}.file <path:file>`,
            `Path to ${id} file (${ext})`,
            { required, collect: !!multiple },
          )
          .option(
            `--${id.toLowerCase()}.destination <path:string>`,
            'Destination path of this file',
            { collect: !!multiple },
          )
          .action(async (opts) => {
            const apiKey = ensureLogin();

            const objs = db.objects.flatMap((obj) => {
              const opt = opts[obj.id.toLowerCase()] as ObjOption | undefined;

              return opt ? [[obj, opt]] : [];
            }) as [ObjSchema, ObjOption][];

            const { url } = await createValidation(opts.apiUrl || defaultApiUrl, apiKey, db, objs);
            const payload = await waitForRequestFinished(url, apiKey);

            colorize(JSON.stringify(payload, null, 2));
          })
      ), _cmd)
      .reset();

    return [db.id.toLowerCase(), cmd];
  });
}

async function createValidation(apiUrl: string, apiKey: string, db: DBSchema, objs: [ObjSchema, ObjOption][]) {
  const body = new FormData();
  body.set('db', db.id);

  const promises = objs
    .map(async ([obj, val]) => {
      const key = obj.multiple ? `${obj.id}[]` : obj.id;

      for (const [path, destination] of zip([val.file].flat(), [val.destination].flat())) {
        const file = await fetch(toFileUrl(resolve(path!)));
        body.append(`${key}[file]`, await file.blob(), basename(path!));

        if (destination) {
          body.append(`${key}[destination]`, destination);
        }
      }
    });

  await Promise.all(promises);

  const res = await fetch(`${apiUrl}/validations/via-file`, {
    method: 'post',
    headers: { 'Authorization': `Bearer ${apiKey}` },
    body,
  });

  await ensureSuccess(res);

  return await res.json();
}

async function waitForRequestFinished(url: string, apiKey: string) {
  const res = await fetch(url, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const payload = await res.json();
  const { progress } = payload;

  if (progress === 'finished' || progress === 'canceled') return payload;

  await delay(1000);

  return waitForRequestFinished(url, apiKey);
}

function zip<T, U>(xs: T[], ys: U[]) {
  return xs.map((x, i) => [x, ys[i]]);
}
