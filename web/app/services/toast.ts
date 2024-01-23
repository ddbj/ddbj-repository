import Service from '@ember/service';
import { getOwner } from '@ember/owner';

import type ApplicationController from 'ddbj-repository/controllers/application';
import type { ToastData } from 'ddbj-repository/controllers/application';

export default class ToastService extends Service {
  show(body: ToastData['body'], bgColor: ToastData['bgColor']) {
    const controller = getOwner(this)!.lookup('controller:application') as ApplicationController;

    controller.showToast({ body, bgColor });
  }
}
