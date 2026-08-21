import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { Textarea } from '@ember/component';

import DownloadLink from 'repository/components/download-link';
import MessageThread from 'repository/components/message-thread';
import { uniqueId } from '@ember/helper';

import formatDatetime from 'repository/helpers/format-datetime';
import humanSize from 'repository/helpers/human-size';

import type { paths } from 'schema/openapi';

type MessagesResponse =
  paths['/submission_requests/{submission_request_id}/messages']['get']['responses']['200']['content']['application/json'];

type CreateMessageResponse =
  paths['/submission_requests/{submission_request_id}/messages']['post']['responses']['201']['content']['application/json'];

type Message = MessagesResponse[number];

interface Signature {
  Args: {
    requestId: number;

    // How many curator messages are waiting on the submitter, as the
    // server counts them. Asked for rather than derived from the loaded
    // messages: the thread arrives from its newest end, and a question
    // older than that page would otherwise leave the reader with no way
    // to discharge it — the lost reminder this whole design exists to
    // prevent.
    unreadCount: number;
  };
}

export default class SubmissionMessages extends MessageThread<Signature, Message> {
  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);
    void this.load();
  }

  get url() {
    return `/submission_requests/${this.args.requestId}/messages`;
  }

  async load() {
    this.messages = await this.loadThread(this.url);
  }

  @action
  showEarlier() {
    void this.loadEarlier(this.url);
  }

  // Reading is no longer what discharges the thread — see MessagesController.
  // Replying and this do, so both refresh the banner: it is rendered from
  // a count the server keeps, and nothing else would go back for it.
  //
  // There is nothing to acknowledge until the thread has arrived: with no
  // id the server falls back to "now" and would discharge messages this
  // reader has not seen.
  get unanswered() {
    return Boolean(this.args.unreadCount) && Boolean(this.newestMessageId);
  }

  // Acknowledges what is on screen, not whatever has arrived since: a
  // question that landed a moment ago was not taken into account by a
  // press that could not have seen it.
  get newestMessageId() {
    return this.messages.at(-1)?.id;
  }

  @action
  async markRead() {
    await this.requestManager.request({
      url: `${this.url}/read`,
      method: 'POST',
      data: { through_id: this.newestMessageId },
    });

    // The count comes from the route, so that is what is fetched again.
    // NOT the thread: reloading it would replace what is on screen with
    // the newest page and throw away anything the reader had pulled in
    // with "Show earlier messages".
    await this.settle();
  }

  @action
  async submit(e: Event) {
    e.preventDefault();

    const body = this.draft.trim();

    // A message that is only an attachment is a real thing to send —
    // "here is the corrected file" needs no prose.
    if ((!body && this.files.length === 0) || this.posting) return;

    this.posting = true;
    this.error = null;

    try {
      const files = await this.uploadDraftFiles();

      const { content } = await this.requestManager.request<CreateMessageResponse>({
        url: this.url,
        method: 'POST',
        data: { submission_message: { body, files } },
        options: { reportErrors: false },
      });

      // Appended rather than re-fetched — saves a round trip and keeps
      // the form snappy. The unread count is the route's now, and
      // `settle` sends it back for below, so nothing here has to fix up
      // what the server just marked read.
      this.appendMessage(content);
      this.clearForm();

      await this.settle();
    } catch {
      this.error = SubmissionMessages.SEND_FAILED;
    } finally {
      this.posting = false;
    }
  }

  <template>
    <section class="mt-4" data-test-messages>
      <div class="d-flex align-items-baseline gap-3 flex-wrap">
        <h2 class="h5">Messages with the curator</h2>

        {{! The other way to deal with a thread. A curator's note that
        needs no reply would otherwise sit in the queue for ever, which is
        what the old mark-on-read was avoiding by discharging too much. }}
        {{#if this.unanswered}}
          <button
            type="button"
            class="btn btn-outline-secondary btn-sm"
            data-test-mark-read
            {{on "click" this.markRead}}
          >Mark as read</button>
        {{/if}}
      </div>

      <p class="text-body-secondary small">
        New messages from the curator are also sent to you by email.
      </p>

      {{! Speaker is carried by side and colour rather than by a label the
      eye has to read: the curator sits left with an avatar, you sit
      indented and tinted. }}
      {{#if this.messages.length}}
        {{! A thread arrives from its newest end, so what is missing is
        the beginning of it. }}
        {{#if this.hasEarlier}}
          <button
            type="button"
            class="btn btn-outline-secondary btn-sm mb-3"
            disabled={{this.loadingEarlier}}
            data-test-show-earlier
            {{on "click" this.showEarlier}}
          >
            {{if this.loadingEarlier "Loading…" "Show earlier messages"}}
          </button>
        {{/if}}

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
                  <strong class="text-body">{{if (isCurator m) "DDBJ curator" "You"}}</strong>
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
            <label for={{id}} class="form-label">Reply to the curator</label>
            {{! `<Textarea @value>` rather than a bare element: an HTML
            textarea whose content starts with a newline loses it, so a
            draft beginning with a blank line comes back one line short. }}
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

        {{! It was set and never shown: a failed send left the button
        coming back and nothing else happening, which is exactly what a
        lost message looks like from the sender's side. }}
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
