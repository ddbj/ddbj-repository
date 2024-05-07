import '@glint/environment-ember-loose';

import type PageTitle from 'ember-page-title/template-registry';
import type StyleModifier from 'ember-style-modifier/template-registry';
import type TruthHelpers from 'ember-truth-helpers/template-registry';

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry extends PageTitle, StyleModifier, TruthHelpers {}
}
