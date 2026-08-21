import Component from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { uniqueId } from '@ember/helper';
import { DirectUpload } from '@rails/activestorage';

import DownloadLink from 'repository/components/download-link';
import formatDatetime from 'repository/helpers/format-datetime';
import humanSize from 'repository/helpers/human-size';
import ENV from 'repository/config/environment';

import type AttentionService from 'repository/services/attention';
import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
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
export default class SetMessages extends Component<Signature> {
  @service declare attention: AttentionService;
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  @tracked messages: Message[] = [];
  @tracked draft = '';
  @tracked files: File[] = [];

  // The element itself, so it can be emptied after a send — clearing
  // `files` alone leaves the control showing the name of what was just
  // sent, and the next message goes out with nothing attached while the
  // sender is looking at the filename they believe is on it.
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
      url: `/sets/${this.args.setId}/messages`,
    });

    this.messages = content;
  }

  // Acknowledges what is on screen, not whatever has arrived since.
  get newestMessageId() {
    return this.messages.at(-1)?.id;
  }

  @action
  async markRead() {
    await this.requestManager.request({
      url: `/sets/${this.args.setId}/messages/read`,
      method: 'POST',
      data: { through_id: this.newestMessageId },
      options: { reportErrors: false },
    });

    await this.settle();
  }

  // The count above this thread comes from the route's copy of the set,
  // so discharging the thread has to send the route back for it.
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

  // Straight to storage, like every other upload here: the files this
  // conversation is about are submission files, and nothing about them
  // should be bounded by a request body.
  async upload(file: File) {
    const upload = new DirectUpload(file, ENV.directUploadURL, undefined, this.currentUser.authorizationHeader);

    return new Promise<string>((resolve, reject) => {
      upload.create((error, blob) => (error ? reject(error) : resolve(blob!.signed_id)));
    });
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
      const files = await Promise.all(this.files.map((file) => this.upload(file)));

      const { content } = await this.requestManager.request<CreateMessageResponse>({
        url: `/sets/${this.args.setId}/messages`,
        method: 'POST',
        data: { submission_set_message: { body, files } },
        options: { reportErrors: false },
      });

      this.messages = [...this.messages, content];

      this.draft = '';
      this.files = [];

      if (this.fileInput) this.fileInput.value = '';

      await this.settle();
    } catch {
      this.error = 'Could not send. The file may not have uploaded — check your connection and try again.';
    } finally {
      this.posting = false;
    }
  }

  <template>
    <section class="mt-4" data-test-set-messages>
      <div class="d-flex align-items-baseline gap-3 flex-wrap">
        <h2 class="h5">Messages about this set</h2>

        {{! The other way to deal with a thread: a curator's note that
        needs no reply would otherwise sit here for ever. Per member —
        marking it read speaks for nobody else in the set. }}
        {{#if @unreadCount}}
          <button
            type="button"
            class="btn btn-outline-secondary btn-sm"
            data-test-mark-read
            {{on "click" this.markRead}}
          >Mark as read</button>
        {{/if}}
      </div>

      <p class="text-body-secondary small">
        Everyone in this set can read and write here, and every message is emailed to all of them. A question about one
        submission belongs on that submission instead — those conversations stay between its owner and DDBJ.
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
