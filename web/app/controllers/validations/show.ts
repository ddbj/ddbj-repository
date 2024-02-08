import Controller from '@ember/controller';
import { getOwner } from '@ember/owner';
import { service } from '@ember/service';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type ValidationsIndexController from 'ddbj-repository/controllers/validations/index';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

export default class ValidationsShowController extends Controller {
  @service declare currentUser: CurrentUserService;

  declare model: Validation;

  get indexPage() {
    const controller = getOwner(this)!.lookup('controller:validations.index') as ValidationsIndexController;

    return controller?.pageBefore;
  }
}
