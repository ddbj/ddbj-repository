import Component from '@glimmer/component';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { task } from 'ember-concurrency';

import { LoginError } from 'ddbj-repository/services/current-user';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ErrorModalService from 'ddbj-repository/services/error-modal';
import type ToastService from 'ddbj-repository/services/toast';

interface Signature {
  Args: {
    loginURL: string;
  };
}

export default class LoginFormComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare toast: ToastService;

  @tracked errorMessage?: string;

  login = task({ drop: true }, async (e: Event) => {
    e.preventDefault();

    const formData = new FormData(e.target as HTMLFormElement);

    try {
      await this.currentUser.login(formData.get('apiKey') as string);

      this.toast.show('Logged in.', 'success');
    } catch (err) {
      if (err instanceof LoginError) {
        this.toast.show('Login failed, please check your API key.', 'danger');
      } else {
        this.errorModal.show(err as object);
      }
    }
  });
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    LoginForm: typeof LoginFormComponent;
  }
}
