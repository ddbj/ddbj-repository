import Component from '@glimmer/component';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/-internals/glimmer';

import { task } from 'ember-concurrency';

import ENV from 'ddbj-repository/config/environment';
import { safeFetchWithModal } from 'ddbj-repository/utils/safe-fetch';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ErrorModalService from 'ddbj-repository/services/error-modal';
import type Router from '@ember/routing/router';
import type ToastService from 'ddbj-repository/services/toast';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    validation: Validation;
  };
}

export default class ValidationSubmitFormComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare router: Router;
  @service declare toast: ToastService;

  submit = task({ drop: true }, async (e) => {
    e.preventDefault();

    const formData = new FormData(e.target);
    const { id } = this.args.validation;

    formData.set('submission[validation_id]', id.toString());

    const res = await safeFetchWithModal(
      `${ENV.apiURL}/submissions`,
      {
        method:  'POST',
        headers: this.currentUser.authorizationHeader,
        body:    formData
      },
      this.errorModal,
    );

    const { id: submissionId } = await res.json();

    this.router.transitionTo('submissions.show', submissionId);
    this.toast.show('Validation was successfully submitted.', 'success');
  });

  <template>
    <form {{on 'submit' this.submit.perform}} class="p-3">
      <div class='mb-3'>
        <label class='form-label'>Visibility</label>

        <div>
          <div class='form-check form-check-inline'>
            {{#let (uniqueId) as |id|}}
              <input class='form-check-input' type='radio' name='submission[visibility]' value='public' id={{id}} required />
              <label class='form-check-label' for={{id}}>Public</label>
            {{/let}}
          </div>

          <div class='form-check form-check-inline'>
            {{#let (uniqueId) as |id|}}
              <input class='form-check-input' type='radio' name='submission[visibility]' value='private' id={{id}} required />
              <label class='form-check-label' for={{id}}>Private</label>
            {{/let}}
          </div>
        </div>
      </div>

      <button class='btn btn-primary' type='submit'>Submit</button>
    </form>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'Validation::SubmitForm': typeof ValidationSubmitFormComponent;
  }
}
