import Controller from '@ember/controller';

export default class ValidationsIndexController extends Controller {
  queryParams = [{ page: { type: 'number' } as const }];

  page?: number;
}
