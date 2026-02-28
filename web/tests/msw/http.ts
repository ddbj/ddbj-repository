import { createOpenApiHttp } from 'openapi-msw';

import ENV from 'repository/config/environment';

import type { paths } from 'schema/openapi';

export const http = createOpenApiHttp<paths>({ baseUrl: ENV.apiURL });
