import { Command } from 'cliffy/command/mod.ts';
import { Table } from 'cliffy/table/mod.ts';
import { colorize } from 'json_colorize/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';

import createCommand from './validation_create_command.ts';
import paginatedFetch from './paginated_fetch.ts';
import { defaultApiUrl, ensureLogin, ensureSuccess, formatDatetime } from './util.ts';

import type { components } from '../schema/openapi.d.ts';

type Options = {
  apiUrl?: string;
};

type Validation = components['schemas']['Validation'];

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

async function listValidations(apiUrl: string, apiKey: string) {
  const headers = ['ID', 'DB', 'Created', 'Started', 'Finished', 'Progress', 'Validity', 'Submission'];
  const table = Table.from([headers.map(colors.bold.yellow)]);

  table.push(headers.map((header) => colors.bold.yellow('-'.repeat(header.length))));

  await paginatedFetch(`${apiUrl}/validations`, apiKey, async (res) => {
    await ensureSuccess(res);

    const validations: Validation[] = await res.json();

    validations.forEach((req) => {
      table.push([
        colors.bold(req.id.toString()),
        req.db,
        formatDatetime(req.created_at)!,
        formatDatetime(req.started_at) || '-',
        formatDatetime(req.finished_at) || '-',
        req.progress,
        req.validity || '-',
        req.submission?.id || '-',
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

  const { db, created_at, started_at, finished_at, progress, validity, submission, results } = await res.json() as Validation;

  console.log(`${colors.bold.yellow('ID:')} ${id}`);
  console.log(`${colors.bold.yellow('URL:')} ${new URL(`/web/validations/${id}`, apiUrl).href}`);
  console.log(`${colors.bold.yellow('DB:')} ${db}`);
  console.log(`${colors.bold.yellow('Created:')} ${formatDatetime(created_at)}`);
  console.log(`${colors.bold.yellow('Started:')} ${formatDatetime(started_at) || '-'}`);
  console.log(`${colors.bold.yellow('Finished:')} ${formatDatetime(finished_at) || '-'}`);
  console.log(`${colors.bold.yellow('Progress:')} ${progress}`);
  console.log(`${colors.bold.yellow('Validity:')} ${validity || '-'}`);
  console.log(`${colors.bold.yellow('Submission:')} ${submission?.id || '-'}`);
  console.log();
  console.log(colors.bold.yellow('Results:'));

  Table.from([
    ['Object', 'File', 'Validity'].map(colors.bold.yellow),

    ...results.map(({ object_id, file, validity }) => [
      object_id,
      file?.path || '-',
      validity || '-',
    ]),
  ]).render();
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
