import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

export default class extends Controller {
  queryParams = ['db', 'user', { page: { type: 'number' } as const }];

  @tracked db = '';
  @tracked user = '';
  @tracked page = 1;
}
