import type { components } from 'schema/openapi';

type Db = components['schemas']['Db'];
type SubmittableDb = components['schemas']['SubmittableDb'];

export const DB_LABELS: Record<Db, string> = {
  st26: 'ST.26',
  bioproject: 'BioProject',
  biosample: 'BioSample',
  dra: 'DRA',
};

// The databases a request can be created for here. DRA submissions are
// migrated from D-way and cannot be created yet.
export const SUBMITTABLE_DBS: SubmittableDb[] = ['st26', 'bioproject', 'biosample'];

export function isSubmittableDb(db: string): db is SubmittableDb {
  return (SUBMITTABLE_DBS as string[]).includes(db);
}

export default function dbLabel(db: string): string {
  return DB_LABELS[db as Db] ?? db;
}
