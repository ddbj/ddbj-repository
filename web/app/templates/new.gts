import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';
import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';
import SubmissionSteps from 'repository/components/submission-steps';

import dbLabel, { SUBMITTABLE_DBS } from 'repository/helpers/db-label';

import type { TOC } from '@ember/component/template-only';

// What each database takes. Only those a request can be created for are
// offered: a BioProject or BioSample record cannot be applied yet.
const DESCRIPTIONS: Record<string, string> = {
  st26: 'Patent sequence listings (ST.26 XML).',
  bioproject: 'Biological project metadata.',
  biosample: 'Biological sample metadata.',
};

const CARDS = SUBMITTABLE_DBS.map((db) => ({ db, description: DESCRIPTIONS[db] }));

export default <template>
  {{pageTitle "New Submission"}}

  <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="New Submission")}} />

  <h1 class="display-6 mb-3">New Submission</h1>

  <SubmissionSteps @current={{1}} />

  <p class="text-body-secondary mb-4">Select the database you want to submit to.</p>

  <div class="row g-3">
    {{#each CARDS as |card|}}
      <div class="col-md-4">
        <LinkTo @route="db.requests.new" @model={{card.db}} class="card text-decoration-none h-100">
          <div class="card-body">
            <h2 class="card-title h5">{{dbLabel card.db}}</h2>
            <p class="card-text text-body-secondary mb-0">{{card.description}}</p>
          </div>
        </LinkTo>
      </div>
    {{/each}}
  </div>
</template> satisfies TOC<{ Args: object }>;
