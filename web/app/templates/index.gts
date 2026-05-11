import Component from '@glimmer/component';
import { service } from '@ember/service';
import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';

import NavCard from 'repository/components/nav-card';

import type CurrentUserService from 'repository/services/current-user';

const authURL = new URL('/auth/keycloak', ENV.apiURL).href;

export default class extends Component {
  @service declare currentUser: CurrentUserService;

  <template>
    {{pageTitle "DDBJ Repository"}}

    {{#if this.currentUser.isLoggedIn}}
      <h1 class="mb-6 text-3xl font-light">DDBJ Repository</h1>

      <div class="grid gap-4 md:grid-cols-3">
        <NavCard @route="db" @model="st26" @title="ST.26" @description="Patent sequence listings (ST.26 XML)." />
        <NavCard @route="db" @model="bioproject" @title="BioProject" @description="Biological project metadata." />
        <NavCard @route="db" @model="biosample" @title="BioSample" @description="Biological sample metadata." />
      </div>
    {{else}}
      <div class="flex justify-center py-12">
        <div class="w-full sm:max-w-md">
          <div class="rounded-lg border border-gray-200 bg-white p-8 text-center shadow-sm sm:p-10">
            <h1 class="mb-2 text-2xl font-medium">DDBJ Repository</h1>
            <p class="mb-6 text-gray-600">Sign in with your DDBJ Account to continue.</p>

            <form action={{authURL}} method="POST">
              <button
                type="submit"
                class="rounded-lg bg-blue-600 px-8 py-3 text-lg font-medium text-white shadow-sm transition hover:-translate-y-px hover:bg-blue-700 hover:shadow-md focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:outline-none active:translate-y-0 active:bg-blue-800 active:shadow-sm"
              >
                Login with DDBJ Account
              </button>
            </form>
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}
