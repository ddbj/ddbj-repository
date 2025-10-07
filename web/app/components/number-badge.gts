import type { TOC } from '@ember/component/template-only';

interface Signature {
  Args: {
    number: number;
  };
}

export default <template>
  {{#if @number}}
    <span class="badge bg-secondary">{{@number}}</span>
  {{/if}}
</template> satisfies TOC<Signature>;
