import Controller from '@ember/controller';
import { action } from '@ember/object';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';

import type { Model } from 'ddbj-repository/routes/validations/index';
import type Router from '@ember/routing/router';

export default class ValidationsIndexController extends Controller {
  @service declare router: Router;

  declare model: Model;

  queryParams = [
    { page: { type: 'number' } as const },
    { db: { type: 'string' } as const },
    { created: { type: 'string' } as const },
    { progress: { type: 'string' } as const },
    { validity: { type: 'string' } as const },
    { submitted: { type: 'boolean' } as const },
  ];

  dbs = ENV.dbs.map((db) => db.id);
  progresses = ['waiting', 'running', 'finished', 'canceled'];
  validities = ['valid', 'invalid', 'error', 'null'];

  @tracked page = 1;
  @tracked pageBefore?: number;

  @tracked db?: string;
  @tracked created?: string;
  @tracked progress?: string;
  @tracked validity?: string;
  @tracked submitted?: boolean;

  get selectedDBs() {
    return queryValueToArray(this.db, this.dbs);
  }

  get selectedProgresses() {
    return queryValueToArray(this.progress, this.progresses);
  }

  get selectedValidities() {
    return queryValueToArray(this.validity, this.validities);
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

  @action
  onSelectedProgressesChange(selected: string[]) {
    this.page = 1;
    this.progress = arrayToQueryValue(selected, this.progresses);
  }

  @action
  onSelectedValiditiesChange(selected: string[]) {
    this.page = 1;
    this.validity = arrayToQueryValue(selected, this.validities);
  }

  @action
  onSubmittedChange(submitted?: boolean) {
    this.page = 1;
    this.submitted = submitted;
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
