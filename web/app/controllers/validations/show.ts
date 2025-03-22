import Controller from '@ember/controller';
import { getOwner } from '@ember/owner';

import type ValidationsIndexController from 'repository/controllers/validations/index';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export default class ValidationsShowController extends Controller {
  declare model: Validation;

  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:validations.index') as ValidationsIndexController;

    return controller?.pageBefore;
  }
}
