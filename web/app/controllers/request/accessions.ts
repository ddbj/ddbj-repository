import Controller from '@ember/controller';
import { tracked } from '@glimmer/tracking';

import type { components } from 'schema/openapi';

type SubmissionAccession = components['schemas']['SubmissionAccession'];

export default class extends Controller {
  queryParams = [
    {
      page: { type: 'number' } as const,
    },
  ];

  @tracked page = 1;

  declare model: { requestId: number; accessions: SubmissionAccession[]; totalPages: number };

  // What each record states arrives as labelled facts, because a review
  // link can hold all three databases at once and they agree on nothing
  // past a name. A submission is one database, so on this screen the
  // labels are the same on every row — and a column of LOCUS dates can be
  // read down, which a stack of "LOCUS date 2026-01-15" cannot.
  //
  // The union rather than the first row's: `AccessionFacts` drops a fact
  // the record does not carry, so a sample with no organism would
  // otherwise take the column away from the page.
  get columns() {
    const seen = new Set<string>();

    for (const accession of this.model.accessions) {
      for (const detail of accession.details) seen.add(detail.label);
    }

    return [...seen];
  }

  // A row's facts by label, so a record missing one leaves an empty cell
  // rather than shifting the row along by a column.
  detailsFor = (accession: SubmissionAccession) => {
    const byLabel = new Map(accession.details.map((detail) => [detail.label, detail.value]));

    return this.columns.map((label) => byLabel.get(label));
  };
}
