import Controller from '@ember/controller';
import { action } from '@ember/object';
import { getOwner } from '@ember/owner';
import { service } from '@ember/service';

import downloadFile from 'ddbj-repository/utils/download-file';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type SubmissionsIndexController from 'ddbj-repository/controllers/submissions/index';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionsShowController extends Controller {
  @service declare currentUser: CurrentUserService;

  declare model: Submission;

  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:submissions.index') as SubmissionsIndexController;

    return controller?.pageBefore;
  }

  @action
  async downloadFile(url: string) {
    await downloadFile(url, this.currentUser);
  }
}
