import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';

import downloadFile from 'ddbj-repository/utils/download-file';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type { components } from 'schema/openapi';

type Submission = components['schemas']['Submission'];

export default class SubmissionsShowController extends Controller {
  @service declare currentUser: CurrentUserService;

  declare model: Submission;

  @action
  async downloadFile(url: string) {
    await downloadFile(url, this.currentUser);
  }
}
