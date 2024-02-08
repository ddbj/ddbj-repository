import Component from '@glimmer/component';
import { action } from '@ember/object';
import { service } from '@ember/service';

import downloadFile from 'ddbj-repository/utils/download-file';

import type CurrentUserService from 'ddbj-repository/services/current-user';
import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    showUser?: boolean;
    validation: Validation;
  };
}

export default class ValidationComponent extends Component<Signature> {
  @service declare currentUser: CurrentUserService;

  @action
  async downloadFile(url: string) {
    await downloadFile(url, this.currentUser);
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    Validation: typeof ValidationComponent;
  }
}
