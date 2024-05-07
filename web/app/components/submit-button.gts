import Component from '@glimmer/component';
import { modifier } from 'ember-modifier';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { task } from 'ember-concurrency';
import { tracked } from '@glimmer/tracking';

import { eq, not, or } from 'ember-truth-helpers';

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

const oneDay = 24 * 60 * 60 * 1000;

export default class SubmitButtonComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare router: Router;
  @service declare toast: ToastService;

  @tracked currentTime = new Date();

  tickCurrentTime = modifier(() => {
    const timer = setInterval(() => {
      this.currentTime = new Date();
    }, 1000);

    return () => {
      clearInterval(timer);
    };
  });

  submit = task({ drop: true }, async () => {
    const { id } = this.args.validation;

    const res = await safeFetchWithModal(
      `${ENV.apiURL}/submissions`,
      {
        method: 'POST',

        headers: {
          'Content-Type': 'application/json',
          ...this.currentUser.authorizationHeader,
        },

        body: JSON.stringify({
          validation_id: id,
        }),
      },
      this.errorModal,
    );

    const { id: submissionId } = await res.json();

    this.router.transitionTo('submissions.show', submissionId);
    this.toast.show('Validation was successfully submitted.', 'success');
  });

  cancel = task({ drop: true }, async () => {
    const { id } = this.args.validation;

    await safeFetchWithModal(
      `${ENV.apiURL}/validations/${id}`,
      {
        method: 'DELETE',
        headers: this.currentUser.authorizationHeader,
      },
      this.errorModal,
    );

    // @ts-expect-error https://api.emberjs.com/ember/5.5/classes/RouterService/methods/refresh?anchor=refresh
    this.router.refresh();
    this.toast.show('Validation has been canceled.', 'success');
  });

  get canSubmit() {
    return !this.cannotSubmitReason;
  }

  get cannotSubmitReason() {
    const { validity, finished_at, submission } = this.args.validation!;

    if (submission) {
      return 'Validation is already submitted.';
    } else if (validity !== 'valid') {
      return 'Validation must be valid.';
    } else if (this.currentTime.getTime() - new Date(finished_at!).getTime() >= oneDay) {
      return 'Validation must finished in 24 hours.';
    } else {
      return undefined;
    }
  }

  <template>
    {{#if (or (eq @validation.progress 'waiting') (eq @validation.progress 'running'))}}
      <button
        type='button'
        class='btn btn-danger'
        disabled={{this.cancel.isRunning}}
        {{on 'click' this.cancel.perform}}
      >
        Cancel
      </button>
    {{else}}
      <div class='d-flex align-items-center gap-3' {{this.tickCurrentTime}}>
        <button
          type='button'
          class='btn btn-primary'
          disabled={{or (not this.canSubmit) this.submit.isRunning}}
          {{on 'click' this.submit.perform}}
        >
          Submit
        </button>

        {{#if this.cannotSubmitReason}}
          <div class='text-danger'>{{this.cannotSubmitReason}}</div>
        {{/if}}
      </div>
    {{/if}}
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    SubmitButton: typeof SubmitButtonComponent;
  }
}
