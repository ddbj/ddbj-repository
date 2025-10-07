import NumberBadge from 'repository/components/number-badge';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Results = components['schemas']['Validation']['results'];

interface Signature {
  Args: {
    results: Results;
  };
}

export default <template><NumberBadge @number={{detailsCount @results}} /></template> satisfies TOC<Signature>;

function detailsCount(results: Results) {
  return results.reduce((acc, { details }) => acc + details.length, 0);
}
