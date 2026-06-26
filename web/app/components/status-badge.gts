import type { TOC } from '@ember/component/template-only';
import type { components } from 'schema/openapi';

interface Signature {
  Args: {
    status: components['schemas']['SubmissionOperationStatus'];

    // When true, render an "Accessioned" badge instead of the raw
    // status. Lifecycle past `applied` is not modelled in the enum, so
    // callers that know an accession has been issued surface that here.
    hasAccession?: boolean;
  };
}

export default <template>
  {{#if @hasAccession}}
    <span class="badge text-bg-success">Accessioned</span>
  {{else}}
    <span class="badge {{colorClass @status}} text-capitalize">{{humanize @status}}</span>
  {{/if}}
</template> satisfies TOC<Signature>;

function colorClass(status: Signature['Args']['status']): string {
  switch (status) {
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
      throw new Error(status satisfies never);
  }
}

function humanize(str: string): string {
  return str.replace(/_/g, ' ');
}
