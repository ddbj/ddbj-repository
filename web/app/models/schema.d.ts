export interface DBSchema {
  id: string;
  objects: ObjSchema[];
}

export interface ObjSchema {
  id: string;
  optional: boolean;
  multiple: boolean;
}
