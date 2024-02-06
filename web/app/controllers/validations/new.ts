import Controller from '@ember/controller';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import DB from 'ddbj-repository/models/db';
import ENV from 'ddbj-repository/config/environment';

export default class ValidationsNewController extends Controller {
  queryParams = [{ db: { type: 'string' } as const }];

  dbs = ENV.dbs.map((db) => new DB(db));

  @tracked db = this.dbs[0]!.schema.id;

  get selectedDb() {
    return this.dbs.find((db) => db.schema.id === this.db)!;
  }

  @action
  selectDb(db: DB) {
    this.db = db.schema.id;
  }
}
