import { helper } from '@ember/component/helper';

export interface Signature {
  Args: {
    Positional: [obj: unknown];
  };

  Return: string;
}

const toJson = helper<Signature>(([obj]) => {
  return JSON.stringify(obj, null, 2);
});

export default toJson;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'to-json': typeof toJson;
  }
}
