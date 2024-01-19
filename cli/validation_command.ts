import { basename, resolve, toFileUrl } from 'std/path/mod.ts';
import { delay } from 'std/async/mod.ts';

import { Command } from 'cliffy/command/mod.ts';
import { Table } from 'cliffy/table/mod.ts';
import { colorize } from 'json_colorize/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';
import { format } from 'std/datetime/mod.ts';

import dbs from '../schema/db.json' with { type: 'json' };
import paginatedFetch from './paginated_fetch.ts';
import { defaultApiUrl, ensureLogin, ensureSuccess } from './util.ts';

type Options = {
  apiUrl?: string;
};

type CreateOptions = {
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

const _createCommand = new Command<Options>()
  .description('Validate the specified files.')
  .action(() => _createCommand.showHelp());

const createCommand = createDatabaseCommands()
  .reduce((cmd, [name, subCmd]) => cmd.command(name, subCmd).reset(), _createCommand);

const listCommand = new Command<Options>()
  .description('Get your validations.')
  .action(({ apiUrl }) => {
    const apiKey = ensureLogin();

    listValidations(apiUrl || defaultApiUrl, apiKey);
  });

const showCommand = new Command<Options>()
  .description('Get the validation.')
  .arguments('<id:number>')
  .action(({ apiUrl }, id) => {
    const apiKey = ensureLogin();

    showValidation(apiUrl || defaultApiUrl, apiKey, id);
  });

const getFileCommand = new Command<void, void, Options, [string, string]>()
  .description('Get the content of submission file.')
  .arguments('<id:string> <path:string>')
  .action(({ apiUrl }, id, path) => {
    const apiKey = ensureLogin();

    getFile(apiUrl || defaultApiUrl, apiKey, id, path);
  });

const cancelCommand = new Command<void, void, Options, [string]>()
  .description('Cancel the validation.')
  .arguments('<id:number>')
  .action(({ apiUrl }, id) => {
    const apiKey = ensureLogin();

    cancelValidation(apiUrl || defaultApiUrl, apiKey, id);
  });

const validationCommand: Command<Options> = new Command<Options>()
  .description('Manage validations.')
  .action(() => validationCommand.showHelp())
  .command('create', createCommand)
  .command('list', listCommand)
  .command('show', showCommand)
  .command('get-file', getFileCommand)
  .command('cancel', cancelCommand)
  .reset();

export default validationCommand;

type Validation = {
  id: number;
  db: string;
  created_at: string;
  finished_at: string;
  progress: string;
  validity: string;

  submission?: {
    id: string;
  };
};

async function listValidations(apiUrl: string, apiKey: string) {
  const headers = ['ID', 'DB', 'Started', 'Finished', 'Progress', 'Validity', 'Submission'];
  const table = Table.from([headers.map(colors.bold.yellow)]);

  table.push(headers.map((header) => colors.bold.yellow('-'.repeat(header.length))));

  await paginatedFetch(`${apiUrl}/validations`, apiKey, async (res) => {
    await ensureSuccess(res);

    const validations: Validation[] = await res.json();

    validations.forEach((req) => {
      table.push([
        colors.bold(req.id.toString()),
        req.db,
        formatDatetime(req.created_at),
        formatDatetime(req.finished_at),
        req.progress,
        req.validity,
        req.submission?.id || '',
      ]);
    });
  });

  table.render();
}

async function showValidation(apiUrl: string, apiKey: string, id: number) {
  const res = await fetch(`${apiUrl}/validations/${id}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const payload = await res.json();

  colorize(JSON.stringify(payload, null, 2));
}

async function getFile(apiUrl: string, apiKey: string, id: string, path: string) {
  const res = await fetch(`${apiUrl}/validations/${id}/files/${path}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  console.log(await res.text());
}

async function cancelValidation(apiUrl: string, apiKey: string, id: number) {
  const res = await fetch(`${apiUrl}/validations/${id}`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const payload = await res.json();

  colorize(JSON.stringify(payload, null, 2));
}

function formatDatetime(date?: string) {
  if (!date) return undefined;

  return format(new Date(date), 'yyyy-MM-dd HH:mm:ss');
}

function createDatabaseCommands(): [string, Command<Options>][] {
  return dbs.map((db) => {
    const _cmd = new Command<Options>()
      .description(`Validate ${db.id} files.`);

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

            const { url } = await createValidation(opts.apiUrl || defaultApiUrl, apiKey, db, objs);
            const payload = await waitForRequestFinished(url, apiKey);

            colorize(JSON.stringify(payload, null, 2));
          })
      ), _cmd)
      .reset();

    return [db.id.toLowerCase(), cmd];
  });
}

async function createValidation(apiUrl: string, apiKey: string, db: Db, objs: [Obj, ObjOption][]) {
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
