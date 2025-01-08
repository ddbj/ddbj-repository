import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { task } from 'ember-concurrency';

import ENV from 'ddbj-repository/config/environment';
import ObjectField from 'ddbj-repository/components/object-field';
import { safeFetchWithModal } from 'ddbj-repository/utils/safe-fetch';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type DB from 'ddbj-repository/models/db';
import type ErrorModalService from 'ddbj-repository/services/error-modal';
import type Router from '@ember/routing/router';
import type ToastService from 'ddbj-repository/services/toast';

interface Signature {
  Args: {
    db: DB;
  };
}

export default class NewValidationFormComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare router: Router;
  @service declare toast: ToastService;

  create = task({ drop: true }, async (e: Event) => {
    const { db } = this.args;

    e.preventDefault();

    const res = await safeFetchWithModal(
      `${ENV.apiURL}/validations/via-file`,
      {
        method: 'POST',
        headers: this.currentUser.authorizationHeader,
        body: jsonToFormData(db.toJSON()),
      },
      this.errorModal,
    );

    const { id } = await res.json();

    this.router.transitionTo('validations.show', id);
    this.toast.show('Validation has started.', 'success');
  });

  <template>
    <form {{on "submit" this.create.perform}}>
      {{#each @db.objs as |obj|}}
        <ObjectField @obj={{obj}} />
      {{/each}}

      <button type="submit" class="btn btn-primary" disabled={{this.create.isRunning}}>
        {{#if this.create.isRunning}}
          <span class="spinner-border spinner-border-sm" aria-hidden="true"></span>
          <span role="status">Uploading...</span>
        {{else}}
          Validate
        {{/if}}
      </button>
    </form>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    NewValidationForm: typeof NewValidationFormComponent;
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
