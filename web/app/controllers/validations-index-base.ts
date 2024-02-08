import Controller from '@ember/controller';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import ENV from 'ddbj-repository/config/environment';

import type { Model } from 'ddbj-repository/routes/validations-index-base';

export default abstract class ValidationsIndexBaseController extends Controller {
  declare model: Model;

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
