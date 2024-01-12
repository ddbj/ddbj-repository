import { Command } from 'cliffy/command/mod.ts';
import { Table } from 'cliffy/table/mod.ts';
import { colorize } from 'json_colorize/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';

import paginatedFetch from './paginated_fetch.ts';
import { defaultApiUrl, ensureLogin, ensureSuccess } from './util.ts';

type Options = {
  apiUrl?: string;
};

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
  .command('list', listCommand)
  .command('show', showCommand)
  .command('get-file', getFileCommand)
  .reset();

export default submissionCommand;

type Submission = {
  id: string;
  created_at: string;
  db: string;

  objects: Array<{
    id: string;

    files: Array<{
      path: string;
    }>;
  }>;
};

async function listSubmissions(apiUrl: string, apiKey: string) {
  const headers = ['ID', 'Created', 'DB'];
  const table = Table.from([headers.map(colors.bold.yellow)]);

  table.push(headers.map((header) => colors.bold.yellow('-'.repeat(header.length))));

  await paginatedFetch(`${apiUrl}/submissions`, apiKey, async (res) => {
    await ensureSuccess(res);

    const submissions: Submission[] = await res.json();

    submissions.forEach((submission) => {
      table.push([
        colors.bold(submission.id),
        submission.created_at,
        submission.db,
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

  const payload = await res.json();

  colorize(JSON.stringify(payload, null, 2));
}

async function getFile(apiUrl: string, apiKey: string, id: string, path: string) {
  const res = await fetch(`${apiUrl}/submissions/${id}/files/${path}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  console.log(await res.text());
}
