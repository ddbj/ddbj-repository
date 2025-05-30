import Service from '@ember/service';
import { modifier } from 'ember-modifier';

import { Modal } from 'bootstrap';

export default class ErrorModalService extends Service {
  error?: Error;
  modal?: Modal;

  register = modifier((el: Element) => {
    this.modal = new Modal(el);

    const handler = () => {
      this.error = undefined;
    };

    el.addEventListener('hidden.bs.modal', handler);

    return () => {
      el.removeEventListener('hidden.bs.modal', handler);
    };
  });

  show(error: Error) {
    this.error = error;

    if (this.modal) {
      this.modal.show();
    } else {
      alert(`Error:
Something went wrong. Please try again later.

${error.message}

Details:
${error.stack}`);
    }
  }
}
