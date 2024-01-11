import { Command } from 'cliffy/command/mod.ts';
import { colors } from 'cliffy/ansi/colors.ts';
import { keypress } from 'cliffy/keypress/mod.ts';
import { open } from 'https://deno.land/x/open@v0.0.6/index.ts';

import { Config, writeConfig } from './config.ts';
import { ensureSuccess } from './util.ts';

export default class extends Command {
  constructor({ endpoint, apiKey }: Config) {
    super();

    return this
      .action(() => this.showHelp())
      .command('whoami')
      .action(async () => {
        if (apiKey) {
          const uid = await fetchUid(endpoint, apiKey);

          console.log(`Logged in as ${colors.bold(uid)}.`);
        } else {
          console.log('Not logged in.');
        }
      })
      .command('login')
      .arguments('[api-key:string]')
      .action(async (_opts, apiKey) => {
        if (apiKey) {
          const uid = await fetchUid(endpoint, apiKey);

          console.log(`Logged in as ${colors.bold(uid)}.`);

          await writeConfig({ apiKey });
        } else {
          await openLoginURL(endpoint);
        }
      })
      .command('logout')
      .action(async () => {
        await writeConfig({ apiKey: undefined });
      })
      .reset();
  }
}

async function openLoginURL(endpoint: string) {
  const res = await fetch(`${endpoint}/api-key`);
  const { login_url } = await res.json();

  console.log(colors.bold('cli: Press any key to open up the browser to login or q to exit:'));

  const event = await keypress();

  if (event.key === 'q') {
    console.log('Quit');
    Deno.exit(0);
  }

  console.log(`Opening browser to ${login_url}`);
  console.log();
  console.log('Execute the following command with the API key displayed in your browser:');
  console.log();
  console.log(colors.bold('$ ddbj-repository auth login YOUR_API_KEY'));

  await open(login_url);
}

async function fetchUid(endpoint: string, apiKey: string) {
  const res = await fetch(`${endpoint}/me`, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
  });

  await ensureSuccess(res);

  const { uid } = await res.json();

  return uid;
}
