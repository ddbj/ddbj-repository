import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import { errorMessage } from 'repository/utils/error-message';

import type DownloadsService from 'repository/services/downloads';

interface Signature {
  Element: HTMLButtonElement;

  Args: {
    url: string;
    filename: string;
  };
}

// Looks like a link, is a button. See DownloadsService for why it cannot
// be an anchor: the address it would point at refuses a request that
// carries no credentials, and a browser navigation carries none.
export default class DownloadLink extends Component<Signature> {
  @service declare downloads: DownloadsService;

  @tracked error: string | null = null;

  @action
  async open() {
    this.error = null;

    try {
      await this.downloads.open(this.args.url);
    } catch (e) {
      this.error = errorMessage(e) ?? 'Could not fetch that file. Try again.';
    }
  }

  <template>
    <button
      type="button"
      class="btn btn-link p-0 align-baseline"
      data-test-download
      {{on "click" this.open}}
      ...attributes
    >
      {{@filename}}
    </button>

    {{#if this.error}}
      <div class="small text-warning-emphasis" data-test-error>{{this.error}}</div>
    {{/if}}
  </template>
}
