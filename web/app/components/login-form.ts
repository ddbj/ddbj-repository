import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { LoginError } from 'ddbj-repository/services/current-user';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ErrorModalService from 'ddbj-repository/services/error-modal';

export default class LoginFormComponent extends Component {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;

  @tracked errorMessage?: string;

  @action
  async login(e: Event) {
    e.preventDefault();

    this.errorMessage = undefined;

    const formData = new FormData(e.target as HTMLFormElement);

    try {
      await this.currentUser.login(formData.get('apiKey') as string);
    } catch (err) {
      if (err instanceof LoginError) {
        this.errorMessage = 'Login failed, please check your API key.';
      } else {
        this.errorModal.show(err as object);
      }
    }
  }
}
