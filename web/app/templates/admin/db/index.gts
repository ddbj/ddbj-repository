import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import dbLabel from 'repository/helpers/db-label';

import type { TOC } from '@ember/component/template-only';

export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label="Administration" route="admin")
      (hash label=(dbLabel @model.db))
    }}
  />

  <h1 class="display-6 mb-4">{{dbLabel @model.db}}</h1>

  <div class="row g-3">
    <div class="col-md-6">
      <LinkTo @route="admin.db.requests" @model={{@model.db}} class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">Requests</h2>
          <p class="card-text text-body-secondary mb-0">All users' submission requests in this database.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-6">
      <LinkTo @route="admin.db.submissions" @model={{@model.db}} class="card text-decoration-none h-100">
        <div class="card-body">
          <h2 class="card-title h5">Submissions</h2>
          <p class="card-text text-body-secondary mb-0">All users' applied submissions in this database.</p>
        </div>
      </LinkTo>
    </div>
  </div>
</template> satisfies TOC<{
  Args: {
    model: { db: string };
  };
}>;
