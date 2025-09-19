import formatDatetime from 'repository/helpers/format-datetime';

import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

type Accession = components['schemas']['Accession'];

export default <template>
  <h1 class="display-6 mb-4">Accession #{{@accession.number}}</h1>

  <dl class="d-flex flex-wrap row-gap-1 column-gap-5">
    <div>
      <dt>Number</dt>
      <dd>{{@accession.number}}</dd>
    </div>

    <div>
      <dt>Entry ID</dt>
      <dd>{{@accession.entry_id}}</dd>
    </div>

    <div>
      <dt>Version</dt>
      <dd>{{@accession.version}}</dd>
    </div>

    <div>
      <dt>Last updated</dt>
      <dd>{{formatDatetime @accession.last_updated_at}}</dd>
    </div>
  </dl>
</template> satisfies TOC<{
  Args: {
    accession: Accession;
  };
}>;
