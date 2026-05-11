import { LinkTo } from '@ember/routing';

import type { TOC } from '@ember/component/template-only';

interface Signature {
  Args: {
    title: string;
    description?: string;
    route: string;
    model?: string;
  };
}

const NavCard = <template>
  <LinkTo
    @route={{@route}}
    @model={{@model}}
    class="flex h-full flex-col rounded-lg border border-gray-200 bg-white p-6 no-underline shadow-sm transition hover:-translate-y-px hover:border-gray-300 hover:shadow-md"
  >
    <h2 class="mb-2 text-lg font-medium text-gray-900">{{@title}}</h2>
    {{#if @description}}
      <p class="m-0 text-gray-600">{{@description}}</p>
    {{/if}}
  </LinkTo>
</template> satisfies TOC<Signature>;

export default NavCard;
