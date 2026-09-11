import type { components } from 'schema/openapi';

type RecordNode = components['schemas']['RecordNode'];

// A node with every field present and nothing in it. RecordNode closes
// over its properties — one shape for six kinds, so a fixture that leaves
// a field out is not a smaller node, it is an invalid one.
export const emptyNode: RecordNode = {
  kind: 'empty',
  columns: null,
  hidden_columns: null,
  total: null,
  shown: null,
  hidden: 0,
  value: null,
  free_text: false,
  fields: null,
  items: null,
  cells: null,
};

export function valueNode(value: string | number): RecordNode {
  return { ...emptyNode, kind: 'value', value };
}
