import Service from '@ember/service';
import { modifier } from 'ember-modifier';
import { trackedArray } from '@ember/reactive/collections';

import { Toast } from 'bootstrap';
import { runTask } from 'ember-lifeline';

export interface Data {
  id: string;
  body: string;
  color: string;
}

export default class ToastService extends Service {
  data = trackedArray<Data>();
  refs = new Map<string, Toast>();

  register = modifier((el: Element) => {
    const toast = new Toast(el);

    this.refs.set(el.id, toast);

    const handler = () => {
      this.refs.delete(el.id);
      this.data.splice(0, this.data.length, ...this.data.filter(({ id }) => id !== el.id));
    };

    el.addEventListener('hidden.bs.toast', handler);

    return () => {
      el.removeEventListener('hidden.bs.toast', handler);
    };
  });

  show(body: string, color: string) {
    const id = crypto.randomUUID();

    this.data.push({ id, body, color });

    runTask(this, () => {
      const toast = this.refs.get(id);

      if (!toast) return;

      toast.show();
    });
  }
}
