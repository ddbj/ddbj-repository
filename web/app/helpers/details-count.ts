import type { components } from 'schema/openapi';

type Results = components['schemas']['Validation']['results'];

export default function detailsCount(results: Results) {
  return results.reduce((acc: number, { details }) => acc + details.length, 0);
}
