import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import type { Model } from 'ddbj-repository/routes/validations/index';
import type Router from '@ember/routing/router';

export default class ValidationsIndexController extends Controller {
  @service declare router: Router;

  queryParams = [{ page: { type: 'number' } as const }, { db: { type: 'string' } as const }];

  declare model: Model;

  @tracked page?: number;
  @tracked pageBefore?: number;

  @tracked db?: string;

  @action
  updateDB(db?: string) {
    this.db = db;
    this.page = undefined;
  }
}
