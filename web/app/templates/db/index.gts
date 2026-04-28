import { LinkTo } from '@ember/routing';

import dbLabel from 'repository/helpers/db-label';

import type { TOC } from '@ember/component/template-only';

export default <template>
  <h1 class="display-6 mb-4">{{dbLabel @model.db}}</h1>

  <div class="row g-3">
    <div class="col-md-4">
      <LinkTo @route="db.requests.new" @model={{@model.db}} class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">Submit</h2>
          <p class="card-text text-body-secondary mb-0">Upload a new DDBJ Record for validation.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="db.requests" @model={{@model.db}} class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">Requests</h2>
          <p class="card-text text-body-secondary mb-0">Submission requests in progress or awaiting application.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="db.submissions" @model={{@model.db}} class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">Submissions</h2>
          <p class="card-text text-body-secondary mb-0">Applied submissions and their accessions.</p>
        </div>
      </LinkTo>
    </div>
  </div>
</template> satisfies TOC<{
  Args: {
    model: { db: string };
  };
}>;
