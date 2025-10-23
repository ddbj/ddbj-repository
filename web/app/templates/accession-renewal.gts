import Component from '@glimmer/component';
import { action } from '@ember/object';
import { LinkTo } from '@ember/routing';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import ProgressLabel from 'repository/components/progress-label';
import ValidityBadge from 'repository/components/validity-badge';

import AccessionSummary from 'repository/components/accession-summary';
import formatDatetime from 'repository/helpers/format-datetime';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
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

export default class extends Component<Signature> {
  @service declare request: RequestService;
  @service declare router: RouterService;

  @action
  async downloadFile(url: string) {
    await this.request.downloadFile(url);
  }

  @action
  backToAccession() {
    this.router.refresh();
    this.router.transitionTo('accession', this.args.model.accession.number);
  }

  <template>
    <div class="mb-3">
      <LinkTo @route="accession" @model={{@model.accession.number}} {{on "click" this.backToAccession}}>
        &laquo; Back to accession
      </LinkTo>
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

        <dd>
          <ValidityBadge @validity={{@model.renewal.validity}} />

          {{#if @model.renewal.validation_details.length}}
            <span class="badge bg-secondary">{{@model.renewal.validation_details.length}}</span>
          {{/if}}
        </dd>
      </div>
    </dl>

    {{#if @model.renewal.file}}
      <h3>File</h3>

      <button
        type="button"
        class="btn btn-link p-0 mb-3"
        {{on "click" (fn this.downloadFile @model.renewal.file.url)}}
      >{{@model.renewal.file.filename}}</button>
    {{/if}}

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
  </template>
}
