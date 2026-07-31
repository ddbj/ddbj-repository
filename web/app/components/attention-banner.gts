import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { service } from '@ember/service';

import type AttentionService from 'repository/services/attention';

// Global "you need to do something" band. Sits above the page rather than
// inside a list, so the notice is reachable from wherever the submitter
// happens to be — and worded like the notification email that led them
// here, so the two do not describe the same thing differently.
export default class AttentionBanner extends Component {
  @service declare attention: AttentionService;

  get first() {
    return this.attention.requests[0];
  }

  <template>
    {{#if this.attention.count}}
      <div class="alert alert-warning border-0 rounded-0 mb-0 py-2" role="status">
        <div class="container d-flex align-items-center gap-3 flex-wrap">
          <span class="badge text-bg-danger">{{this.attention.count}}</span>

          <span>
            <strong>
              {{this.attention.count}}
              {{if (eq this.attention.count 1) "submission needs" "submissions need"}}
              your reply.
            </strong>

            <span class="text-body-secondary ms-1">
              {{#each this.attention.requests as |request index|}}
                {{~if index ", "}}
                <LinkTo @route="request" @model={{request.id}}>
                  #{{request.id}}
                </LinkTo>
                {{~#if request.source_id}}
                  ({{request.source_id}})
                {{/if~}}
              {{/each}}
            </span>
          </span>

          <span class="flex-fill"></span>

          {{#if this.first}}
            <LinkTo @route="request" @model={{this.first.id}} class="fw-semibold">
              Review them →
            </LinkTo>
          {{/if}}
        </div>
      </div>
    {{/if}}
  </template>
}
