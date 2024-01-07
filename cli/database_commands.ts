import { basename, resolve, toFileUrl } from 'std/path/mod.ts';
import { delay } from 'std/async/mod.ts';

import { Command } from 'cliffy/command/mod.ts';
import { colorize } from 'json_colorize/mod.ts';

import dbs from '../schema/db.json' with { type: 'json' };
import { Config } from './config.ts';
import { ensureSuccess } from './util.ts';

class DatabaseCommand extends Command {
  constructor({ endpoint, apiKey }: Config, resource: string, descriptionFn: (db: Db) => string) {
    super();

    // deno-lint-ignore no-this-alias
    let cmd = this;

    for (const db of dbs) {
      cmd = cmd
        .command(db.id.toLowerCase())
        .description(descriptionFn(db));

      for (const { id, ext, optional, multiple } of db.objects) {
        cmd = cmd.option(
          `--${id.toLowerCase()}.file <path:file>`,
          `Path to ${id} file (${ext})`,
          {
            required: optional !== true,
            collect: multiple === true,
          },
        );

        cmd = cmd.option(
          `--${id.toLowerCase()}.destination <path:string>`,
          'Destination path of this file',
          {
            collect: multiple === true,
          },
        );
      }

      cmd = cmd.action(async (opts) => {
        if (!apiKey) requireLogin();

        const { request } = await createRequest(endpoint, apiKey!, resource, db, opts);
        const payload = await waitForRequestFinished(request.url, apiKey!);

        colorize(JSON.stringify(payload, null, 2));
      });
    }

    return cmd.reset();
  }
}

export class ValidateCommand extends DatabaseCommand {
  constructor(config: Config) {
    super(config, 'validations', (db) => `Validate ${db.id} files.`);

    return this
      .description('Validate the specified files.')
      .action(() => this.showHelp());
  }
}

export class SubmitCommand extends DatabaseCommand {
  constructor(config: Config) {
    super(config, 'submissions', (db) => `Submit files to ${db.id}.`);

    return this
      .description('Submit files to the specified database.')
      .action(() => this.showHelp());
  }
}

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

async function createRequest(endpoint: string, apiKey: string, resource: string, db: Db, opts: Record<string, any>) {
  const body = new FormData();

  const promises = db.objects.map((obj) => {
    return [obj, opts[obj.id.toLowerCase()]];
  }).filter(([_obj, entry]) => entry).map(async ([obj, entry]) => {
    const key = obj.multiple ? `${obj.id}[]` : obj!.id;

    for (const [path, destination] of zip([entry.file].flat(), [entry.destination].flat())) {
      const file = await fetch(toFileUrl(resolve(path)));
      body.append(`${key}[file]`, await file.blob(), basename(path));

      if (destination) {
        body.append(`${key}[destination]`, destination);
      }
    }
  });

  await Promise.all(promises);

  const res = await fetch(
    `${endpoint}/${resource}/${db.id.toLowerCase()}/via-file`,
    {
      method: 'post',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
      },
      body,
    },
  );

  await ensureSuccess(res);

  return await res.json();
}

async function waitForRequestFinished(url: string, apiKey: string) {
  const res = await fetch(url, {
    headers: {
      'Authorization': `Bearer ${apiKey}`,
    },
  });

  await ensureSuccess(res);

  const payload = await res.json();
  const { status } = payload;

  if (status === 'finished' || status === 'canceled') return payload;

  await delay(1000);

  return waitForRequestFinished(url, apiKey);
}

function zip<T, U>(lhs: T[], rhs: U[]) {
  return lhs.map((e, i) => [e, rhs[i]]);
}
