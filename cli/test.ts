import { snapshotTest } from 'cliffy/testing/mod.ts';

import mainCommand from './main_command.ts';

await snapshotTest({
  name: '--help',
  meta: import.meta,
  denoArgs: ['--allow-all'],

  async fn() {
    await mainCommand.parse(['--help']);
  }
});
