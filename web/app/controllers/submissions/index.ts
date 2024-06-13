import Controller from '@ember/controller';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';

import type { Model } from 'ddbj-repository/routes/submissions/index';

export default class SubmissionsIndexController extends Controller {
  queryParams = [
    {
      page: { type: 'number' } as const,
      db: { type: 'string' } as const,
      created: { type: 'string' } as const,
    },
  ];

  declare model: Model;

  dbs = ENV.dbs.map((db) => db.id);

  @tracked page = 1;
  @tracked pageBefore?: number;

  @tracked db?: string;
  @tracked created?: string;

  get selectedDBs() {
    return queryValueToArray(this.db, this.dbs);
  }

  @action
  onSelectedDBsChange(selected: string[]) {
    this.page = 1;
    this.db = arrayToQueryValue(selected, this.dbs);
  }

  @action
  onCreatedChange(created?: string) {
    this.page = 1;
    this.created = created;
  }
}

function queryValueToArray(value: string | undefined, all: string[]) {
  switch (value) {
    case undefined:
      return all;
    case '':
      return [];
    default:
      return value.split(',');
  }
}

function arrayToQueryValue(values: string[], all: unknown[]) {
  return values.length === all.length ? undefined : values.join(',');
}
