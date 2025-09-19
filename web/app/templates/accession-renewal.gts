import { LinkTo } from '@ember/routing';

import ProgressLabel from 'repository/components/progress-label';
import ValidityBadge from 'repository/components/validity-badge';

import AccessionSummary from 'repository/components/accession-summary';
import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];
type Renewal = components['schemas']['AccessionRenewal'];

interface Signature {
  Args: {
    model: {
      accession: Accession;
      renewal: Renewal;
    };
  };
}

export default <template>
  <div class="mb-3">
    <LinkTo @route="accession" @model={{@model.accession.number}}>&laquo; Back to accession</LinkTo>
  </div>

  <AccessionSummary @accession={{@model.accession}} />

  <h2>Renewal #{{@model.renewal.id}}</h2>

  <dl class="d-flex flex-wrap row-gap-1 column-gap-5">
    <div>
      <dt>Created</dt>
      <dd>{{formatDatetime @model.renewal.created_at}}</dd>
    </div>

    <div>
      <dt>Started</dt>

      <dd>
        {{#if @model.renewal.started_at}}
          {{formatDatetime @model.renewal.started_at}}
        {{else}}
          -
        {{/if}}
      </dd>
    </div>

    <div>
      <dt>Finished</dt>

      <dd>
        {{#if @model.renewal.finished_at}}
          {{formatDatetime @model.renewal.finished_at}}
        {{else}}
          -
        {{/if}}
      </dd>
    </div>

    <div>
      <dt>Progress</dt>
      <dd><ProgressLabel @progress={{@model.renewal.progress}} /></dd>
    </div>

    <div>
      <dt>Validity</dt>
      <dd><ValidityBadge @validity={{@model.renewal.validity}} /></dd>
    </div>
  </dl>

  {{#if @model.renewal.validation_details.length}}
    <h3>Validation Results</h3>

    <table class="table">
      <thead>
        <tr>
          <th>Severity</th>
          <th>Message</th>
        </tr>
      </thead>

      <tbody>
        {{#each @model.renewal.validation_details as |detail|}}
          <tr>
            <td>{{detail.severity}}</td>
            <td>{{detail.message}}</td>
          </tr>
        {{/each}}
      </tbody>
    </table>
  {{/if}}
</template> satisfies TOC<Signature>;
