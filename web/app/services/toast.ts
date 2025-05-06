import Service from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { Toast } from 'bootstrap';
import { runTask } from 'ember-lifeline';

export interface Data {
  id: string;
  body: string;
  color: string;
}

export default class ToastService extends Service {
  @tracked data: Data[] = [];

  toasts: Map<string, Toast> = new Map();

  register(el: Element) {
    const toast = new Toast(el);

    this.toasts.set(el.id, toast);

    const handler = () => {
      this.toasts.delete(el.id);
      this.data = this.data.filter(({ id }) => id !== el.id);
    };

    el.addEventListener('hidden.bs.toast', handler);

    return () => {
      el.removeEventListener('hidden.bs.toast', handler);
    };
  }

  show(body: string, color: string) {
    const id = crypto.randomUUID();

    this.data = [...this.data, { id, body, color }];

    runTask(this, () => {
      const toast = this.toasts.get(id);

      if (!toast) return;

      toast.show();
    });
  }
}
