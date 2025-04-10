import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';
import type RequestService from 'repository/services/request';
import type ToastService from 'repository/services/toast';

export default class AccountController extends Controller {
  @service declare currentUser: CurrentUserService;
  @service declare request: RequestService;
  @service declare toast: ToastService;

  @action
  async copyApiKey() {
    await navigator.clipboard.writeText(this.currentUser.user!.apiKey);

    this.toast.show('Copied to clipboard.', 'success');
  }

  @action
  async regenerateApiKey() {
    const res = await this.request.fetchWithModal('/api_key/regenerate', {
      method: 'POST',
    });

    const { api_key } = (await res.json()) as { api_key: string };

    this.currentUser.user!.apiKey = api_key;
  }
}
