type DBSchema = {
  id: string;
  objects: ObjSchema[];
};

type ObjSchema = {
  id: string;
  optional: boolean;
  multiple: boolean;
};
