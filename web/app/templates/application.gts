import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { service } from '@ember/service';

import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';
import AttentionBanner from 'repository/components/attention-banner';
import ErrorMessage from 'repository/components/error-message';

import type CurrentUserService from 'repository/services/current-user';
import type ErrorModalService from 'repository/services/error-modal';
import type LoadingService from 'repository/services/loading';
import type ToastService from 'repository/services/toast';

const adminURL = ENV.adminURL;
const authURL = ENV.authURL;

export default class extends Component {
  @service declare currentUser: CurrentUserService;
  @service declare errorModal: ErrorModalService;
  @service declare loading: LoadingService;
  @service declare toast: ToastService;

  @action
  logout() {
    this.currentUser.logout();

    this.toast.show('Logged out.', 'success');
  }

  <template>
    {{pageTitle "DDBJ Repository"}}

    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
      <div class="container">
        <LinkTo @route="index" class="navbar-brand">DDBJ Repository</LinkTo>

        <div class="collapse navbar-collapse" id="navbarSupportedContent">
          {{#if this.currentUser.isLoggedIn}}
            <ul class="navbar-nav me-auto mb-2 mb-lg-0">
              <li class="nav-item">
                <LinkTo @route="index" class="nav-link">My submissions</LinkTo>
              </li>

              {{#if this.currentUser.user.isAdmin}}
                <li class="nav-item">
                  <a href={{adminURL}} class="nav-link">Administration</a>
                </li>
              {{/if}}
            </ul>

            <ul class="navbar-nav align-items-lg-center">
              <li class="nav-item me-lg-3">
                <LinkTo @route="new" class="btn btn-outline-light btn-sm">New submission</LinkTo>
              </li>

              <li class="nav-item dropdown">
                {{! Always the real account. Who is being acted *as* is the
                proxy bar's job, and saying it in two places invited reading
                the wrong one. }}
                <button type="button" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">
                  {{this.currentUser.user.uid}}
                </button>

                <ul class="dropdown-menu">
                  <li>
                    <LinkTo @route="account" class="dropdown-item">Account</LinkTo>
                  </li>

                  <li><hr class="dropdown-divider" /></li>

                  <li>
                    <button type="button" class="dropdown-item" {{on "click" this.logout}}>Logout</button>
                  </li>
                </ul>
              </li>
            </ul>
          {{/if}}
        </div>
      </div>
    </nav>

    {{! Who you are acting as, permanently visible. It used to be a "(proxy)"
    suffix inside a dropdown, which is not where you look before doing
    something on somebody else's behalf. }}
    {{#if this.currentUser.isProxyLoggedIn}}
      <div class="bg-dark text-white py-2" role="status">
        <div class="container d-flex align-items-center gap-3 flex-wrap">
          <span class="badge text-bg-warning font-monospace">PROXY</span>

          <span class="small">
            Viewing as
            <strong>{{this.currentUser.proxyUid}}</strong>
            <span class="text-white-50">— you are
              {{this.currentUser.user.uid}}. Actions are recorded as the proxy.</span>
          </span>

          <span class="flex-fill"></span>

          <button type="button" class="btn btn-outline-light btn-sm" {{on "click" this.currentUser.stopProxy}}>End proxy
            session</button>
        </div>
      </div>
    {{/if}}

    {{! A 401 arrived from somewhere. Deliberately a banner: there is no
    session expiry in this system, so this means "signed out elsewhere",
    and covering a half-finished form to announce it is the only part that
    would actually cost anything. }}
    {{#if this.currentUser.sessionExpired}}
      <div class="alert alert-warning border-0 rounded-0 mb-0 py-2" role="alert">
        <div class="container d-flex align-items-center gap-3 flex-wrap">
          <span>
            <strong>You are signed out.</strong>
            <span class="text-body-secondary">Log in again to continue — you will come back to this page.</span>
          </span>

          <span class="flex-fill"></span>

          <form action={{authURL}} method="POST">
            <button type="submit" class="btn btn-primary btn-sm">Log in again</button>
          </form>
        </div>
      </div>
    {{/if}}

    <AttentionBanner />

    {{#if this.loading.isLoading}}
      <div class="loading-bar" aria-busy="true">
        <span class="visually-hidden">Loading...</span>
      </div>
    {{/if}}

    <div class="position-relative">
      <main class="container py-4 position-relative">
        {{outlet}}
      </main>

      <div class="toast-container top-0 end-0 p-3">
        {{#each this.toast.data as |toast|}}
          <div
            id={{toast.id}}
            class="toast align-items-center text-bg-{{toast.color}} border-0"
            data-bs-delay="2000"
            role="alert"
            aria-live="assertive"
            aria-atomic="true"
            {{this.toast.register}}
          >
            <div class="d-flex">
              <div class="toast-body">{{toast.body}}</div>

              <button
                type="button"
                class="btn-close btn-close-white me-2 m-auto"
                data-bs-dismiss="toast"
                aria-label="Close"
              ></button>
            </div>
          </div>
        {{/each}}
      </div>
    </div>

    <div class="modal fade" tabindex="-1" {{this.errorModal.register}}>
      <div class="modal-dialog modal-dialog-centered modal-dialog-scrollable">
        <div class="modal-content">
          <div class="modal-header">
            <h5 class="modal-title">Error</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>

          <div class="modal-body">
            {{#if this.errorModal.error}}
              <ErrorMessage @error={{this.errorModal.error}} />
            {{/if}}
          </div>
        </div>
      </div>
    </div>
  </template>
}
