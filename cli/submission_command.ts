import { Command } from 'cliffy/command/mod.ts';
import { Table } from 'cliffy/table/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';

import paginatedFetch from './paginated_fetch.ts';
import { defaultApiUrl, ensureLogin, ensureSuccess, formatDatetime } from './util.ts';

import type { components } from '../schema/openapi.d.ts';

type Options = {
  apiUrl?: string;
};

type Submission = components['schemas']['Submission'];

const createCommand = new Command<void, void, Options, [number]>()
  .description('Create the submission.')
  .arguments('<validation_id:number>')
  .action(({ apiUrl }, validationId) => {
    const apiKey = ensureLogin();

    createSubmission(apiUrl || defaultApiUrl, apiKey, validationId);
  });

const listCommand = new Command<Options>()
  .description('Get your submissions.')
  .action(({ apiUrl }) => {
    const apiKey = ensureLogin();

    listSubmissions(apiUrl || defaultApiUrl, apiKey);
  });

const showCommand = new Command<void, void, Options, [string]>()
  .description('Get the submission.')
  .arguments('<id:string>')
  .action(({ apiUrl }, id) => {
    const apiKey = ensureLogin();

    showSubmission(apiUrl || defaultApiUrl, apiKey, id);
  });

const getFileCommand = new Command<void, void, Options, [string, string]>()
  .description('Get the content of submission file.')
  .arguments('<id:string> <path:string>')
  .action(({ apiUrl }, id, path) => {
    const apiKey = ensureLogin();

    getFile(apiUrl || defaultApiUrl, apiKey, id, path);
  });

const submissionCommand: Command<Options> = new Command<Options>()
  .description('Manage submissions.')
  .action(() => submissionCommand.showHelp())
  .command('create', createCommand)
  .command('list', listCommand)
  .command('show', showCommand)
  .command('get-file', getFileCommand)
  .reset();

export default submissionCommand;

async function createSubmission(apiUrl: string, apiKey: string, validationId: number) {
  const res = await fetch(`${apiUrl}/submissions/`, {
    method: 'POST',

    headers: {
      'Authorization': `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },

    body: JSON.stringify({ validation_id: validationId }),
  });

  await ensureSuccess(res);

  const { id, created_at, validation } = await res.json() as Submission;

  console.log(`${colors.bold.yellow('ID:')} ${id}`);
  console.log(`${colors.bold.yellow('URL:')} ${new URL(`/web/submissions/${id}`, apiUrl).href}`);
  console.log(`${colors.bold.yellow('DB:')} ${validation.db}`);
  console.log(`${colors.bold.yellow('Created:')} ${formatDatetime(created_at)}`);
  console.log(`${colors.bold.yellow('Validation:')} #${validation.id}`);
  console.log();
  console.log(colors.bold.yellow('Objects:'));

  Table.from([
    ['ID', 'Files'].map(colors.bold.yellow),

    ...validation.objects.map(({ id, files }) => [
      id,
      files.map(({ path }) => path).join('\n'),
    ]),
  ]).render();
}

async function listSubmissions(apiUrl: string, apiKey: string) {
  const headers = ['ID', 'DB', 'Created'];
  const table = Table.from([headers.map(colors.bold.yellow)]);

  table.push(headers.map((header) => colors.bold.yellow('-'.repeat(header.length))));

  await paginatedFetch(`${apiUrl}/submissions`, apiKey, async (res) => {
    await ensureSuccess(res);

    const submissions: Submission[] = await res.json();

    submissions.forEach((submission) => {
      table.push([
        colors.bold(submission.id),
        submission.validation.db,
        formatDatetime(submission.created_at)!,
      ]);
    });
  });

  table.render();
}

async function showSubmission(apiUrl: string, apiKey: string, id: string) {
  const res = await fetch(`${apiUrl}/submissions/${id}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const { created_at, validation } = await res.json() as Submission;

  console.log(`${colors.bold.yellow('ID:')} ${id}`);
  console.log(`${colors.bold.yellow('URL:')} ${new URL(`/web/submissions/${id}`, apiUrl).href}`);
  console.log(`${colors.bold.yellow('DB:')} ${validation.db}`);
  console.log(`${colors.bold.yellow('Created:')} ${formatDatetime(created_at)}`);
  console.log(`${colors.bold.yellow('Validation:')} #${validation.id}`);
  console.log();
  console.log(colors.bold.yellow('Objects:'));

  Table.from([
    ['ID', 'Files'].map(colors.bold.yellow),

    ...validation.objects.map(({ id, files }) => [
      id,
      files.map(({ path }) => path).join('\n'),
    ]),
  ]).render();
}

async function getFile(apiUrl: string, apiKey: string, id: string, path: string) {
  const res1 = await fetch(`${apiUrl}/submissions/${id}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res1);

  const { validation } = await res1.json() as Submission;

  const res2 = await fetch(`${apiUrl}/validations/${validation.id}/files/${path}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res2);

  console.log(await res2.text());
}
