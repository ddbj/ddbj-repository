import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { Modal } from 'bootstrap';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default class ApplicationController extends Controller {
  @service declare currentUser: CurrentUserService;

  @tracked isLoading = false;
  @tracked error?: object;

  errorModal?: Modal;

  @action
  async logout() {
    await this.currentUser.logout();
  }

  @action
  setErrorModal(element: HTMLElement) {
    this.errorModal = new Modal(element);

    element.addEventListener('hidden.bs.modal', () => {
      this.error = undefined;
    });
  }

  @action
  showErrorModal(error: object) {
    this.error = error;

    if (this.errorModal) {
      this.errorModal.show();
    } else {
      const details = 'stack' in error ? error.stack : JSON.stringify(error, null, 2);

      alert(`Error:
Something went wrong. Please try again later.

${error}

Details:
${details}`);
    }
  }
}
