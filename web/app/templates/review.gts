import StatusBadge from 'repository/components/status-badge';
import ValidityBadge from 'repository/components/validity-badge';
import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

// Read-only reviewer view. Intentionally a separate template from
// request/index (no apply action, no messages, no authenticated links) so
// the two can diverge; for now it shows the same request body.
export default <template>
  <div class="alert alert-info py-2 small" role="note">
    You are viewing this submission request as a reviewer.
  </div>

  <h1 class="display-6 mb-4">#{{@model.id}}</h1>

  <dl class="horizontal">
    <dt>Created</dt>
    <dd>{{formatDatetime @model.created_at}}</dd>

    <dt>File</dt>

    <dd>
      <a href={{@model.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
        {{@model.ddbj_record.filename}}
      </a>
    </dd>

    <dt>Status</dt>
    <dd><StatusBadge @status={{@model.status}} /></dd>

    {{#if @model.error_message}}
      <dt>Error</dt>
      <dd>{{@model.error_message}}</dd>
    {{/if}}
  </dl>

  {{#if @model.validation}}
    <h2>Validation</h2>

    <dl class="horizontal">
      <dt>Progress</dt>
      <dd class="text-capitalize">{{@model.validation.progress}}</dd>

      <dt>Started</dt>
      <dd>{{formatDatetime @model.validation.created_at}}</dd>

      <dt>Finished</dt>
      <dd>{{formatDatetime @model.validation.finished_at}}</dd>

      <dt>Validity</dt>
      <dd><ValidityBadge @validity={{@model.validation.validity}} /></dd>
    </dl>

    <details class="my-3">
      <summary>Details</summary>

      <table class="table">
        <thead>
          <tr>
            <th>Entry ID</th>
            <th>Code</th>
            <th>Severity</th>
            <th>Message</th>
          </tr>
        </thead>

        <tbody>
          {{#each @model.validation.details as |detail|}}
            <tr>
              <td>{{detail.entry_id}}</td>
              <td>{{detail.code}}</td>
              <td>{{detail.severity}}</td>
              <td>{{detail.message}}</td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    </details>
  {{/if}}

  {{#if @model.submission}}
    <h2 class="mt-4">Submission</h2>

    <dl class="horizontal">
      <dt>Source ID</dt>
      <dd>{{or @model.submission.source_id "-"}}</dd>

      <dt>Created</dt>
      <dd>{{formatDatetime @model.submission.created_at}}</dd>

      <dt>Updated</dt>
      <dd>{{formatDatetime @model.submission.updated_at}}</dd>

      <dt>DDBJ Record</dt>

      <dd>
        <a href={{@model.submission.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
          {{@model.submission.ddbj_record.filename}}
        </a>
      </dd>

      <dt>Flatfile (NA)</dt>

      <dd>
        {{#if @model.submission.flatfile_na}}
          <a href={{@model.submission.flatfile_na.url}} target="_blank" rel="noopener noreferrer">
            {{@model.submission.flatfile_na.filename}}
          </a>
        {{else}}
          -
        {{/if}}
      </dd>

      <dt>Flatfile (AA)</dt>

      <dd>
        {{#if @model.submission.flatfile_aa}}
          <a href={{@model.submission.flatfile_aa.url}} target="_blank" rel="noopener noreferrer">
            {{@model.submission.flatfile_aa.filename}}
          </a>
        {{else}}
          -
        {{/if}}
      </dd>
    </dl>
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: components['schemas']['SubmissionRequest'];
  };
}>;
