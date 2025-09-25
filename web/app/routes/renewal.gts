import Route from '@ember/routing/route';
import { service } from '@ember/service';

export default class RenewalRoute extends Route {
  @service declare request: RequestService;

  async model({ accession_renewal_id }: { renewal_id: string }) {
    const res = await this.request.fetch(`/accession_renewals/${accession_renewal_id}`);

    return res.json() as Promise<{
      id: number;
      progress: string;
      validity: string | null;
    }>;
  }
}
