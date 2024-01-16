import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';
import { DB } from 'ddbj-repository/components/submit-form';

export default class SubmitController extends Controller {
  dbs = ENV.dbs.map((db) => new DB(db));

  @tracked selectedDb = this.dbs[0];
}
