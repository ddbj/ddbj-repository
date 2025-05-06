import ErrorMessage from 'repository/components/error-message';

import type { TOC } from '@ember/component/template-only';

<template>
  <h1 class="display-6">Error</h1>

  {{#if @model}}
    <ErrorMessage @error={{@model}} />
  {{/if}}
</template> satisfies TOC<{
  Args: {
    model: Error;
  };
}>;
