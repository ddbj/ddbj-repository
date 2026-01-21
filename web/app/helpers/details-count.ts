export default function detailsCount(results: { details: unknown[] }[]): number {
  return results.reduce((acc: number, { details }) => acc + details.length, 0);
}
