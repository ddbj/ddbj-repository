import Component from '@glimmer/component';
import { uniqueId } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { pageTitle } from 'ember-page-title';
import { task } from 'ember-concurrency';

import AccessionSummary from 'repository/components/accession-summary';

import type RequestService from 'repository/services/request';
import type RouterService from '@ember/routing/router-service';
import type ToastService from 'repository/services/toast';
import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];

interface Signature {
  Args: {
    model: {
      accession: Accession;
    };
  };
}

export default class extends Component<Signature> {
  @service declare request: RequestService;
  @service declare router: RouterService;
  @service declare toast: ToastService;

  submit = task({ drop: true }, async (e: Event) => {
    const { accession } = this.args.model;

    e.preventDefault();

    const res = await this.request.fetchWithModal(`/accessions/${accession.number}/accession_renewals`, {
      method: 'POST',
      body: new FormData(e.target as HTMLFormElement),
    });

    const { id } = (await res.json()) as { id: number };

    this.router.transitionTo('accession_renewal', id);
    this.toast.show('Accession renewal request submitted.', 'success');
  });

  <template>
    {{pageTitle "Renew"}}

    <AccessionSummary @accession={{@model.accession}} />

    <h2>Renew Accession</h2>

    <form {{on "submit" this.submit.perform}}>
      <div class="card">
        {{#let (uniqueId) as |id|}}
          <div class="card-header">
            <label for={{id}}>
              DDBJ Record
            </label>
          </div>

          <div class="card-body">
            <input type="file" name="accession_renewal[file]" id={{id}} class="form-control" accept=".json" required />
          </div>
        {{/let}}
      </div>

      <button type="submit" class="btn btn-primary mt-3" disabled={{this.submit.isRunning}}>
        Submit
      </button>
    </form>
  </template>
}
