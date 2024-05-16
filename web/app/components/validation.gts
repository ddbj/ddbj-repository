import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import DetailsCount from 'ddbj-repository/components/details-count';
import ProgressLabel from 'ddbj-repository/components/progress-label';
import SubmitButton from 'ddbj-repository/components/submit-button';
import ValidityBadge from 'ddbj-repository/components/validity-badge';
import downloadFile from 'ddbj-repository/utils/download-file';
import formatDatetime from 'ddbj-repository/helpers/format-datetime';
import toJSON from 'ddbj-repository/helpers/to-json';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    showUser?: boolean;
    validation: Validation;
  };
}

export default class ValidationComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;

  @action
  async downloadFile(url: string) {
    await downloadFile(url, this.currentUser);
  }

  <template>
    <h1 class='display-6 mb-4'>Validation #{{@validation.id}}</h1>

    <div class='mb-3'>
      <SubmitButton @validation={{@validation}} />
    </div>

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

    <h2>Results</h2>

    <table class='table'>
      <thead>
        <tr>
          <th>Object</th>
          <th>File</th>
          <th>Validity</th>
          <th>Details</th>
        </tr>
      </thead>

      <tbody>
        {{#each @validation.results key='object_id' as |result|}}
          <tr>
            <td>{{result.object_id}}</td>

            <td>
              {{#if result.file}}
                <button
                  type='button'
                  class='btn btn-link p-0'
                  {{on 'click' (fn this.downloadFile result.file.url)}}
                >{{result.file.path}}</button>
              {{else}}
                -
              {{/if}}
            </td>

            <td><ValidityBadge @validity={{result.validity}} /></td>

            <td>
              <pre class='mb-0 py-1 text-pre-wrap'><code>{{#if result.details}}{{toJSON
                      result.details
                    }}{{else}}-{{/if}}</code></pre>
            </td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </template>
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    Validation: typeof ValidationComponent;
  }
}