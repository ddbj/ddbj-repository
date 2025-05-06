import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

import { dbNames } from 'repository/models/db';

export default class ValidationsNewController extends Controller {
  queryParams = [{ db: { type: 'string' } as const }];

  @tracked db = dbNames[0];
}
