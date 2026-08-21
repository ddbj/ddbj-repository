import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { DirectUpload } from '@rails/activestorage';

import ENV from 'repository/config/environment';

import type AttentionService from 'repository/services/attention';
import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';

// What the two conversations have in common: a draft, some files on
// their way to storage, and what to do to the rest of the screen once
// something has been said.
//
// The two threads themselves are deliberately separate components — a
// submission's is between one submitter and DDBJ, a set's is between
// everyone in it, and they name their speakers, count their unread and
// address their endpoints differently. What is shared is the plumbing
// under that, which was copied once and would have drifted.
export default class MessageThread<S, M extends { id: number }> extends Component<S> {
  @service declare attention: AttentionService;
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  @tracked messages: M[] = [];

  // How many the thread holds in all, from `Total-Count`. A thread is
  // read from its newest end, so what arrives is the last page of it —
  // and this is how the screen knows whether to offer the rest.
  @tracked total = 0;
  @tracked loadingEarlier = false;

  @tracked draft = '';
  @tracked files: File[] = [];
  @tracked posting = false;
  @tracked error: string | null = null;

  // The element itself, so it can be emptied after a send. Clearing
  // `files` alone leaves the control still displaying the name of what
  // was just sent, and the next message then goes out with nothing
  // attached while the sender is looking at the filename they believe is
  // on it.
  fileInput?: HTMLInputElement;

  @action
  selectFiles(e: Event) {
    this.fileInput = e.target as HTMLInputElement;
    this.files = Array.from(this.fileInput.files ?? []);
  }

  // Straight to storage, the same path the submission upload itself
  // takes. Nothing goes through the API request, so the files these
  // conversations are about — submission files, large by nature — are
  // not bounded by anything in front of Rails.
  async upload(file: File) {
    // The endpoint authenticates (it mints a blob row and a presigned
    // PUT, which is not something to leave open), and
    // @rails/activestorage sends only its own headers unless it is given
    // more.
    const upload = new DirectUpload(file, ENV.directUploadURL, undefined, this.currentUser.authorizationHeader);

    return new Promise<string>((resolve, reject) => {
      upload.create((error, blob) => (error ? reject(error) : resolve(blob!.signed_id)));
    });
  }

  get hasEarlier() {
    return this.total > this.messages.length;
  }

  // The newest page, replacing whatever was on screen.
  async loadThread(url: string) {
    const { content, response } = await this.requestManager.request<M[]>({ url });

    this.total = Number(response?.headers?.get('Total-Count')) || content.length;

    return content;
  }

  // The page before the oldest one on screen, prepended. `before_id`
  // rather than a page number: a page counted from the oldest message
  // moves under the reader every time somebody writes.
  async loadEarlier(url: string) {
    const oldest = this.messages[0]?.id;
    if (!oldest || this.loadingEarlier) return;

    this.loadingEarlier = true;

    try {
      const { content } = await this.requestManager.request<M[]>({
        url,
        options: { params: { before_id: oldest }, reportErrors: false },
      });

      this.messages = [...content, ...this.messages];
    } catch {
      this.error = 'Could not load the earlier messages. Try again.';
    } finally {
      this.loadingEarlier = false;
    }
  }

  uploadDraftFiles() {
    return Promise.all(this.files.map((file) => this.upload(file)));
  }

  clearForm() {
    this.draft = '';
    this.files = [];

    if (this.fileInput) this.fileInput.value = '';
  }

  // The panels around a thread are rendered from counts the route
  // fetched, so dealing with the thread has to send the route back for
  // them — otherwise a notice stays up over a conversation that has just
  // been answered, and only the button vanishes.
  async settle() {
    await this.router.refresh();

    void this.attention.refresh();
  }

  // Storage going away is not hypothetical — a dev SeaweedFS
  // crash-looped unnoticed for a fortnight — and the only signal a
  // silent failure gives is that the button came back and nothing
  // happened.
  static readonly SEND_FAILED = 'Could not send. The file may not have uploaded — check your connection and try again.';
}
