import Service, { service } from '@ember/service';

import type CurrentUserService from 'repository/services/current-user';
import type { RequestManager } from '@warp-drive/core';

// Fetching a file the API will only hand over to somebody it recognises.
//
// A plain `<a href>` cannot carry an `Authorization` header, and this API
// takes no cookies — so an anchor pointing at a download route arrives
// unauthenticated and is refused. Asking for the address and then
// navigating to it is what keeps the check where it belongs: at the
// moment of the click, against whoever is clicking.
//
// The address that comes back is a storage URL good for a few minutes.
// It is not fetched through here: these are submission files, and a
// genome assembly read into a blob to be handed to the browser is a tab
// that runs out of memory.
export default class DownloadsService extends Service {
  @service declare currentUser: CurrentUserService;
  @service declare requestManager: RequestManager;

  async open(url: string) {
    const { content } = await this.requestManager.request<{ url?: string }>({
      url,
      // The failure belongs next to the file it is about — DownloadLink
      // puts it there, so the modal stays out of it.
      options: { params: { as: 'url', disposition: 'attachment' }, reportErrors: false },
    });

    // Navigating to `undefined` would leave the app on a 404 with no
    // sign of what went wrong. An answer that carries no address is a
    // failure however it was spelled.
    if (!content?.url) throw new Error('The server did not say where that file is.');

    this.navigate(content.url);
  }

  // `location.assign` rather than a new tab: the address is asked for
  // with `disposition=attachment` above, so the answer saves the file
  // and the page stays where it is. A tab opened for it would flash and
  // close. The cost is that a storage error at this point — the answer
  // arriving without that header — navigates away from the app; the URL
  // is seconds old by then, which is what makes that unlikely rather
  // than merely unhandled.
  //
  // Its own method because `window.location` is read-only and cannot be
  // stubbed — this is the seam a test watches to see where a download
  // went.
  navigate(url: string) {
    window.location.assign(url);
  }
}
