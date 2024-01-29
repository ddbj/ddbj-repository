import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

import type { Model } from 'ddbj-repository/routes/validations/index';

export default class ValidationsIndexController extends Controller {
  queryParams = [{ page: { type: 'number' } as const }];

  declare model: Model;

  @tracked page?: number;
  @tracked pageBefore?: number;
}
