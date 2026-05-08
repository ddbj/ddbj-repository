'use strict';

module.exports = {
  extends: ['stylelint-config-standard'],

  rules: {
    'import-notation': 'string',
    'at-rule-no-unknown': [
      true,
      { ignoreAtRules: ['theme', 'utility', 'variant', 'custom-variant', 'apply', 'reference', 'source', 'plugin'] },
    ],
  },
};
