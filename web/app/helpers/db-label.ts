import type { components } from 'schema/openapi';

type Db = components['schemas']['Db'];

export const DB_LABELS: Record<Db, string> = {
  st26: 'ST.26',
  bioproject: 'BioProject',
  biosample: 'BioSample',
  dra: 'DRA',
};

export default function dbLabel(db: string): string {
  return DB_LABELS[db as Db] ?? db;
}
