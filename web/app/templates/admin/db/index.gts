import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import NavCard from 'repository/components/nav-card';
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

  <h1 class="mb-6 text-3xl font-light">{{dbLabel @model.db}}</h1>

  <div class="grid gap-4 md:grid-cols-2">
    <NavCard
      @route="admin.db.requests"
      @model={{@model.db}}
      @title="Requests"
      @description="All users' submission requests in this database."
    />
    <NavCard
      @route="admin.db.submissions"
      @model={{@model.db}}
      @title="Submissions"
      @description="All users' applied submissions in this database."
    />
  </div>
</template> satisfies TOC<{
  Args: {
    model: { db: string };
  };
}>;
