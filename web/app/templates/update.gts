import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { eq } from 'ember-truth-helpers';

import formatDatetime from 'repository/helpers/format-datetime';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';

export default class extends Component {
  @service declare request: RequestService;
  @service declare router: RouterService;

  @action
  async apply() {
    const { model } = this.args;

    await this.request.fetchWithModal(`/submission_updates/${model.id}/submission`, {
      method: 'PATCH',
    });

    this.router.refresh();
  }

  <template>
    <h1 class="display-6 mb-4">Update-{{@model.id}}</h1>

    <dl class="horizontal">
      <dt>Submission</dt>

      <dd>
        <LinkTo @route="submission" @model={{@model.submission.id}}>Submission-{{@model.submission.id}}</LinkTo>
      </dd>

      <dt>Created</dt>
      <dd>{{formatDatetime @model.created_at}}</dd>

      <dt>File</dt>

      <dd>
        <a href={{@model.ddbj_record.url}} target="_blank" rel="noopener noreferrer">{{@model.ddbj_record.filename}}</a>
      </dd>

      <dt>Status</dt>
      <dd>{{@model.status}}</dd>

      {{#if @model.error_message}}
        <dt>Error</dt>
        <dd>{{@model.error_message}}</dd>
      {{/if}}
    </dl>

    <h2>Validation</h2>

    <dl class="horizontal">
      <dt>Progress</dt>
      <dd>{{@model.validation.progress}}</dd>

      <dt>Started</dt>

      <dd>
        {{formatDatetime @model.validation.created_at}}
      </dd>

      <dt>Finished</dt>

      <dd>
        {{#if @model.validation.finished_at}}
          {{formatDatetime @model.validation.finished_at}}
        {{else}}
          -
        {{/if}}
      </dd>

      <dt>Validity</dt>
      <dd>{{@model.validation.validity}}</dd>
    </dl>

    {{#if @model.diff }}
      <h2>Diff</h2>
      <pre>{{@model.diff}}</pre>
    {{/if}}

    <details class="my-3">
      <summary>Details</summary>

      <table class="table">
        <thead>
          <tr>
            <th>Filename</th>
            <th>Entry ID</th>
            <th>Code</th>
            <th>Severity</th>
            <th>Message</th>
          </tr>
        </thead>

        <tbody>
          {{#each @model.validation.details as |detail|}}
            <tr>
              <td>{{detail.filename}}</td>
              <td>{{detail.entry_id}}</td>
              <td>{{detail.code}}</td>
              <td>{{detail.severity}}</td>
              <td>{{detail.message}}</td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    </details>

    {{#if (eq @model.status "ready_to_apply")}}
      <div class="my-3">
        <button type="button" class="btn btn-primary" {{on "click" this.apply}}>
          Apply
        </button>
      </div>
    {{/if}}
  </template>
}
