import type { DBSchema } from 'schema/db';

/**
 * Type declarations for
 *    import config from 'ddbj-repository/config/environment'
 */
declare const config: {
  environment: string;
  modulePrefix: string;
  podModulePrefix: string;
  locationType: 'history' | 'hash' | 'none';
  rootURL: string;
  APP: Record<string, unknown>;
  apiURL: string;
  dbs: DBSchema[];
};

export default config;
