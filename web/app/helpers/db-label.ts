const LABELS: Record<string, string> = {
  st26: 'ST.26',
  bioproject: 'BioProject',
  biosample: 'BioSample',
};

export default function dbLabel(db: string): string {
  return LABELS[db] ?? db;
}
