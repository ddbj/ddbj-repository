import Controller from '@ember/controller';
import { action } from '@ember/object';
import { modifier } from 'ember-modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { Modal, Toast } from 'bootstrap';
import { scheduleTask } from 'ember-lifeline';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ToastService from 'ddbj-repository/services/toast';

export interface ToastData {
  id: string;
  body: string;
  bgColor: string;
}

export default class ApplicationController extends Controller {
  @service declare currentUser: CurrentUserService;
  @service declare toast: ToastService;

  @tracked isLoading = false;
  @tracked error?: object;
  @tracked toastData: ToastData[] = [];

  errorModal?: Modal;
  toasts: Map<Element, Toast> = new Map();

  setErrorModal = modifier((el) => {
    this.errorModal = new Modal(el);

    const handler = () => {
      this.error = undefined;
    };

    el.addEventListener('hidden.bs.modal', handler);

    return () => {
      el.removeEventListener('hidden.bs.modal', handler);
    };
  });

  setToast = modifier((el) => {
    const toast = new Toast(el);

    this.toasts.set(el, toast);

    const handler = () => {
      this.toasts.delete(el);
      this.toastData = this.toastData.filter(({ id }) => id !== el.id);
    };

    el.addEventListener('hidden.bs.toast', handler);

    return () => {
      el.removeEventListener('hidden.bs.toast', handler);
    };
  });

  @action
  async logout() {
    await this.currentUser.logout();

    this.toast.show('Logged out.', 'success');
  }

  @action
  showErrorModal(error: Error | object) {
    this.error = error;

    if (this.errorModal) {
      this.errorModal.show();
    } else {
      const details = error instanceof Error ? error.stack : JSON.stringify(error, null, 2);

      alert(`Error:
Something went wrong. Please try again later.

${error}

Details:
${details}`);
    }
  }

  @action showToast(data: Omit<ToastData, 'id'>) {
    const id = crypto.randomUUID();

    this.toastData = [...this.toastData, { id, ...data }];

    scheduleTask(this, 'render', () => {
      const entry = [...this.toasts].find(([el]) => el.id === id);

      if (!entry) return;

      const [, toast] = entry;

      toast.show();
    });
  }
}
