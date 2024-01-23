import Component from '@glimmer/component';
import { service } from '@ember/service';

import { task } from 'ember-concurrency';

import ENV from 'ddbj-repository/config/environment';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type DB from 'ddbj-repository/models/db';
import type ErrorModalService from 'ddbj-repository/services/error-modal';
import type Router from '@ember/routing/router';

interface Signature {
  Args: {
    db: DB;
  };
}

export default class CreateValidationFormComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare router: Router;

  create = task({ drop: true }, async (e: Event) => {
    const { db } = this.args;

    e.preventDefault();

    const res = await fetch(`${ENV.apiURL}/validations/via-file`, {
      method: 'POST',
      headers: this.currentUser.authorizationHeader,
      body: jsonToFormData(db.toJSON()),
    });

    if (!res.ok) {
      this.errorModal.show(new Error(res.statusText));
    }

    const { id } = await res.json();

    this.router.transitionTo('validations.show', id);
  });
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    CreateValidationForm: typeof CreateValidationFormComponent;
  }
}

function jsonToFormData(obj: object, key?: string, formData = new FormData()) {
  if (Array.isArray(obj)) {
    for (const v of obj) {
      jsonToFormData(v, `${key}[]`, formData);
    }
  } else if (Object.prototype.toString.call(obj) === '[object Object]') {
    for (const [k, v] of Object.entries(obj)) {
      jsonToFormData(v, key ? `${key}[${k}]` : k, formData);
    }
  } else {
    if (!key) throw new Error('key is empty');

    if (obj !== undefined) {
      formData.append(key, obj instanceof Blob ? obj : obj.toString());
    }
  }

  return formData;
}
