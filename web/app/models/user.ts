import { tracked } from '@glimmer/tracking';

export default class User {
  @tracked uid: string;
  @tracked apiKey: string;
  @tracked isAdmin: boolean;

  constructor(uid: string, apiKey: string, isAdmin: boolean) {
    this.uid = uid;
    this.apiKey = apiKey;
    this.isAdmin = isAdmin;
  }
}
