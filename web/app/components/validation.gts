import { LinkTo } from '@ember/routing';
import { uniqueId } from '@ember/-internals/glimmer';

import DetailsCount from 'ddbj-repository/components/details-count';
import ProgressLabel from 'ddbj-repository/components/progress-label';
import ValidationResults from 'ddbj-repository/components/validation/results';
import ValidityBadge from 'ddbj-repository/components/validity-badge';
import formatDatetime from 'ddbj-repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    showUser?: boolean;
    validation: Validation;
  };
}

const ValidationComponent: TOC<Signature> = <template>
  <h1 class='display-6 mb-4'>Validation #{{@validation.id}}</h1>

  <dl class='d-flex flex-wrap row-gap-1 column-gap-5'>
    <div>
      <dt>ID</dt>
      <dd>{{@validation.id}}</dd>
    </div>

    {{#if @showUser}}
      <div>
        <dt>User</dt>
        <dd>{{@validation.user.uid}}</dd>
      </div>
    {{/if}}

    <div>
      <dt>DB</dt>
      <dd>{{@validation.db}}</dd>
    </div>

    <div>
      <dt>Created</dt>
      <dd>{{formatDatetime @validation.created_at}}</dd>
    </div>

    <div>
      <dt>Started</dt>

      <dd>
        {{#if @validation.started_at}}
          {{formatDatetime @validation.started_at}}
        {{else}}
          -
        {{/if}}
      </dd>
    </div>

    <div>
      <dt>Finished</dt>

      <dd>
        {{#if @validation.finished_at}}
          {{formatDatetime @validation.finished_at}}
        {{else}}
          -
        {{/if}}
      </dd>
    </div>

    <div>
      <dt>Progress</dt>
      <dd><ProgressLabel @progress={{@validation.progress}} /></dd>
    </div>

    <div>
      <dt>Validity</dt>

      <dd>
        <ValidityBadge @validity={{@validation.validity}} />
        <DetailsCount @results={{@validation.results}} />
      </dd>
    </div>

    <div>
      <dt>Submission</dt>

      <dd>
        {{#if @validation.submission}}
          <LinkTo @route='submissions.show' @model={{@validation.submission.id}}>
            {{@validation.submission.id}}
          </LinkTo>
        {{else}}
          -
        {{/if}}
      </dd>
    </div>
  </dl>

  <ul class='nav nav-tabs' id='tab' role='tablist'>
    <li class='nav-item' role='presentation'>
      <button
        class='nav-link active'
        id='results-tab'
        data-bs-toggle='tab'
        data-bs-target='#results-pane'
        type='button'
        role='tab'
        aria-controls='results-pane'
        aria-selected='true'
      >Results</button>
    </li>

    <li class='nav-item'>
      <button
        class='nav-link'
        id='submit-tab'
        data-bs-toggle='tab'
        data-bs-target='#submit-pane'
        type='button'
        role='tab'
        aria-controls='submit-pane'
        aria-selected='false'
      >Submit</button>
    </li>
  </ul>

  <div class='tab-content'>
    <div class='tab-pane show active' id='results-pane' role='tabpanel' aria-labelledby='results-tab' tabindex='0'>
      <ValidationResults @validation={{@validation}} />
    </div>

    <div class='tab-pane' id='submit-pane' role='tabpanel' aria-labelledby='submit-tab' tabindex='0'>
      <form class="p-3">
        <div class='mb-3'>
          <label class='form-label'>Visibility</label>

          <div>
            <div class='form-check form-check-inline'>
              {{#let (uniqueId) as |id|}}
                <input class='form-check-input' type='radio' name='visibility' value='public' id={{id}} required />
                <label class='form-check-label' for={{id}}>Public</label>
              {{/let}}
            </div>

            <div class='form-check form-check-inline'>
              {{#let (uniqueId) as |id|}}
                <input class='form-check-input' type='radio' name='visibility' value='private' id={{id}} required />
                <label class='form-check-label' for={{id}}>Private</label>
              {{/let}}
            </div>
          </div>
        </div>

        <button class='btn btn-primary' type='submit'>Submit</button>
      </form>
    </div>
  </div>
</template>;

export default ValidationComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    Validation: typeof ValidationComponent;
  }
}
