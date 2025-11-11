import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';

import AccessionSummary from 'repository/components/accession-summary';
// import ProgressLabel from 'repository/components/progress-label';
// import ValidityBadge from 'repository/components/validity-badge';
// import formatDate from 'repository/helpers/format-datetime';

import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];
type Submission = components['schemas']['Submission'];

interface Signature {
  Args: {
    model: {
      submission: Submission;
      accession: Accession;
    };
  };
}

export default class extends Component<Signature> {
  get renewals() {
    const { model } = this.args;

    return model.accession.renewals!.sort((x, y) => y.id - x.id);
  }

  <template>
    <div class="mb-3">
      <LinkTo @route="submission" @model={{@model.submission}}>&laquo; Back to submission</LinkTo>
    </div>

    <AccessionSummary @accession={{@model.accession}} />

    {{!--
    <h2>Renewals</h2>

    <LinkTo @route="accession_renewals.new" class="btn btn-primary mb-3">
      Renew Accession
    </LinkTo>

    {{#if this.renewals}}
      <table class="table">
        <thead>
          <tr>
            <th>ID</th>
            <th>Created</th>
            <th>Started</th>
            <th>Finished</th>
            <th>Progress</th>
            <th>Validity</th>
          </tr>
        </thead>

        <tbody>
          {{#each this.renewals as |renewal|}}
            <tr>
              <td>
                <LinkTo @route="accession_renewal" @model={{renewal.id}}>
                  #{{renewal.id}}
                </LinkTo>
              </td>

              <td>{{formatDate renewal.created_at}}</td>

              <td>
                {{#if renewal.started_at}}
                  {{formatDate renewal.started_at}}
                {{else}}
                  -
                {{/if}}
              </td>

              <td>
                {{#if renewal.finished_at}}
                  {{formatDate renewal.finished_at}}
                {{else}}
                  -
                {{/if}}
              </td>

              <td><ProgressLabel @progress={{renewal.progress}} /></td>

              <td>
                <ValidityBadge @validity={{renewal.validity}} />

                {{#if renewal.validation_details.length}}
                  <span class="badge bg-secondary">{{renewal.validation_details.length}}</span>
                {{/if}}
              </td>
            </tr>
          {{/each}}
        </tbody>
      </table>
    {{/if}}
    --}}
  </template>
}
