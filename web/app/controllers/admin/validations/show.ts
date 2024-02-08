import Controller from '@ember/controller';
import { getOwner } from '@ember/owner';

import type AdminValidationsIndexController from 'ddbj-repository/controllers/admin/validations/index';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export default class AdminValidationsShowController extends Controller {
  declare model: Validation;

  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:admin.validations.index') as AdminValidationsIndexController;

    return controller?.pageBefore;
  }
}
