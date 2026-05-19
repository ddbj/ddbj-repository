import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

export default class extends Controller {
  queryParams = ['query', 'include_inactive'];

  @tracked query = '';
  @tracked include_inactive = '';
}
