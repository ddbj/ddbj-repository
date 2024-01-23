import Controller from '@ember/controller';
import { action } from '@ember/object';
import { modifier } from 'ember-modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { task } from 'ember-concurrency';

import ENV from 'ddbj-repository/config/environment';
import downloadFile from 'ddbj-repository/utils/download-file';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ErrorModalService from 'ddbj-repository/services/error-modal';
import type Router from '@ember/routing/router';
import type ToastService from 'ddbj-repository/services/toast';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

const oneDay = 24 * 60 * 60 * 1000;

export default class ValidationsShowController extends Controller {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare router: Router;
  @service declare toast: ToastService;

  @tracked currentTime = new Date();

  declare model: Validation;

  tickCurrentTime = modifier(() => {
    const timer = setInterval(() => {
      this.currentTime = new Date();
    }, 1000);

    return () => {
      clearInterval(timer);
    };
  });

  get canSubmit() {
    return !this.cannotSubmitReason;
  }

  get cannotSubmitReason() {
    const { validity, finished_at, submission } = this.model;

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

  @action
  async downloadFile(url: string) {
    await downloadFile(url, this.currentUser);
  }

  submit = task({ drop: true }, async () => {
    const { id } = this.model;

    const res = await fetch(`${ENV.apiURL}/submissions`, {
      method: 'POST',

      headers: {
        'Content-Type': 'application/json',
        ...this.currentUser.authorizationHeader,
      },

      body: JSON.stringify({
        validation_id: id,
      }),
    });

    if (!res.ok) {
      this.errorModal.show(new Error(res.statusText));
    }

    const { id: submissionId } = await res.json();

    this.router.transitionTo('submissions.show', submissionId);
    this.toast.show('Validation was successfully submitted.', 'success');
  });
}
