import templateOnlyComponent from '@ember/component/template-only';

export interface Signature {
  Element: HTMLTableElement;

  Args: {
    items: unknown[];
  };

  Blocks: {
    default: [];
  };
}

const TableComponent = templateOnlyComponent<Signature>();

export default TableComponent;

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    Table: typeof TableComponent;
  }
}
