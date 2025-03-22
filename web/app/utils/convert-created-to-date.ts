import { subDays, subWeeks, subMonths, subYears } from 'date-fns';

import type { Created } from 'repository/components/validations-search-form';

export default function convertCreatedToDate(created: NonNullable<Created>) {
  const now = new Date();

  switch (created) {
    case 'within_one_day':
      return subDays(now, 1);
    case 'within_one_week':
      return subWeeks(now, 1);
    case 'within_one_month':
      return subMonths(now, 1);
    case 'within_one_year':
      return subYears(now, 1);
    default:
      throw new Error(created satisfies never);
  }
}
