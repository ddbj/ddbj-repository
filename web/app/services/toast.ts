import Service from '@ember/service';
import { modifier } from 'ember-modifier';

import { Toast } from 'bootstrap';
import { TrackedArray } from 'tracked-built-ins';
import { runTask } from 'ember-lifeline';

export interface Data {
  id: string;
  body: string;
  color: string;
}

export default class ToastService extends Service {
  data = new TrackedArray<Data>();
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
