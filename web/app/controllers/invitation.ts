import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

export default class extends Controller {
  // Set by Cloakman on the way back from creating an account. The flash
  // it showed there does not travel across applications, so this page is
  // the one that has to say the account is ready — otherwise somebody
  // lands back on an unchanged page and cannot tell whether it worked.
  queryParams = [{ signedUp: 'signed_up' }];

  @tracked signedUp = '';
}
