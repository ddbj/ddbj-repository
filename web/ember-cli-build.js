'use strict';
const EmberApp = require('ember-cli/lib/broccoli/ember-app');

const path = require('path');

const { compatBuild } = require('@embroider/compat');

module.exports = async function (defaults) {
  const { buildOnce } = await import('@embroider/vite');
  const { setConfig } = await import('@warp-drive/build-config');

  const app = new EmberApp(defaults, {
    'ember-cli-babel': { enableTypeScriptTransform: true },

    babel: {
      plugins: [
        require.resolve('ember-concurrency/async-arrow-task-transform'),

        [
          require.resolve('babel-plugin-module-resolver'),
          {
            extensions: ['.js', '.ts', '.gjs', '.gts'],

            alias: {
              schema: path.resolve(__dirname, '../schema'),
            },
          },
        ],
      ],
    },
  });

  setConfig(app, __dirname, {
    compatWith: '5.8',
    deprecations: {},
  });

  return compatBuild(app, buildOnce);
};
