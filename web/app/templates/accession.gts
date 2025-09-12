import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { concat, uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { pageTitle } from 'ember-page-title';
import { task } from 'ember-concurrency';

import formatDatetime from 'repository/helpers/format-datetime';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';
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
  @service declare request: RequestService;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  submit = task({ drop: true }, async (e: Event) => {
    const { submission, accession } = this.args.model;

    e.preventDefault();

    await this.request.fetchWithModal(`/accessions/${accession.number}`, {
      method: 'PUT',
      body: new FormData(e.target as HTMLFormElement),
    });

    this.router.transitionTo('submission', submission);
    this.router.refresh();
    this.toast.show('Accession has been updated.', 'success');
  });

  <template>
    {{pageTitle (concat "Accession " @model.accession.number)}}

    <div class="mb-3">
      <LinkTo @route="submission" @model={{@model.submission}}>&laquo; Back to submission</LinkTo>
    </div>

    <h1 class="display-6 mb-4">Accession #{{@model.accession.number}}</h1>

    <dl class="d-flex flex-wrap row-gap-1 column-gap-5">
      <div>
        <dt>Number</dt>
        <dd>{{@model.accession.number}}</dd>
      </div>

      <div>
        <dt>Entry ID</dt>
        <dd>{{@model.accession.entry_id}}</dd>
      </div>

      <div>
        <dt>Version</dt>
        <dd>{{@model.accession.version}}</dd>
      </div>

      <div>
        <dt>Last updated</dt>
        <dd>{{formatDatetime @model.accession.last_updated_at}}</dd>
      </div>
    </dl>

    <form {{on "submit" this.submit.perform}}>
      <div class="card">
        {{#let (uniqueId) as |id|}}
          <div class="card-header">
            <label for={{id}}>
              DDBJ Record
            </label>
          </div>

          <div class="card-body">
            <input type="file" name="DDBJRecord" id={{id}} class="form-control" accept=".json" required />
          </div>
        {{/let}}
      </div>

      <button type="submit" class="btn btn-primary mt-3" disabled={{this.submit.isRunning}}>
        Submit
      </button>
    </form>
  </template>
}
