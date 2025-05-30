import Component from '@glimmer/component';
import { LinkTo } from '@ember/routing';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';

import { pageTitle } from 'ember-page-title';

import ErrorMessage from 'repository/components/error-message';

import type CurrentUserService from 'repository/services/current-user';
import type ErrorModalService from 'repository/services/error-modal';
import type LoadingService from 'repository/services/loading';
import type ToastService from 'repository/services/toast';

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
                <LinkTo @route="validations" class="nav-link">Validations</LinkTo>
              </li>

              <li class="nav-item">
                <LinkTo @route="submissions" class="nav-link">Submissions</LinkTo>
              </li>

              {{#if this.currentUser.user.isAdmin}}
                <li class="nav-item">
                  <LinkTo @route="admin" class="nav-link">Administration</LinkTo>
                </li>
              {{/if}}
            </ul>

            <ul class="navbar-nav">
              <li class="nav-item dropdown">
                <button type="button" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false">
                  {{#if this.currentUser.proxyUid}}
                    {{this.currentUser.proxyUid}}
                    (proxy)
                  {{else}}
                    {{this.currentUser.user.uid}}
                  {{/if}}
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
