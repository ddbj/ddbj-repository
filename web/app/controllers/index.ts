import Controller from '@ember/controller';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

export interface FilterOption {
  value: string;
  label: string;
}

export const DB_OPTIONS: FilterOption[] = [
  { value: 'st26', label: 'ST.26' },
  { value: 'bioproject', label: 'BioProject' },
  { value: 'biosample', label: 'BioSample' },
];

export const STATUS_OPTIONS: FilterOption[] = [
  'waiting_validation',
  'validating',
  'validation_failed',
  'ready_to_apply',
  'waiting_application',
  'applying',
  'applied',
  'application_failed',
  'no_change',
].map((value) => ({ value, label: value.replace(/_/g, ' ') }));

export default class extends Controller {
  queryParams = ['db', 'status', 'sourceId', { page: { type: 'number' } as const }];

  // The applied filter — the checked subset for each facet. An empty
  // array means "no constraint" (every value), so the param drops out of
  // the URL. The checkboxes are only read on submit, so editing them
  // never re-queries or resets mid-edit.
  @tracked db: string[] = [];
  @tracked status: string[] = [];
  @tracked sourceId = '';
  @tracked page = 1;

  @action
  applyFilters(e: Event) {
    e.preventDefault();
    const data = new FormData(e.target as HTMLFormElement);

    this.db = normalize(
      data.getAll('db') as string[],
      DB_OPTIONS.map((o) => o.value),
    );
    this.status = normalize(
      data.getAll('status') as string[],
      STATUS_OPTIONS.map((o) => o.value),
    );
    const sourceId = data.get('sourceId');
    this.sourceId = typeof sourceId === 'string' ? sourceId.trim() : '';
    this.page = 1;
  }

  // Check / uncheck every box in a facet. Operates on the DOM directly
  // (the checkboxes are uncontrolled until Filter is pressed), so it does
  // not query — the user presses Filter to apply.
  @action
  setFacet(name: string, checked: boolean, e: Event) {
    const form = (e.currentTarget as HTMLElement).closest('form');
    form?.querySelectorAll<HTMLInputElement>(`input[name="${name}"]`).forEach((box) => {
      box.checked = checked;
    });
  }

  @action
  clearFilters() {
    this.db = [];
    this.status = [];
    this.sourceId = '';
    this.page = 1;
  }

  get hasActiveFilters(): boolean {
    return this.db.length > 0 || this.status.length > 0 || this.sourceId.length > 0;
  }
}

// All-checked and none-checked both mean "no constraint" (show every
// value) — the standard faceted-filter convention, matching the admin
// list. Only a proper subset becomes an actual filter.
function normalize(selected: string[], all: string[]): string[] {
  return selected.length === 0 || selected.length === all.length ? [] : selected;
}

export function isChecked(selected: string[], value: string): boolean {
  return selected.length === 0 || selected.includes(value);
}
