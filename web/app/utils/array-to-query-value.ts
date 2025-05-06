export default function arrayToQueryValue(values: string[], all: unknown[]) {
  return values.length === all.length ? undefined : values.join(',');
}
