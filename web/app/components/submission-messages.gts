import Component from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { DirectUpload } from '@rails/activestorage';

import DownloadLink from 'repository/components/download-link';
import { uniqueId } from '@ember/helper';

import formatDatetime from 'repository/helpers/format-datetime';
import humanSize from 'repository/helpers/human-size';
import ENV from 'repository/config/environment';

import type AttentionService from 'repository/services/attention';
import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { paths } from 'schema/openapi';

type MessagesResponse =
  paths['/submission_requests/{submission_request_id}/messages']['get']['responses']['200']['content']['application/json'];

type CreateMessageResponse =
  paths['/submission_requests/{submission_request_id}/messages']['post']['responses']['201']['content']['application/json'];

type Message = MessagesResponse[number];

interface Signature {
  Args: {
    requestId: number;
  };
}

export default class SubmissionMessages extends Component<Signature> {
  @service declare attention: AttentionService;
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  @tracked messages: Message[] = [];
  @tracked draft = '';
  @tracked files: File[] = [];

  // The element itself, so it can be emptied after a send. Clearing
  // `files` alone leaves the control still displaying the name of what
  // was just sent, and the next message then goes out with nothing
  // attached while the sender is looking at the filename they believe is
  // on it.
  fileInput?: HTMLInputElement;
  @tracked posting = false;
  @tracked error: string | null = null;

  constructor(owner: unknown, args: Signature['Args']) {
    // @ts-expect-error -- Glimmer Component owner typing
    super(owner, args);
    void this.load();
  }

  async load() {
    const { content } = await this.requestManager.request<MessagesResponse>({
      url: `/submission_requests/${this.args.requestId}/messages`,
    });

    this.messages = content;
  }

  // Reading is no longer what discharges the thread — see MessagesController.
  // These two are, so both refresh the banner: it is rendered from a count
  // the server keeps, and nothing else would go back for it.
  get unanswered() {
    return this.messages.some((m) => m.author_role === 'curator' && !m.read_at);
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
      url: `/submission_requests/${this.args.requestId}/messages/read`,
      method: 'POST',
      data: { through_id: this.newestMessageId },
    });

    await this.load();
    await this.settle();
  }

  // The panel above this thread is rendered from counts the route
  // fetched, so discharging the thread has to send the route back for
  // them — otherwise "A curator has a question … reply below" stays up
  // over a thread that was just answered, and only the button vanishes.
  async settle() {
    await this.router.refresh();

    void this.attention.refresh();
  }

  @action
  updateDraft(e: Event) {
    this.draft = (e.target as HTMLTextAreaElement).value;
  }

  @action
  selectFiles(e: Event) {
    this.fileInput = e.target as HTMLInputElement;
    this.files = Array.from(this.fileInput.files ?? []);
  }

  // Straight to storage, the same path the submission upload itself
  // takes. Nothing goes through the API request, so the files this
  // conversation is about — submission files, large by nature — are not
  // bounded by anything in front of Rails.
  async upload(file: File) {
    // The endpoint authenticates now (it mints a blob row and a presigned
    // PUT, which is not something to leave open), and @rails/activestorage
    // sends only its own headers unless it is given more.
    const upload = new DirectUpload(file, ENV.directUploadURL, undefined, this.currentUser.authorizationHeader);

    return new Promise<string>((resolve, reject) => {
      upload.create((error, blob) => (error ? reject(error) : resolve(blob!.signed_id)));
    });
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
      const files = await Promise.all(this.files.map((file) => this.upload(file)));

      const { content } = await this.requestManager.request<CreateMessageResponse>({
        url: `/submission_requests/${this.args.requestId}/messages`,
        method: 'POST',
        data: { submission_message: { body, files } },
        options: { reportErrors: false },
      });

      // Appended rather than re-fetched — saves a round trip and keeps
      // the form snappy — but the curator's messages were just marked
      // read server-side, so the copies held here have to learn that too
      // or the button stays offering to do what replying already did.
      this.messages = [
        ...this.messages.map((m) =>
          m.author_role === 'curator' && !m.read_at ? { ...m, read_at: new Date().toISOString() } : m,
        ),
        content,
      ];

      this.draft = '';
      this.files = [];

      if (this.fileInput) this.fileInput.value = '';

      await this.settle();
    } catch {
      // Storage going away is not hypothetical here — a dev SeaweedFS
      // crash-looped unnoticed for a fortnight — and the only signal a
      // silent failure gives is that the button came back and nothing
      // happened.
      this.error = 'Could not send. The file may not have uploaded — check your connection and try again.';
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
            <textarea
              id={{id}}
              class="form-control font-monospace small textarea-autogrow"
              value={{this.draft}}
              {{on "input" this.updateDraft}}
            ></textarea>
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
      </form>
    </section>
  </template>
}

function isCurator(m: Message): boolean {
  return m.author_role === 'curator';
}
