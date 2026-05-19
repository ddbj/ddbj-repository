export function getText(data: FormData, key: string): string {
  const value = data.get(key);

  return typeof value === 'string' ? value : '';
}
