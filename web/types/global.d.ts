import '@glint/environment-ember-loose';

import { HelperLike } from '@glint/template';

import type PageTitle from 'ember-page-title/template-registry';
import type StyleModifier from 'ember-style-modifier/template-registry';
import type TruthHelpers from 'ember-truth-helpers/template-registry';

declare module '@glint/environment-ember-loose/registry' {
  export default interface Registry extends PageTitle, StyleModifier, TruthHelpers {
    perform: HelperLike<{
      Args: {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        Positional: [any];
      };

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      Return: (...args: any[]) => any;
    }>;
  }
}
