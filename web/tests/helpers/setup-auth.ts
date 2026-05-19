import { http } from '../msw/http';
import { worker } from '../msw/worker';

interface Options {
  admin?: boolean;
}

export function setupAuthentication(hooks: NestedHooks, options: Options = {}) {
  hooks.beforeEach(() => {
    localStorage.setItem('token', 'test-token');

    if (options.admin) {
      worker.use(
        http.get('/me', ({ response }) => {
          return response(200).json({
            uid: 'test-admin',
            api_key: 'test-api-key',
            admin: true,
          });
        }),
      );
    }
  });

  hooks.afterEach(() => {
    localStorage.removeItem('token');
  });
}
