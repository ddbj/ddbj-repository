import { tracked } from '@glimmer/tracking';

import type Obj from 'ddbj-repository/models/obj';

export default class Source {
  obj: Obj;

  @tracked file?: File;
  @tracked path = '';
  @tracked destination = '';

  constructor(obj: Obj) {
    this.obj = obj;
  }

  get required() {
    const { optional, multiple } = this.obj.schema;

    return !optional || multiple;
  }

  toJSON() {
    const {
      file,
      path,
      destination,
      obj: { sourceType },
    } = this;

    if (!file && !path) return undefined;

    switch (sourceType) {
      case 'file':
        return { file, destination };
      case 'path':
        return { path, destination };
      default:
        throw new Error(sourceType satisfies never);
    }
  }
}
