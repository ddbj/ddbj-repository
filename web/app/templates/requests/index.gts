import { LinkTo } from '@ember/routing';

import { gt } from 'ember-truth-helpers';

import formatDatetime from 'repository/helpers/format-datetime';
import Pagination from 'repository/components/pagination';

import type Controller from 'repository/controllers/requests/index';
import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

export default <template>
  <h1 class="display-6 mb-4">Requests</h1>

  <div class="mb-3">
    <LinkTo @route="requests.new" class="btn btn-primary">New Submission Request</LinkTo>
  </div>

  <table class="table border">
    <thead class="table-light">
      <tr>
        <th>ID</th>
        <th>Created</th>
        <th>Status</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model.requests as |request|}}
        <tr>
          <td>
            <LinkTo @route="request" @model={{request.id}}>
              Request-{{request.id}}
            </LinkTo>
          </td>

          <td>{{formatDatetime request.created_at}}</td>
          <td>{{request.status}}</td>
        </tr>
      {{/each}}
    </tbody>
  </table>

  {{#if (gt @model.totalPages 1)}}
    <Pagination @route="requests.index" @current={{@controller.page}} @total={{@model.totalPages}} />
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: {
      requests: components['schemas']['SubmissionRequest'][];
      totalPages: number;
    };

    controller: Controller;
  };
}>;
