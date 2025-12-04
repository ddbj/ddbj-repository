import { LinkTo } from '@ember/routing';

import formatDatetime from 'repository/helpers/format-datetime';

export default <template>
  <h1>Requests</h1>

  <LinkTo @route="requests.new" class="btn btn-primary">New Submission Request</LinkTo>

  <table class="table">
    <thead>
      <tr>
        <th>ID</th>
        <th>Created</th>
        <th>Status</th>
      </tr>
    </thead>

    <tbody>
      {{#each @model as |request|}}
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
</template>;
