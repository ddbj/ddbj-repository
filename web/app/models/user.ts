import { tracked } from '@glimmer/tracking';

import type { components } from 'schema/openapi';

type SubmittableDb = components['schemas']['SubmittableDb'];

export default class User {
  @tracked uid: string;
  @tracked apiKey: string;
  @tracked isAdmin: boolean;

  // What a request can be created for here, as the server says: BioProject
  // and BioSample open where their records can be checked.
  @tracked submittableDbs: SubmittableDb[];

  constructor(uid: string, apiKey: string, isAdmin: boolean, submittableDbs: SubmittableDb[]) {
    this.uid = uid;
    this.apiKey = apiKey;
    this.isAdmin = isAdmin;
    this.submittableDbs = submittableDbs;
  }

  canSubmitTo(db: string): db is SubmittableDb {
    return (this.submittableDbs as string[]).includes(db);
  }
}
