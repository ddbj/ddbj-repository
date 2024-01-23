import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';

import Source from 'ddbj-repository/models/source';

import type DB from 'ddbj-repository/models/db';
import type { ObjSchema } from 'ddbj-repository/models/schema';

export default class Obj {
  db: DB;
  schema: ObjSchema;

  @tracked sourceType: 'file' | 'path' = 'file';
  @tracked sources: Source[];

  constructor(db: DB, schema: ObjSchema) {
    const { required, multiple } = schema;

    this.db = db;
    this.schema = schema;
    this.sources = !required && multiple ? [] : [new Source(this)];
  }

  get canRemoveSource() {
    return !this.schema.required || this.sources.length > 1;
  }

  @action
  addSource() {
    this.sources = [...this.sources, new Source(this)];
  }

  @action
  removeSource(source: Source) {
    this.sources = this.sources.filter((_source) => _source !== source);
  }

  toJSON() {
    const { schema, sources } = this;

    return schema.multiple ? sources.map((source) => source.toJSON()) : sources[0]!.toJSON();
  }
}
