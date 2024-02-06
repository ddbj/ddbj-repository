import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

import type { Model } from 'ddbj-repository/routes/submissions/index';

export default class SubmissionsIndexController extends Controller {
  queryParams = [{ page: { type: 'number' } as const }];

  declare model: Model;

  @tracked page = 1;
  @tracked pageBefore?: number;
}
