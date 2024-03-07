import { Command } from 'cliffy/command/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';
import { keypress } from 'cliffy/keypress/mod.ts';
import { open } from 'https://deno.land/x/open@v0.0.6/index.ts';

import { defaultApiUrl, ensureSuccess } from './util.ts';
import { read, remove, write } from './api_key.ts';

export const _internals = { keypress, open, read, remove, write };

type Options = {
  apiUrl?: string;
};

const whoamiCommand = new Command<Options>()
  .description('Show your logged in name.')
  .action(async ({ apiUrl }) => {
    const apiKey = _internals.read();

    if (apiKey) {
      const uid = await fetchUid(apiUrl || defaultApiUrl, apiKey);

      console.log(`Logged in as ${colors.bold(uid)}.`);
    } else {
      console.log('Not logged in.');
    }
  });

const loginCommand = new Command<void, void, Options, [string?]>()
  .description('Login.')
  .arguments('[api-key:string]')
  .action(async ({ apiUrl }, apiKey) => {
    apiUrl = apiUrl || defaultApiUrl;

    if (apiKey) {
      const uid = await fetchUid(apiUrl, apiKey);

      console.log(`Logged in as ${colors.bold(uid)}.`);

      _internals.write(apiKey);
    } else {
      await openLoginURL(apiUrl);
    }
  });

const logoutCommand = new Command()
  .description('Logout.')
  .action(() => {
    _internals.remove();
  });

const authCommand: Command<Options> = new Command<Options>()
  .description('Authenticate with DDBJ Repository.')
  .action(() => authCommand.showHelp())
  .command('whoami', whoamiCommand)
  .command('login', loginCommand)
  .command('logout', logoutCommand)
  .reset();

export default authCommand;

async function openLoginURL(apiUrl: string) {
  const res = await fetch(`${apiUrl}/api-key`);
  const { login_url } = await res.json();

  console.log(colors.bold('cli: Press any key to open up the browser to login or q to exit:'));

  const event = await _internals.keypress();

  if (event.key === 'q') {
    console.log('Quit');
    Deno.exit(0);
  }

  console.log(`Opening browser to ${login_url}`);
  console.log();
  console.log('Execute the following command with the API key displayed in your browser:');
  console.log();
  console.log(colors.bold('$ ddbj-repository auth login YOUR_API_KEY'));

  await _internals.open(login_url);
}

async function fetchUid(apiUrl: string, apiKey: string) {
  const res = await fetch(`${apiUrl}/me`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });

  await ensureSuccess(res);

  const { uid } = await res.json();

  return uid;
}
