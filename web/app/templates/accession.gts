import { concat } from '@ember/helper';

import { pageTitle } from 'ember-page-title';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];

export default <template>
  {{pageTitle (concat "Accession " @model.accession.number)}}

  {{outlet}}
</template> satisfies TOC<{
  Args: {
    model: {
      accession: Accession;
    };
  };
}>;
