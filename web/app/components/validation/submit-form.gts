import Component from '@glimmer/component';
import { modifier } from 'ember-modifier';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { uniqueId } from '@ember/-internals/glimmer';

import { eq, gt, notEq } from 'ember-truth-helpers';
import { task } from 'ember-concurrency';

import type RequestService from 'repository/services/request';
import type Router from '@ember/routing/router';
import type ToastService from 'repository/services/toast';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    validation: Validation;
  };
}

export default class ValidationSubmitFormComponent extends Component<Signature> {
  @service declare request: RequestService;
  @service declare router: Router;
  @service declare toast: ToastService;

  @tracked elapsedFromValidationFinished = 0;

  calculateElapsed = modifier(() => {
    const finishedAt = new Date(this.args.validation.finished_at!);

    const timer = setInterval(() => {
      this.elapsedFromValidationFinished = new Date().getTime() - finishedAt.getTime();
    }, 1000);

    return () => {
      clearInterval(timer);
    };
  });

  submit = task({ drop: true }, async (e: Event) => {
    e.preventDefault();

    const formData = new FormData(e.target as HTMLFormElement);

    const res = await this.request.fetchWithModal('/submissions', {
      method: 'POST',
      body: formData,
    });

    if (!res) return;

    const { id: submissionId } = (await res.json()) as { id: string };

    this.router.transitionTo('submissions.show', submissionId);
    this.toast.show('Validation was successfully submitted.', 'success');
  });

  <template>
    <div {{this.calculateElapsed}}>
      {{#if @validation.submission}}
        <div class="alert alert-danger mt-3">You have already submitted this validation.</div>
      {{else if (notEq @validation.validity "valid")}}
        <div class="alert alert-danger mt-3">This validation is not valid.</div>
      {{else if (gt this.elapsedFromValidationFinished oneDay)}}
        <div class="alert alert-danger mt-3">This validation is expired.</div>
      {{else}}
        <form {{on "submit" this.submit.perform}} class="p-3">
          <input type="hidden" name="validation_id" value={{@validation.id}} />
          <input type="hidden" name="db" value={{@validation.db}} />

          <div class="mb-3">
            <label class="form-label">Visibility</label>

            <div>
              <div class="form-check form-check-inline">
                {{#let (uniqueId) as |id|}}
                  <input class="form-check-input" id={{id}} type="radio" name="visibility" value="public" required />
                  <label class="form-check-label" for={{id}}>Public</label>
                {{/let}}
              </div>

              <div class="form-check form-check-inline">
                {{#let (uniqueId) as |id|}}
                  <input class="form-check-input" id={{id}} type="radio" name="visibility" value="private" required />
                  <label class="form-check-label" for={{id}}>Private</label>
                {{/let}}
              </div>
            </div>
          </div>

          {{#if (eq @validation.db "BioProject")}}
            <div class="mb-3">
              <div class="form-check">
                <input type="hidden" name="umbrella" value="false" />

                {{#let (uniqueId) as |id|}}
                  <input class="form-check-input" id={{id}} type="checkbox" name="umbrella" value="true" />
                  <label class="form-check-label" for={{id}}>Umbrella project</label>
                {{/let}}
              </div>
            </div>
          {{/if}}

          <button class="btn btn-primary" type="submit">Submit</button>
        </form>
      {{/if}}
    </div>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'Validation::SubmitForm': typeof ValidationSubmitFormComponent;
  }
}

const oneDay = 24 * 60 * 60 * 1000;
