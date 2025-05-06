import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

export default class SubmissionsIndexController extends Controller {
  queryParams = [
    {
      page: { type: 'number' } as const,
      db: { type: 'string' } as const,
      created: { type: 'string' } as const,
    },
  ];

  @tracked page = 1;
  @tracked pageBefore?: number;

  @tracked db?: string;
  @tracked created?: string;
}
