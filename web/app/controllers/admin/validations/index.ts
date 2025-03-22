import { tracked } from '@glimmer/tracking';

import { task, timeout } from 'ember-concurrency';

import ValidationsIndexBaseController from 'repository/controllers/validations-index-base';
import { queryParams } from 'repository/controllers/validations/index';

export default class AdminValidationsIndexController extends ValidationsIndexBaseController {
  queryParams = [
    {
      ...queryParams[0],
      uid: { type: 'string' } as const,
    },
  ];

  @tracked uid?: string;

  onUIDChange = task({ restartable: true }, async (e: Event) => {
    const uid = (e.target as HTMLInputElement).value;

    await timeout(500);

    this.page = 1;
    this.uid = uid === '' ? undefined : uid;
  });
}
