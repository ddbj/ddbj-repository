import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { concat, fn, hash } from '@ember/helper';
import { getOwner } from '@ember/owner';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { eq } from 'ember-truth-helpers';
import { pageTitle } from 'ember-page-title';

import ProgressLabel from 'repository/components/progress-label';
import ResultBadge from 'repository/components/result-badge';
import formatDatetime from 'repository/helpers/format-datetime';

import type RequestService from 'repository/services/request';
import type SubmissionsIndexController from 'repository/controllers/submissions/index';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

interface Signature {
  Args: {
    model: Submission;
  };
}

export default class extends Component<Signature> {
  @service declare request: RequestService;

  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:submissions.index') as SubmissionsIndexController;

    return controller?.pageBefore;
  }

  @action
  async downloadFile(url: string) {
    await this.request.downloadFile(url);
  }

  <template>
    {{pageTitle (concat "Submission-" @model.id)}}

    <div class="mb-3">
      <LinkTo @route="submissions.index" @query={{hash page=this.indexPage}}>&laquo; Back to index</LinkTo>
    </div>

    <h1 class="display-6 mb-4">Submission-{{@model.id}}</h1>

    <dl class="d-flex flex-wrap row-gap-1 column-gap-5">
      <div>
        <dt>ID</dt>
        <dd>{{@model.id}}</dd>
      </div>

      <div>
        <dt>DB</dt>
        <dd>{{@model.validation.db}}</dd>
      </div>

      <div>
        <dt>Created</dt>
        <dd>{{formatDatetime @model.created_at}}</dd>
      </div>

      <div>
        <dt>Started</dt>

        <dd>
          {{#if @model.started_at}}
            {{formatDatetime @model.started_at}}
          {{else}}
            -
          {{/if}}
        </dd>
      </div>

      <div>
        <dt>Finished</dt>

        <dd>
          {{#if @model.finished_at}}
            {{formatDatetime @model.finished_at}}
          {{else}}
            -
          {{/if}}
        </dd>
      </div>

      <div>
        <dt>Progress</dt>
        <dd><ProgressLabel @progress={{@model.progress}} /></dd>
      </div>

      <div>
        <dt>Result</dt>

        <dd>
          <ResultBadge @result={{@model.result}} />
        </dd>
      </div>

      <div>
        <dt>Validation</dt>

        <dd>
          <LinkTo @route="validation" @model={{@model.validation}}>Validation-{{@model.validation.id}}</LinkTo>
        </dd>
      </div>

      <div>
        <dt>Visibility</dt>
        <dd>{{@model.visibility}}</dd>
      </div>

      {{#if (eq @model.validation.db "BioProject")}}
        <div>
          <dt>Umbrella</dt>
          {{! @glint-expect-error }}
          <dd>{{@model.umbrella}}</dd>
        </div>
      {{/if}}
    </dl>

    {{#if @model.error_message}}
      <p class="alert alert-danger">{{@model.error_message}}</p>
    {{/if}}

    <h2>Objects</h2>

    <table class="table">
      <thead>
        <tr>
          <th>ID</th>
          <th>Files</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.validation.objects key="id" as |obj|}}
          <tr>
            <td>{{obj.id}}</td>

            <td>
              <ul class="list-unstyled mb-0">
                {{#each obj.files as |file|}}
                  <li>
                    <button
                      type="button"
                      class="btn btn-link p-0"
                      {{on "click" (fn this.downloadFile file.url)}}
                    >{{file.path}}</button>
                  </li>
                {{/each}}
              </ul>
            </td>
          </tr>
        {{/each}}
      </tbody>
    </table>

    <h2>Accessions</h2>

    <table class="table">
      <thead>
        <tr>
          <th>Number</th>
          <th>Entry ID</th>
          <th>Version</th>
          <th>Last updated</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.accessions as |accession|}}
          <tr>
            <td>
              <LinkTo @route="accession" @model={{accession.number}}>
                {{accession.number}}
              </LinkTo>
            </td>

            <td>{{accession.entry_id}}</td>
            <td>{{accession.version}}</td>
            <td>{{formatDatetime accession.last_updated_at}}</td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  </template>
}
