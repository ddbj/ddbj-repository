import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

import ENV from 'repository/config/environment';

export default class ValidationsNewController extends Controller {
  queryParams = [{ db: { type: 'string' } as const }];

  @tracked db = ENV.dbs[0]!.id;
}
