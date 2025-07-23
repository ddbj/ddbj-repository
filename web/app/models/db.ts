import Obj from 'repository/models/obj';
import schema from 'schema/db';

type Schema = (typeof schema)[number];

export const dbNames = schema.map(({ id }) => id);

export type DBName = (typeof dbNames)[number];

export default class DB {
  schema: Schema;
  objs: {
    file: Obj[];
    ddbjRecord: Obj[];
  };

  constructor(schema: Schema) {
    this.schema = schema;
    this.objs = {
      file: this.schema.objects.file.map((obj) => new Obj(this, obj)),
      ddbjRecord: this.schema.objects.ddbj_record.map((obj) => new Obj(this, obj))
    };
  }

  toJSON(type: "file" | "ddbjRecord" ) {
    return this.objs[type].reduce(
      (acc, obj) => ({
        ...acc,
        [obj.schema.id]: obj.toJSON(),
      }),
      { db: this.schema.id },
    );
  }
}
