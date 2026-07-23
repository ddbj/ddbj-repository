import { LinkTo } from '@ember/routing';

import StatusBadge from 'repository/components/status-badge';
import ValidityBadge from 'repository/components/validity-badge';
import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

// Read-only reviewer view. Intentionally a separate template from
// request/index (no apply action, no messages) so the two can diverge; for
// now it shows the same request body plus a link to the accessions.
export default <template>
  <div class="alert alert-info py-2 small" role="note">
    You are viewing this submission request as a reviewer.
  </div>

  <h1 class="display-6 mb-4">#{{@model.request.id}}</h1>

  <dl class="horizontal">
    <dt>Created</dt>
    <dd>{{formatDatetime @model.request.created_at}}</dd>

    <dt>File</dt>

    <dd>
      <a href={{@model.request.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
        {{@model.request.ddbj_record.filename}}
      </a>
    </dd>

    <dt>Status</dt>
    <dd><StatusBadge @status={{@model.request.status}} /></dd>

    {{#if @model.request.error_message}}
      <dt>Error</dt>
      <dd>{{@model.request.error_message}}</dd>
    {{/if}}
  </dl>

  {{#if @model.request.validation}}
    <h2>Validation</h2>

    <dl class="horizontal">
      <dt>Progress</dt>
      <dd class="text-capitalize">{{@model.request.validation.progress}}</dd>

      <dt>Started</dt>
      <dd>{{formatDatetime @model.request.validation.created_at}}</dd>

      <dt>Finished</dt>
      <dd>{{formatDatetime @model.request.validation.finished_at}}</dd>

      <dt>Validity</dt>
      <dd><ValidityBadge @validity={{@model.request.validation.validity}} /></dd>
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
          {{#each @model.request.validation.details as |detail|}}
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

  {{#if @model.request.submission}}
    <h2 class="mt-4">Submission</h2>

    <dl class="horizontal">
      <dt>Source ID</dt>
      <dd>{{or @model.request.submission.source_id "-"}}</dd>

      <dt>Created</dt>
      <dd>{{formatDatetime @model.request.submission.created_at}}</dd>

      <dt>Updated</dt>
      <dd>{{formatDatetime @model.request.submission.updated_at}}</dd>

      <dt>DDBJ Record</dt>

      <dd>
        <a href={{@model.request.submission.ddbj_record.url}} target="_blank" rel="noopener noreferrer">
          {{@model.request.submission.ddbj_record.filename}}
        </a>
      </dd>

      <dt>Flatfile (NA)</dt>

      <dd>
        {{#if @model.request.submission.flatfile_na}}
          <a href={{@model.request.submission.flatfile_na.url}} target="_blank" rel="noopener noreferrer">
            {{@model.request.submission.flatfile_na.filename}}
          </a>
        {{else}}
          -
        {{/if}}
      </dd>

      <dt>Flatfile (AA)</dt>

      <dd>
        {{#if @model.request.submission.flatfile_aa}}
          <a href={{@model.request.submission.flatfile_aa.url}} target="_blank" rel="noopener noreferrer">
            {{@model.request.submission.flatfile_aa.filename}}
          </a>
        {{else}}
          -
        {{/if}}
      </dd>

      <dt>Accessions</dt>

      <dd>
        <LinkTo
          @route="review.accessions"
          @model={{@model.token}}
        >{{@model.request.submission.accessions_count}}</LinkTo>
      </dd>
    </dl>
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: {
      token: string;
      request: components['schemas']['SubmissionRequest'];
    };
  };
}>;
