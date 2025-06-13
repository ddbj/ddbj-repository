import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { task } from 'ember-concurrency';

import ObjectField from 'repository/components/object-field';

import type DB from 'repository/models/db';
import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';

interface Signature {
  Args: {
    db: DB;
  };
}

export default class NewValidationForm extends Component<Signature> {
  @service declare request: RequestService;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  create = task({ drop: true }, async (e: Event) => {
    const { db } = this.args;

    e.preventDefault();

    const res = await this.request.fetchWithModal(`/validations/via_file`, {
      method: 'POST',
      body: jsonToFormData(db.toJSON()),
    });

    const { id } = (await res.json()) as { id: string };

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

function jsonToFormData(obj: object, key?: string, formData = new FormData()) {
  if (Array.isArray(obj)) {
    for (const v of obj as object[]) {
      jsonToFormData(v, `${key}[]`, formData);
    }
  } else if (Object.prototype.toString.call(obj) === '[object Object]') {
    for (const [k, v] of Object.entries(obj) as [string, object][]) {
      jsonToFormData(v, key ? `${key}[${k}]` : k, formData);
    }
  } else {
    if (!key) throw new Error('key is empty');

    if (obj !== undefined) {
      // eslint-disable-next-line @typescript-eslint/no-base-to-string
      formData.append(key, obj instanceof Blob ? obj : obj.toString());
    }
  }

  return formData;
}
