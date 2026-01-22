import { LinkTo } from '@ember/routing';

import { gt } from 'ember-truth-helpers';

import formatDatetime from 'repository/helpers/format-datetime';
import Pagination from 'repository/components/pagination';

import type Controller from 'repository/controllers/submissions/index';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <h1 class="display-6 mb-4">Submissions</h1>

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
            <LinkTo @route="submission" @model={{submission.id}}>
              Submission-{{submission.id}}
            </LinkTo>
          </td>

          <td>{{formatDatetime submission.created_at}}</td>
          <td>{{formatDatetime submission.updated_at}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  {{#if (gt @model.totalPages 1)}}
    <Pagination @route="submissions.index" @current={{@controller.page}} @total={{@model.totalPages}} />
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: {
      submissions: components['schemas']['Submission'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
