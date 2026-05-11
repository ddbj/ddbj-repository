import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import NavCard from 'repository/components/nav-card';
import dbLabel from 'repository/helpers/db-label';

import type { TOC } from '@ember/component/template-only';

export default <template>
  <Breadcrumb @items={{array (hash label="Home" route="index") (hash label=(dbLabel @model.db))}} />

  <h1 class="mb-6 text-3xl font-light">{{dbLabel @model.db}}</h1>

  <div class="grid gap-4 md:grid-cols-3">
    <NavCard
      @route="db.requests.new"
      @model={{@model.db}}
      @title="Submit"
      @description="Upload a new DDBJ Record for validation."
    />
    <NavCard
      @route="db.requests"
      @model={{@model.db}}
      @title="Requests"
      @description="Submission requests in progress or awaiting application."
    />
    <NavCard
      @route="db.submissions"
      @model={{@model.db}}
      @title="Submissions"
      @description="Applied submissions and their accessions."
    />
  </div>
</template> satisfies TOC<{
  Args: {
    model: { db: string };
  };
}>;
