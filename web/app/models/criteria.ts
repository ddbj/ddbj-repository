import ENV from 'repository/config/environment';

export const dbs = ENV.dbs.map((db) => db.id);

export const createdOptions = [
  { label: 'All', value: undefined },
  { label: 'Within 1 day', value: 'within_one_day' },
  { label: 'Within 1 week', value: 'within_one_week' },
  { label: 'Within 1 month', value: 'within_one_month' },
  { label: 'Within 1 year', value: 'within_one_year' },
] as const;

export const progressOptions = [
  { label: 'Waiting', value: 'waiting' },
  { label: 'Running', value: 'running' },
  { label: 'Finished', value: 'finished' },
  { label: 'Canceled', value: 'canceled' },
] as const;

export const validityOptions = [
  { label: 'Valid', value: 'valid' },
  { label: 'Invalid', value: 'invalid' },
  { label: 'Error', value: 'error' },
  { label: '-', value: 'null' },
] as const;

export const submittedOptions = [
  { label: 'All', value: undefined },
  { label: 'Submitted', value: true },
  { label: 'Not submitted', value: false },
] as const;

export const progresses = progressOptions.map((opt) => opt.value);
export const validities = validityOptions.map((opt) => opt.value);

export type Created = (typeof createdOptions)[number]['value'];
export type Progress = (typeof progressOptions)[number]['value'];
export type Validity = (typeof validityOptions)[number]['value'];
export type Submitted = (typeof submittedOptions)[number]['value'];
