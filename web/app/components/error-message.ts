import Component from '@glimmer/component';

export interface Signature {
  Args: {
    error: Error | object;
  };
}

export default class ErrorMessageComponent extends Component<Signature> {
  get message() {
    const { error } = this.args;

    return error.toString();
  }

  get details() {
    const { error } = this.args;

    if (error instanceof Error) {
      return error.stack;
    } else {
      return JSON.stringify(error, null, 2);
    }
  }
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ErrorMessage: typeof ErrorMessageComponent;
  }
}
