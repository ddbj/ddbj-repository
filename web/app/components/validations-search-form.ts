import Component from '@glimmer/component';

interface Signature {
  Element: HTMLDListElement;

  Args: {
    dbs: string[];
    selectedDBs: string[];
    onSelectedDBsChange: (selected: string[]) => void;
    created?: string;
    onCreatedChange: (created?: string) => void;
    progresses: string[];
    selectedProgresses: string[];
    onSelectedProgressesChange: (selected: string[]) => void;
    validities: string[];
    selectedValidities: string[];
    onSelectedValiditiesChange: (selected: string[]) => void;
    submitted?: boolean;
    onSubmittedChange: (submitted?: boolean) => void;
  };
}

export default class ValidationsSearchFormComponent extends Component<Signature> {
  createdOptions = [
    { label: 'All', value: undefined },
    { label: 'Within 1 day', value: 'within_one_day' },
    { label: 'Within 1 week', value: 'within_one_week' },
    { label: 'Within 1 month', value: 'within_one_month' },
    { label: 'Within 1 year', value: 'within_one_year' },
  ] as const;

  progressOptions = [
    { label: 'Waiting', value: 'waiting' },
    { label: 'Running', value: 'running' },
    { label: 'Finished', value: 'finished' },
    { label: 'Canceled', value: 'canceled' },
  ] as const;

  validityOptions = [
    { label: 'Valid', value: 'valid' },
    { label: 'Invalid', value: 'invalid' },
    { label: 'Error', value: 'error' },
    { label: '-', value: 'null' },
  ] as const;

  submittedOptions = [
    { label: 'All', value: undefined },
    { label: 'Submitted', value: true },
    { label: 'Not submitted', value: false },
  ] as const;
}

export type Created = ValidationsSearchFormComponent['createdOptions'][number]['value'];

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    ValidationsSearchForm: typeof ValidationsSearchFormComponent;
  }
}
