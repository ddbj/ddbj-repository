import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';
import { pageTitle } from 'ember-page-title';

import Breadcrumb from 'repository/components/breadcrumb';

import type { TOC } from '@ember/component/template-only';

export default <template>
  {{pageTitle "New Submission"}}

  <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="New Submission")}} />

  <h1 class="display-6 mb-4">New Submission</h1>

  <p class="text-body-secondary mb-4">Select the database you want to submit to.</p>

  <div class="row g-3">
    <div class="col-md-4">
      <LinkTo @route="db.requests.new" @model="st26" class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">ST.26</h2>
          <p class="card-text text-body-secondary mb-0">Patent sequence listings (ST.26 XML).</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="db.requests.new" @model="bioproject" class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">BioProject</h2>
          <p class="card-text text-body-secondary mb-0">Biological project metadata.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="db.requests.new" @model="biosample" class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">BioSample</h2>
          <p class="card-text text-body-secondary mb-0">Biological sample metadata.</p>
        </div>
      </LinkTo>
    </div>
  </div>
</template> satisfies TOC<{ Args: object }>;
