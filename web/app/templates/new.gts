import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';
import { service } from '@ember/service';
import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';
import SubmissionSteps from 'repository/components/submission-steps';

import dbLabel from 'repository/helpers/db-label';

import type CurrentUserService from 'repository/services/current-user';
import type { components } from 'schema/openapi';

// What each database takes. Only those a request can be created for here
// are offered (User#submittableDbs): BioProject and BioSample only where
// their records can be checked.
const DESCRIPTIONS: Record<components['schemas']['SubmittableDb'], string> = {
  st26: 'Patent sequence listings (ST.26 XML).',
  bioproject: 'Biological project metadata.',
  biosample: 'Biological sample metadata.',
};

export default class extends Component {
  @service declare currentUser: CurrentUserService;

  get cards() {
    return (this.currentUser.user?.submittableDbs ?? []).map((db) => ({ db, description: DESCRIPTIONS[db] }));
  }

  <template>
    {{pageTitle "New Submission"}}

    <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="New Submission")}} />

    <h1 class="display-6 mb-3">New Submission</h1>

    <SubmissionSteps @current={{1}} />

    <p class="text-body-secondary mb-4">Select the database you want to submit to.</p>

    <div class="row g-3">
      {{#each this.cards as |card|}}
        <div class="col-md-4">
          <LinkTo @route="db.requests.new" @model={{card.db}} class="card text-decoration-none h-100">
            <div class="card-body">
              <h2 class="card-title h5">{{dbLabel card.db}}</h2>
              <p class="card-text text-body-secondary mb-0">{{card.description}}</p>
            </div>
          </LinkTo>
        </div>
      {{else}}
        <p class="text-body-secondary" data-test-no-databases>
          The databases you can submit to could not be loaded. Reload the page to try again.
        </p>
      {{/each}}
    </div>
  </template>
}
