import Route from '@ember/routing/route';
import { service } from '@ember/service';

import type { RequestManager } from '@warp-drive/core';
import type { paths } from 'schema/openapi';

type AccessionRecord =
  paths['/submissions/{id}/accessions/{accession}']['get']['responses']['200']['content']['application/json'];

export default class extends Route {
  @service declare requestManager: RequestManager;

  async model({ accession }: { accession: string }) {
    const request = this.modelFor('request') as { id: number; submission: { id: number } | null };

    const { content } = await this.requestManager.request<AccessionRecord>({
      url: `/submissions/${request.submission?.id}/accessions/${encodeURIComponent(accession)}`,
    });

    // Spread, so the template reads `@model.accession` and
    // `@model.record` — the record is one field of what this endpoint
    // answers, not the whole of it.
    return { requestId: request.id, ...content };
  }
}
