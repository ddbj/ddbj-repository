import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { modifier } from 'ember-modifier';
import { uniqueId } from '@ember/helper';
import { Textarea } from '@ember/component';

import DownloadLink from 'repository/components/download-link';
import MessageThread from 'repository/components/message-thread';
import formatDatetime from 'repository/helpers/format-datetime';
import humanSize from 'repository/helpers/human-size';

import type { paths } from 'schema/openapi';

type MessagesResponse = paths['/sets/{set_id}/messages']['get']['responses']['200']['content']['application/json'];

type CreateMessageResponse =
  paths['/sets/{set_id}/messages']['post']['responses']['201']['content']['application/json'];

type Message = MessagesResponse[number];

interface Signature {
  Args: {
    setId: number;

    // How many messages are waiting on this member, as the server counts
    // it. The thread itself cannot say: a message carries no `read_at`
    // here, because where each member has got to is a fact about the
    // person rather than about the message.
    unreadCount: number;
  };
}

// The set's own conversation — one thread about the bundle, which every
// member of the set reads and writes.
//
// Not the submissions' threads. Those stay between their owner and DDBJ,
// and are on each submission's own page; being able to read somebody's
// submission through a shared set is not being party to what they were
// asked about it.
export default class SetMessages extends MessageThread<Signature> {
  @tracked messages: Message[] = [];

  // Which set the messages on screen belong to. Ember reuses a component
  // instance when the model changes under the same route, so loading
  // once at construction would leave one set's thread rendered under
  // another set's name — in a feature whose whole premise is who is
  // party to which conversation.
  #loaded?: number;

  reload = modifier((_element: Element, [setId]: [number]) => {
    if (this.#loaded === setId) return;

    this.#loaded = setId;
    this.messages = [];

    void this.load();
  });

  async load() {
    const setId = this.args.setId;

    const { content } = await this.requestManager.request<MessagesResponse>({
      url: `/sets/${setId}/messages`,
    });

    // A slower answer for the set we have left must not land on the one
    // we are looking at.
    if (setId === this.args.setId) this.messages = content;
  }

  // Acknowledges what is on screen, not whatever has arrived since.
  get newestMessageId() {
    return this.messages.at(-1)?.id;
  }

  get unreadShown() {
    return Boolean(this.args.unreadCount) && Boolean(this.newestMessageId);
  }

  @action
  async markRead() {
    // Nothing to acknowledge until the thread has arrived: without an id
    // the server falls back to "now" and would discharge messages this
    // reader has not seen — the exact thing `through_id` exists to stop.
    if (!this.newestMessageId) return;

    this.error = null;

    try {
      await this.requestManager.request({
        url: `/sets/${this.args.setId}/messages/read`,
        method: 'POST',
        data: { through_id: this.newestMessageId },
        options: { reportErrors: false },
      });

      // Both: the count above comes from the route, and anything posted
      // while this page was open is still missing from the thread.
      await this.load();
      await this.settle();
    } catch {
      this.error = 'Could not mark it read. Try again.';
    }
  }

  isMine = (m: Message) => m.author_role === 'member' && m.author_uid === this.currentUser.user?.uid;

  @action
  async submit(e: Event) {
    e.preventDefault();

    const body = this.draft.trim();

    // An attachment on its own is a real thing to send.
    if ((!body && this.files.length === 0) || this.posting) return;

    this.posting = true;
    this.error = null;

    try {
      const files = await this.uploadDraftFiles();

      const { content } = await this.requestManager.request<CreateMessageResponse>({
        url: `/sets/${this.args.setId}/messages`,
        method: 'POST',
        data: { submission_set_message: { body, files } },
        options: { reportErrors: false },
      });

      this.messages = [...this.messages, content];

      this.clearForm();

      await this.settle();
    } catch {
      this.error = SetMessages.SEND_FAILED;
    } finally {
      this.posting = false;
    }
  }

  <template>
    <section class="mt-4" data-test-set-messages {{this.reload @setId}}>
      <div class="d-flex align-items-baseline gap-3 flex-wrap">
        <h2 class="h5">Messages about this set</h2>

        {{! The other way to deal with a thread: a curator's note that
        needs no reply would otherwise sit here for ever. Per member —
        marking it read speaks for nobody else in the set. }}
        {{#if this.unreadShown}}
          <button
            type="button"
            class="btn btn-outline-secondary btn-sm"
            data-test-mark-read
            {{on "click" this.markRead}}
          >Mark as read</button>
        {{/if}}
      </div>

      <p class="text-body-secondary small">
        Everyone in this set can read and write here, and every message is emailed to the others and to the DDBJ
        curators following the set. A question about one submission belongs on that submission instead — those
        conversations stay between its owner and DDBJ.
      </p>

      {{! Speaker by side and colour, as on a submission's thread: the
      curator sits left with an avatar, the members sit indented. Which
      member wrote it is named — unlike a submission's thread, where every
      non-curator message is by definition the owner's. }}
      {{#if this.messages.length}}
        <ul class="list-unstyled mb-3 d-flex flex-column gap-3">
          {{#each this.messages as |m|}}
            <li class="d-flex gap-3 {{unless (isCurator m) 'ps-5'}}">
              {{#if (isCurator m)}}
                <span
                  class="message-avatar badge rounded-circle text-bg-dark d-flex align-items-center justify-content-center"
                  aria-hidden="true"
                >DC</span>
              {{/if}}

              <div
                class="flex-fill border rounded p-3
                  {{if (isCurator m) 'bg-body-tertiary' 'bg-primary-subtle border-primary-subtle'}}"
              >
                <div class="d-flex justify-content-between small text-body-secondary mb-1">
                  <strong class="text-body">
                    {{#if (isCurator m)}}
                      DDBJ curator
                    {{else if (this.isMine m)}}
                      You
                    {{else}}
                      {{m.author_uid}}
                    {{/if}}
                  </strong>

                  <span>{{formatDatetime m.created_at}}</span>
                </div>

                <div class="text-pre-wrap">{{m.body}}</div>

                {{#if m.files.length}}
                  <ul class="list-unstyled mb-0 mt-2 small">
                    {{#each m.files as |file|}}
                      <li>
                        <DownloadLink @url={{file.url}} @filename={{file.filename}} />
                        <span class="text-body-secondary">{{humanSize file.byte_size}}</span>
                      </li>
                    {{/each}}
                  </ul>
                {{/if}}
              </div>
            </li>
          {{/each}}
        </ul>
      {{else}}
        <p class="text-body-secondary fst-italic">No messages yet.</p>
      {{/if}}

      <form {{on "submit" this.submit}}>
        <div class="mb-3">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">Write to the set</label>
            <Textarea id={{id}} class="form-control font-monospace small textarea-autogrow" @value={{this.draft}} />
          {{/let}}
        </div>

        <div class="mb-3">
          {{#let (uniqueId) as |id|}}
            <label for={{id}} class="form-label">Attach files</label>
            <input id={{id}} type="file" multiple class="form-control" {{on "change" this.selectFiles}} />
          {{/let}}
        </div>

        <button type="submit" class="btn btn-primary" disabled={{this.posting}}>
          {{if this.posting "Sending..." "Send message"}}
        </button>

        {{#if this.error}}
          <div class="alert alert-warning mt-3 mb-0" data-test-error>{{this.error}}</div>
        {{/if}}
      </form>
    </section>
  </template>
}

function isCurator(m: Message): boolean {
  return m.author_role === 'curator';
}
