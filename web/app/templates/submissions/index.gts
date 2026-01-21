import { LinkTo } from '@ember/routing';

import formatDatetime from 'repository/helpers/format-datetime';

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
      {{#each @model as |submission|}}
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
</template> satisfies TOC<{
  Args: {
    model: components['schemas']['Submission'][];
  };
}>;
