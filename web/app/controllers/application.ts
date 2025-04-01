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
  @tracked error?: Error;
  @tracked toastData: ToastData[] = [];

  errorModal?: Modal;
  toasts: Map<string, Toast> = new Map();

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

    this.toasts.set(el.id, toast);

    const handler = () => {
      this.toasts.delete(el.id);
      this.toastData = this.toastData.filter(({ id }) => id !== el.id);
    };

    el.addEventListener('hidden.bs.toast', handler);

    return () => {
      el.removeEventListener('hidden.bs.toast', handler);
    };
  });

  @action
  logout() {
    this.currentUser.logout();

    this.toast.show('Logged out.', 'success');
  }

  @action
  showErrorModal(error: Error) {
    this.error = error;

    if (this.errorModal) {
      this.errorModal.show();
    } else {
      alert(`Error:
Something went wrong. Please try again later.

${error.message}

Details:
${error.stack}`);
    }
  }

  @action showToast(data: Omit<ToastData, 'id'>) {
    const id = crypto.randomUUID();

    this.toastData = [...this.toastData, { id, ...data }];

    scheduleTask(this, 'render', () => {
      const toast = this.toasts.get(id);

      if (!toast) return;

      toast.show();
    });
  }
}
