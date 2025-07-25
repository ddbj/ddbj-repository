import Component from '@glimmer/component';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { eq } from 'ember-truth-helpers';

import { task } from 'ember-concurrency';

import ObjectField from 'repository/components/object-field';

import type DB from 'repository/models/db';
import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';

interface Signature {
  Args: {
    db: DB;
    type: "file" | "ddbjRecord";
    onTypeChange: (type: "file" | "ddbjRecord") => void;
  };
}

export default class NewValidationForm extends Component<Signature> {
  @service declare request: RequestService;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  create = task({ drop: true }, async (e: Event) => {
    const { db, type } = this.args;

    e.preventDefault();

    const url = type === "file" ? "/validations/via_file" : "/validations/via_ddbj_record";

    const res = await this.request.fetchWithModal(url, {
      method: 'POST',
      body: jsonToFormData(db.toJSON(type)),
    });

    const { id } = (await res.json()) as { id: string };

    this.router.transitionTo('validations.show', id);
    this.toast.show('Validation has started.', 'success');
  });

  <template>
    <form {{on "submit" this.create.perform}}>
      {{#if (eq @db.schema.id "Trad")}}
        <div class="mb-3">
          <ul class="nav nav-tabs" id="tradTab" role="tablist">
            <li class="nav-item" role="presentation">
              <button
                class="nav-link active"
                id="file"
                data-bs-toggle="tab"
                data-bs-target="#file-tab-pane"
                type="button"
                role="tab"
                aria-controls="file-tab-pane"
                aria-selected="true"
                {{on "click" (fn @onTypeChange "file")}}
              >File</button>
            </li>
            <li class="nav-item" role="presentation">
              <button
                class="nav-link"
                id="ddbj-record"
                data-bs-toggle="tab"
                data-bs-target="#ddbj-record-tab-pane"
                type="button"
                role="tab"
                aria-controls="ddbj-record-tab-pane"
                aria-selected="false"
                {{on "click" (fn @onTypeChange "ddbjRecord")}}
              >DDBJ Record</button>
            </li>
          </ul>
          <div class="tab-content mt-3" id="tradTabContent">
            <div class="tab-pane fade show active" role="tabpanel">
              {{#if (eq @type "file")}}
                {{#each @db.objs.file as |obj|}}
                  <ObjectField @obj={{obj}} />
                {{/each}}
              {{else}}
                {{#each @db.objs.ddbjRecord as |obj|}}
                  <ObjectField @obj={{obj}} />
                {{/each}}
              {{/if}}
            </div>
          </div>
        </div>
      {{else}}
        {{#each @db.objs.file as |obj|}}
          <ObjectField @obj={{obj}} />
        {{/each}}
      {{/if}}

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
