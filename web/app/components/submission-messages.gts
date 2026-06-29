import Component from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';

import formatDatetime from 'repository/helpers/format-datetime';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type MessagesResponse =
  paths['/submissions/{submission_id}/messages']['get']['responses']['200']['content']['application/json'];

type CreateMessageResponse =
  paths['/submissions/{submission_id}/messages']['post']['responses']['201']['content']['application/json'];

type Message = MessagesResponse[number];

interface Signature {
  Args: {
    submissionId: number;
  };
}

export default class SubmissionMessages extends Component<Signature> {
  @service declare requestManager: RequestManager;

  @tracked messages: Message[] = [];
  @tracked draft = '';
  @tracked posting = false;

  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);
    void this.load();
  }

  async load() {
    const { content } = await this.requestManager.request<MessagesResponse>({
      url: `/submissions/${this.args.submissionId}/messages`,
    });

    this.messages = content;
  }

  @action
  updateDraft(e: Event) {
    this.draft = (e.target as HTMLTextAreaElement).value;
  }

  @action
  async submit(e: Event) {
    e.preventDefault();

    const body = this.draft.trim();
    if (!body || this.posting) return;

    this.posting = true;

    try {
      const { content } = await this.requestManager.request<CreateMessageResponse>({
        url: `/submissions/${this.args.submissionId}/messages`,
        method: 'POST',
        data: { submission_message: { body } },
      });

      // Optimistically append the new message instead of re-fetching the
      // whole thread — saves a round trip and keeps the form snappy.
      this.messages = [...this.messages, content];
      this.draft = '';
    } finally {
      this.posting = false;
    }
  }

  <template>
    <section class="mt-4">
      <h2 class="h4">Messages</h2>

      <p class="text-body-secondary small">
        Conversation with the DDBJ curator. New messages from the curator are sent to you by email.
      </p>

      {{#if this.messages.length}}
        <ul class="list-unstyled mb-3">
          {{#each this.messages as |m|}}
            <li class="border rounded p-2 mb-2 {{if (isCurator m) 'bg-light'}}">
              <div class="d-flex justify-content-between small text-body-secondary">
                <span>
                  <strong>{{if (isCurator m) "Curator" "You"}}</strong>
                  &mdash;
                  {{m.author_uid}}
                </span>
                <span>{{formatDatetime m.created_at}}</span>
              </div>
              <div class="mt-1 text-pre-wrap">{{m.body}}</div>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="text-body-secondary fst-italic">No messages yet.</p>
      {{/if}}

      <form {{on "submit" this.submit}}>
        <div class="mb-3">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">Reply to the curator</label>
            <textarea
              id={{id}}
              class="form-control font-monospace small"
              rows="4"
              value={{this.draft}}
              required
              {{on "input" this.updateDraft}}
            ></textarea>
          {{/let}}
        </div>

        <button type="submit" class="btn btn-primary" disabled={{this.posting}}>
          {{if this.posting "Sending..." "Send message"}}
        </button>
      </form>
    </section>
  </template>
}

function isCurator(m: Message): boolean {
  return m.author_role === 'curator';
}
