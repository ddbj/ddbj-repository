import Service from '@ember/service';
import { getOwner } from '@ember/owner';

import type ApplicationController from 'ddbj-repository/controllers/application';

export default class ErrorModalService extends Service {
  show(error: object) {
    const controller = getOwner(this)!.lookup('controller:application') as ApplicationController;

    controller.showErrorModal(error);

    throw error;
  }
}
