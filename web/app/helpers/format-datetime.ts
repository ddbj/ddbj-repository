export default function formatDatetime(date: Date | string) {
  if (typeof date === 'string') {
    date = new Date(date);
  }

  return `${date.toLocaleDateString('ja-JP')} ${date.toLocaleTimeString('ja-JP')}`;
}
