import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';
import Pagination from 'repository/components/pagination';

import type Controller from 'repository/controllers/db/submissions/index';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <Breadcrumb
    @items={{array
      (hash label="Home" route="index")
      (hash label=(dbLabel @model.db) route="db" models=(array @model.db))
      (hash label="Submissions")
    }}
  />

  <h1 class="display-6 mb-4">Submissions ({{dbLabel @model.db}})</h1>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>ID</th>
        <th>Created</th>
        <th>Updated</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.submissions as |submission|}}
        <tr>
          <td>
            <LinkTo @route="submission" @models={{array @model.db submission.id}}>
              Submission-{{submission.id}}
            </LinkTo>
          </td>

          <td>{{formatDatetime submission.created_at}}</td>
          <td>{{formatDatetime submission.updated_at}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  <Pagination
    @route="db.submissions.index"
    @models={{array @model.db}}
    @current={{@controller.page}}
    @total={{@model.totalPages}}
  />
</template> satisfies TOC<{
  Args: {
    model: {
      db: string;
      submissions: components['schemas']['SubmissionSummary'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
