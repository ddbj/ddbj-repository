import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

export default class ValidationsIndexController extends Controller {
  queryParams = [
    {
      page: { type: 'number' } as const,
      db: { type: 'string' } as const,
      created: { type: 'string' } as const,
      progress: { type: 'string' } as const,
      validity: { type: 'string' } as const,
      submitted: { type: 'boolean' } as const,
    },
  ];

  @tracked page = 1;
  @tracked pageBefore?: number;

  @tracked db?: string;
  @tracked created?: string;
  @tracked progress?: string;
  @tracked validity?: string;
  @tracked submitted?: boolean;
}
