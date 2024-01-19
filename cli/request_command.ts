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
  .description('Get your requests.')
  .action(({ apiUrl }) => {
    const apiKey = ensureLogin();

    listRequests(apiUrl || defaultApiUrl, apiKey);
  });

const showCommand = new Command<Options>()
  .description('Get the request.')
  .arguments('<id:number>')
  .action(({ apiUrl }, id) => {
    const apiKey = ensureLogin();

    showRequest(apiUrl || defaultApiUrl, apiKey, id);
  });

const getFileCommand = new Command<void, void, Options, [string, string]>()
  .description('Get the content of submission file.')
  .arguments('<id:string> <path:string>')
  .action(({ apiUrl }, id, path) => {
    const apiKey = ensureLogin();

    getFile(apiUrl || defaultApiUrl, apiKey, id, path);
  });

const cancelCommand = new Command<void, void, Options, [string]>()
  .description('Cancel the request.')
  .arguments('<id:number>')
  .action(({ apiUrl }, id) => {
    const apiKey = ensureLogin();

    cancelRequest(apiUrl || defaultApiUrl, apiKey, id);
  });

const requestCommand: Command<Options> = new Command<Options>()
  .description('Manage requests.')
  .action(() => requestCommand.showHelp())
  .command('list', listCommand)
  .command('show', showCommand)
  .command('get-file', getFileCommand)
  .command('cancel', cancelCommand)
  .reset();

export default requestCommand;

type Request = {
  id: number;
  created_at: string;
  purpose: string;
  db: string;
  status: string;
  validity: string;

  submission?: {
    id: string;
  };
};

async function listRequests(apiUrl: string, apiKey: string) {
  const headers = ['ID', 'Started', 'Purpose', 'DB', 'Status', 'Validity', 'Submission'];
  const table = Table.from([headers.map(colors.bold.yellow)]);

  table.push(headers.map((header) => colors.bold.yellow('-'.repeat(header.length))));

  await paginatedFetch(`${apiUrl}/requests`, apiKey, async (res) => {
    await ensureSuccess(res);

    const requests: Request[] = await res.json();

    requests.forEach((req) => {
      table.push([
        colors.bold(req.id.toString()),
        req.created_at,
        req.purpose,
        req.db,
        req.status,
        req.validity,
        req.submission?.id || '',
      ]);
    });
  });

  table.render();
}

async function showRequest(apiUrl: string, apiKey: string, id: number) {
  const res = await fetch(`${apiUrl}/requests/${id}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const payload = await res.json();

  colorize(JSON.stringify(payload, null, 2));
}

async function getFile(apiUrl: string, apiKey: string, id: string, path: string) {
  const res = await fetch(`${apiUrl}/requests/${id}/files/${path}`, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  console.log(await res.text());
}

async function cancelRequest(apiUrl: string, apiKey: string, id: number) {
  const res = await fetch(`${apiUrl}/requests/${id}`, {
    method: 'DELETE',
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const payload = await res.json();

  colorize(JSON.stringify(payload, null, 2));
}
