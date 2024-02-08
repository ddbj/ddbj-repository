import templateOnlyComponent from '@ember/component/template-only';

import type { components } from 'schema/openapi';

type Validation = components['schemas']['Validation'];

interface Signature {
  Args: {
    showUser?: boolean;
    validations: Validation[];
    page: number;
    lastPage: number;
    indexRoute: string;
    showRoute: string;
  };
}

const ValidationsTableComponent = templateOnlyComponent<Signature>();

export default ValidationsTableComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ValidationsTable: typeof ValidationsTableComponent;
  }
}
