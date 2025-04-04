import Controller from '@ember/controller';
import { action } from '@ember/object';
import { getOwner } from '@ember/owner';
import { service } from '@ember/service';

import type RequestService from 'repository/services/request';
import type SubmissionsIndexController from 'repository/controllers/submissions/index';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionsShowController extends Controller {
  @service declare request: RequestService;

  declare model: Submission;

  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:submissions.index') as SubmissionsIndexController;

    return controller?.pageBefore;
  }

  @action
  async downloadFile(url: string) {
    await this.request.downloadFile(url);
  }
}
