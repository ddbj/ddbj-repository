import Controller from '@ember/controller';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import DB from 'ddbj-repository/models/db';
import ENV from 'ddbj-repository/config/environment';

export default class ValidationsNewController extends Controller {
  dbs = ENV.dbs.map((db) => new DB(db));

  @tracked selectedDb = this.dbs[0]!;

  @action
  selectDb(db: DB) {
    this.selectedDb = db;
  }
}
