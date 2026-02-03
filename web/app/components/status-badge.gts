import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    status: components['schemas']['SubmissionOperationStatus'];
  };
}

export default <template>
  <span class="badge {{colorClass @status}} text-capitalize">{{humanize @status}}</span>
</template> satisfies TOC<Signature>;

function colorClass(validity: Signature['Args']['status']): string {
  switch (validity) {
    case 'waiting_validation':
      return 'text-bg-secondary';
    case 'validating':
      return 'text-bg-warning';
    case 'validation_failed':
      return 'text-bg-danger';
    case 'ready_to_apply':
      return 'text-bg-success';
    case 'waiting_application':
      return 'text-bg-secondary';
    case 'applying':
      return 'text-bg-warning';
    case 'applied':
      return 'text-bg-primary';
    case 'application_failed':
      return 'text-bg-danger';
    case 'no_change':
      return 'text-bg-light';
    default:
      throw new Error(validity satisfies never);
  }
}

function humanize(str: string): string {
  return str.replace(/_/g, ' ');
}
