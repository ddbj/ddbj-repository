import '@warp-drive/ember/install';
import Application from 'repository/app';
import config from 'repository/config/environment';
import * as QUnit from 'qunit';
import { setApplication } from '@ember/test-helpers';
import { setup } from 'qunit-dom';
import { start as qunitStart, setupEmberOnerrorValidation } from 'ember-qunit';

import { worker } from './msw/worker';

export async function start() {
  await worker.start({
    quiet: true,

    onUnhandledFrame({ frame, defaults }) {
      if (frame.protocol === 'http') {
        const { request } = frame.data as { request: Request };
        const url = new URL(request.url);

        if (url.pathname.startsWith('/socket.io/') || url.pathname === '/favicon.ico') {
          return;
        }
      }

      defaults.warn();
    },
  });

  setApplication(Application.create(config.APP));

  setup(QUnit.assert);
  setupEmberOnerrorValidation();
  qunitStart();
}
