export default function formatDatetime(date: Date | string): string {
  if (typeof date === 'string') {
    date = new Date(date);
  }

  const year = padZero(date.getFullYear());
  const month = padZero(date.getMonth() + 1);
  const _date = padZero(date.getDate());
  const hours = padZero(date.getHours());
  const minutes = padZero(date.getMinutes());
  const seconds = padZero(date.getSeconds());

  return `${year}-${month}-${_date} ${hours}:${minutes}:${seconds}`;
}

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry {
    'format-datetime': typeof formatDatetime;
  }
}

function padZero(n: number) {
  return n.toString().padStart(2, '0');
}
