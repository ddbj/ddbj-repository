import Controller from '@ember/controller';

export default class RequestsIndexController extends Controller {
  queryParams = [{ page: { type: 'number' } as const }];

  page?: number;
}
