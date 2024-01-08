import Route from '@ember/routing/route';
import { service } from '@ember/service';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class RequestsShowRoute extends Route {
  @service declare currentUser: CurrentUserService;

  async model({ id }: { id: string }) {
    return await waitForRequestFinished(`${ENV.apiURL}/requests/${id}`, this.currentUser.apiKey!);
  }
}

async function waitForRequestFinished(url: string, apiKey: string) {
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
  });

  const payload = await res.json();
  const { status } = payload;

  if (status === 'finished' || status === 'canceled') return payload;

  await new Promise((resolve) => setTimeout(resolve, 1000));

  return waitForRequestFinished(url, apiKey);
}
