import { Command, CompletionsCommand } from 'cliffy/command/mod.ts';

import authCommand from './auth_command.ts';
import submissionCommand from './submission_command.ts';
import validationCommand from './validation_command.ts';

type Options = {
  apiUrl?: string;
};

const main: Command<Options> = new Command<Options>()
  .name('ddbj-repository')
  .version('0.1.0')
  .description('Command-line client for DDBJ Repository API')
  .env('DDBJ_REPOSITORY_API_URL=<url:string>', 'API endpoint URL', { global: true, prefix: 'DDBJ_REPOSITORY_' })
  .action(() => main.showHelp())
  .command('auth', authCommand)
  .command('validation', validationCommand)
  .command('submission', submissionCommand)
  .command('completion', new CompletionsCommand())
  .reset();

export default main;
