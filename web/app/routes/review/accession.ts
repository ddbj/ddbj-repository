import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type ReviewerAccessionRecord =
  paths['/reviews/{token}/accessions/{accession}']['get']['responses']['200']['content']['application/json'];

// One accession on a share link, read. No auth gate and no submission id:
// the token is the whole credential, and the submission the accession came
// from is the thing that was deliberately not shared.
export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ accession }: { accession: string }) {
    const { token, name } = this.modelFor('review') as { token: string; name: string };

    const { content } = await this.requestManager.request<ReviewerAccessionRecord>({
      url: `/reviews/${token}/accessions/${encodeURIComponent(accession)}`,
    });

    return { token, setName: name, ...content };
  }
}
