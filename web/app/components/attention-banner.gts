import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { hash } from '@ember/helper';
import { service } from '@ember/service';

import type AttentionService from 'repository/services/attention';
import type { AttentionReason } from 'repository/services/attention';

// What each reason means to the submitter, and where it is acted on.
// Ordered by how blocked the submission is, which is also the order the
// breakdown reads in.
const REASONS: { key: AttentionReason; singular: string; plural: string }[] = [
  { key: 'validation_failed', singular: 'needs fixing', plural: 'need fixing' },
  { key: 'ready_to_apply', singular: 'ready to submit', plural: 'ready to submit' },
  { key: 'unread_message', singular: 'curator question', plural: 'curator questions' },
];

// Global "you need to do something" band. Sits above the page rather than
// inside a list, so the notice is reachable from wherever the submitter
// happens to be — and worded like the notification email that led them
// here, so the two do not describe the same thing differently.
//
// It names WHY, not just how many: "3 submissions need you" is a nag,
// while "2 ready to submit · 1 curator question" is a to-do list, and its
// two halves are acted on in completely different places.
export default class AttentionBanner extends Component {
  @service declare attention: AttentionService;

  get breakdown() {
    return REASONS.flatMap(({ key, singular, plural }) => {
      const count = this.attention.requests.filter((request) => request.reason === key).length;

      return count ? [`${count} ${count === 1 ? singular : plural}`] : [];
    });
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
              you.
            </strong>

            <span class="text-body-secondary ms-1">
              {{#each this.breakdown as |part index|}}
                {{~if index " · "}}{{part~}}
              {{/each}}
            </span>
          </span>

          <span class="flex-fill"></span>

          {{! One destination, not a list of request links: the list can
          show them all with their reasons, which a band cannot. }}
          <LinkTo @route="index" @query={{hash phase="all" needsAction=true page=1}} class="fw-semibold">
            Show only these →
          </LinkTo>
        </div>
      </div>
    {{/if}}
  </template>
}
