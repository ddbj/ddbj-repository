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
    const { content } = await this.requestManager.request<{ url: string }>({
      url,
      options: { params: { as: 'url', disposition: 'attachment' } },
    });

    this.navigate(content.url);
  }

  // `location.assign` rather than a new tab: the answer carries
  // `Content-Disposition: attachment`, so the browser saves the file and
  // stays where it is. A tab opened for it would flash and close.
  //
  // Its own method because `window.location` is read-only and cannot be
  // stubbed — this is the seam a test watches to see where a download
  // went.
  navigate(url: string) {
    window.location.assign(url);
  }
}
