import { basename, resolve, toFileUrl } from 'std/path/mod.ts';
import { delay } from 'std/async/mod.ts';

import { Command } from 'cliffy/command/mod.ts';
import { colorize } from 'json_colorize/mod.ts';

import dbs from '../schema/db.json' with { type: 'json' };
import { defaultApiUrl, ensureLogin, ensureSuccess } from './util.ts';

type Options = {
  apiUrl?: string;
  [key: string]: string | undefined | ObjOption;
};

type ObjOption = {
  file: string;
  destination?: string;
};

type Db = {
  id: string;
  objects: Obj[];
};

type Obj = {
  id: string;
  ext: string;
  optional?: boolean;
  multiple?: boolean;
};

function createDatabaseCommands(resource: string, descriptionFn: (db: Db) => string): [string, Command<Options>][] {
  return dbs.map((db) => {
    const _cmd = new Command<Options>()
      .description(descriptionFn(db));

    const cmd = db.objects
      .reduce((cmd, { id, ext, optional, multiple }) => (
        cmd
          .option(
            `--${id.toLowerCase()}.file <path:file>`,
            `Path to ${id} file (${ext})`,
            { required: !optional, collect: !!multiple },
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
            }) as [Obj, ObjOption][];

            const { request } = await createRequest(opts.apiUrl || defaultApiUrl, apiKey, resource, db, objs);
            const payload = await waitForRequestFinished(request.url, apiKey);

            colorize(JSON.stringify(payload, null, 2));
          })
      ), _cmd)
      .reset();

    return [db.id.toLowerCase(), cmd];
  });
}

const _validateCommand = new Command<Options>()
  .description('Validate the specified files.')
  .action(() => _validateCommand.showHelp());

export const validateCommand = createDatabaseCommands('validations', (db) => `Validate ${db.id} files.`)
  .reduce((cmd, [name, subCmd]) => cmd.command(name, subCmd).reset(), _validateCommand);

export const _submitCommand = new Command<Options>()
  .description('Submit files to the specified database.')
  .action(() => _submitCommand.showHelp());

export const submitCommand = createDatabaseCommands('submissions', (db) => `Submit files to ${db.id}.`)
  .reduce((cmd, [name, subCmd]) => cmd.command(name, subCmd).reset(), _submitCommand);

async function createRequest(apiUrl: string, apiKey: string, resource: string, db: Db, objs: [Obj, ObjOption][]) {
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

  const res = await fetch(`${apiUrl}/${resource}/via-file`, {
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
