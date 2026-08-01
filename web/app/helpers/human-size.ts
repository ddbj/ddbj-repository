// Sizes a reader can act on. The one question an attachment's size
// answers is "is this the corrected spreadsheet or the whole submission
// again", and bytes do not answer it.
const UNITS = ['B', 'KB', 'MB', 'GB', 'TB'];

export default function humanSize(bytes: number): string {
  if (!bytes) return '0 B';

  const exponent = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), UNITS.length - 1);
  const value = bytes / 1024 ** exponent;

  return `${exponent === 0 ? value : value.toFixed(1)} ${UNITS[exponent]}`;
}
