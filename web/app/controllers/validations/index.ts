import Controller from '@ember/controller';

import type { Model } from 'ddbj-repository/routes/validations/index';

export default class ValidationsIndexController extends Controller {
  queryParams = [{ page: { type: 'number' } as const }];

  declare model: Model;

  page?: number;
}
