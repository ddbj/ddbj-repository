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
  ];

  dbs = ENV.dbs.map((db) => db.id);
  progresses = ['waiting', 'running', 'finished', 'canceled'];

  @tracked page?: number;
  @tracked pageBefore?: number;

  @tracked db?: string;
  @tracked created?: string;
  @tracked progress?: string;

  get selectedDBs() {
    return queryValueToArray(this.db, this.dbs);
  }

  get selectedProgresses() {
    return queryValueToArray(this.progress, this.progresses);
  }

  @action
  onSelectedDBsChange(selected: string[]) {
    this.page = undefined;
    this.db = arrayToQueryValue(selected, this.dbs);
  }

  @action
  onCreatedChange(created?: string) {
    this.page = undefined;
    this.created = created;
  }

  @action
  onSelectedProgressesChange(selected: string[]) {
    this.page = undefined;
    this.progress = arrayToQueryValue(selected, this.progresses);
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
