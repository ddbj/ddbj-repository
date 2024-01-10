export default function toJson(obj: unknown) {
  return JSON.stringify(obj, null, 2);
}
