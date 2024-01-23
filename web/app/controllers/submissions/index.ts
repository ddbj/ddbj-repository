import Controller from '@ember/controller';

import type { Model } from 'ddbj-repository/routes/submissions/index';

export default class SubmissionsIndexController extends Controller {
  queryParams = [{ page: { type: 'number' } as const }];

  declare model: Model;

  page?: number;
}
