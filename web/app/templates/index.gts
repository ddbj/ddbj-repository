import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { service } from '@ember/service';
import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';

import type CurrentUserService from 'repository/services/current-user';

const authURL = new URL('/auth/keycloak', ENV.apiURL).href;

export default class extends Component {
  @service declare currentUser: CurrentUserService;

  <template>
    {{pageTitle "DDBJ Repository"}}

    {{#if this.currentUser.isLoggedIn}}
      <h1 class="display-6 mb-4">DDBJ Repository</h1>

      <div class="row g-3">
        <div class="col-md-4">
          <LinkTo @route="db" @model="st26" class="card text-decoration-none h-100">
            <div class="card-body">
              <h2 class="card-title h5">ST.26</h2>
              <p class="card-text text-body-secondary mb-0">Patent sequence listings (ST.26 XML).</p>
            </div>
          </LinkTo>
        </div>

        <div class="col-md-4">
          <LinkTo @route="db" @model="bioproject" class="card text-decoration-none h-100">
            <div class="card-body">
              <h2 class="card-title h5">BioProject</h2>
              <p class="card-text text-body-secondary mb-0">Biological project metadata.</p>
            </div>
          </LinkTo>
        </div>

        <div class="col-md-4">
          <LinkTo @route="db" @model="biosample" class="card text-decoration-none h-100">
            <div class="card-body">
              <h2 class="card-title h5">BioSample</h2>
              <p class="card-text text-body-secondary mb-0">Biological sample metadata.</p>
            </div>
          </LinkTo>
        </div>
      </div>
    {{else}}
      <div class="row justify-content-center py-5">
        <div class="col-12 col-sm-10 col-md-8 col-lg-6">
          <div class="card shadow-sm">
            <div class="card-body p-4 p-md-5 text-center">
              <h1 class="h3 mb-2">DDBJ Repository</h1>
              <p class="text-body-secondary mb-4">Sign in with your DDBJ Account to continue.</p>

              <form action={{authURL}} method="POST">
                <button type="submit" class="btn btn-primary btn-lg">Login with DDBJ Account</button>
              </form>
            </div>
          </div>
        </div>
      </div>
    {{/if}}
  </template>
}
