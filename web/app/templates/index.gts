import Component from '@glimmer/component';
import { action } from '@ember/object';
import { tracked } from '@glimmer/tracking';
import { LinkTo } from '@ember/routing';
import { fn } from '@ember/helper';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { pageTitle } from 'ember-page-title';

import Pagination from 'repository/components/pagination';
import dbLabel from 'repository/helpers/db-label';
import formatDatetime from 'repository/helpers/format-datetime';
import { DB_OPTIONS, PHASE_TABS, STATUS_OPTIONS, isChecked } from 'repository/controllers/index';
import { requestState, toneClasses } from 'repository/utils/request-state';

import type Controller from 'repository/controllers/index';
import type CurrentUserService from 'repository/services/current-user';
import type { components } from 'schema/openapi';

type Summary = components['schemas']['SubmissionRequestSummary'];

interface Signature {
  Args: {
    model: {
      requests: Summary[];
      totalPages: number;
      unfinishedCount: number;
      finishedCount: number;
    } | null;

    controller: Controller;
  };
}

// "Where it is now", in the same words the request's own page uses.
const stateLabel = (request: Summary) => requestState(request).label;
const stateBadgeClass = (request: Summary) => toneClasses(requestState(request).tone).badge;

export default class extends Component<Signature> {
  @service declare currentUser: CurrentUserService;

  // Null until the reader says otherwise, so an applied filter is never
  // invisible — a filtered list that looks unfiltered is a lie.
  @tracked filtersOpen: boolean | null = null;

  get showFilters() {
    return this.filtersOpen ?? this.args.controller.hasActiveFilters;
  }

  @action
  toggleFilters() {
    this.filtersOpen = !this.showFilters;
  }

  get tabs() {
    return PHASE_TABS.map((tab) => ({
      ...tab,
      active: this.args.controller.phase === tab.value,
      count:
        tab.value === 'unfinished'
          ? this.args.model?.unfinishedCount
          : tab.value === 'finished'
            ? this.args.model?.finishedCount
            : undefined,
    }));
  }

  // The counts drive the tabs, but they must never be what decides
  // whether the list renders: rows on screen beat a missing header.
  get hasAnySubmission() {
    const model = this.args.model;

    return Boolean(model && (model.requests.length > 0 || model.unfinishedCount + model.finishedCount > 0));
  }

  <template>
    {{pageTitle "DDBJ Repository"}}

    {{! The route redirects to `login` when there is no session, so this
    template can be about one thing. }}
    {{! No "New submission" button here: it lives in the nav, where it is
    reachable from every screen, and two of them a few pixels apart just
    made the reader choose between identical options. The empty state below
    still offers it, because there it is the whole point of the screen
    rather than a second copy of a control already on it. }}
    <h1 class="display-6 mb-3">My submissions</h1>

    {{#if this.hasAnySubmission}}
      {{! Finished submissions never stop accumulating, so a lab with 500
      released records cannot find the three that are still moving unless
      the two halves are separated. The counts come from the same response
      as the rows, so the tab you are not on still knows its size. }}
      <ul class="nav nav-tabs mb-3">
        {{#each this.tabs as |tab|}}
          <li class="nav-item">
            <button
              type="button"
              class="nav-link {{if tab.active 'active'}}"
              data-test-phase={{tab.value}}
              {{on "click" (fn @controller.selectPhase tab.value)}}
            >
              {{tab.label}}
              {{#if tab.count}}
                <span class="badge text-bg-secondary ms-1">{{tab.count}}</span>
              {{/if}}
            </button>
          </li>
        {{/each}}
      </ul>

      {{#if @controller.needsAction}}
        <p class="mb-3">
          <span class="badge text-bg-warning">Waiting on you</span>
          <button type="button" class="btn btn-link btn-sm" {{on "click" @controller.clearFilters}}>
            Show everything
          </button>
        </p>
      {{/if}}

      {{! Folded away by default. Four facets stacked above the table put
      the controls where the submissions should be, and the tabs answer
      the question most visits are actually asking. }}
      <p class="mb-2">
        <button type="button" class="btn btn-link btn-sm p-0" {{on "click" this.toggleFilters}}>
          {{if this.showFilters "Hide filters" "Filters"}}
        </button>
      </p>

      {{#if this.showFilters}}
        <form class="card mb-4" {{on "submit" @controller.applyFilters}}>
          <div class="card-body">
            <div class="row mb-2">
              <div class="col-sm-2 fw-semibold">Database</div>
              <div class="col-sm-10">
                {{#each DB_OPTIONS as |opt|}}
                  <div class="form-check form-check-inline">
                    <input
                      type="checkbox"
                      class="form-check-input"
                      id="db-{{opt.value}}"
                      name="db"
                      value={{opt.value}}
                      checked={{isChecked @controller.db opt.value}}
                    />
                    <label class="form-check-label" for="db-{{opt.value}}">{{opt.label}}</label>
                  </div>
                {{/each}}

                <div class="small">
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0 me-3"
                    data-test-select="db"
                    {{on "click" (fn @controller.setFacet "db" true)}}
                  >Select all</button>
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0"
                    data-test-deselect="db"
                    {{on "click" (fn @controller.setFacet "db" false)}}
                  >Deselect all</button>
                </div>
              </div>
            </div>

            <div class="row mb-2">
              <div class="col-sm-2 fw-semibold">Status</div>
              <div class="col-sm-10">
                {{#each STATUS_OPTIONS as |opt|}}
                  <div class="form-check form-check-inline">
                    <input
                      type="checkbox"
                      class="form-check-input"
                      id="status-{{opt.value}}"
                      name="status"
                      value={{opt.value}}
                      checked={{isChecked @controller.status opt.value}}
                    />
                    <label class="form-check-label text-capitalize" for="status-{{opt.value}}">{{opt.label}}</label>
                  </div>
                {{/each}}

                <div class="small">
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0 me-3"
                    data-test-select="status"
                    {{on "click" (fn @controller.setFacet "status" true)}}
                  >Select all</button>
                  <button
                    type="button"
                    class="btn btn-link btn-sm p-0"
                    data-test-deselect="status"
                    {{on "click" (fn @controller.setFacet "status" false)}}
                  >Deselect all</button>
                </div>
              </div>
            </div>

            <div class="row mb-2">
              <label for="source-id-filter" class="col-sm-2 col-form-label fw-semibold">Source ID</label>
              <div class="col-sm-10 col-md-5 col-lg-4">
                <input
                  id="source-id-filter"
                  type="search"
                  class="form-control form-control-sm"
                  name="sourceId"
                  placeholder="PSUB / SSUB ..."
                  value={{@controller.sourceId}}
                />
              </div>
            </div>

            <div class="row mb-2">
              <label for="accession-filter" class="col-sm-2 col-form-label fw-semibold">Accession</label>
              <div class="col-sm-10 col-md-5 col-lg-4">
                <input
                  id="accession-filter"
                  type="search"
                  class="form-control form-control-sm"
                  name="accession"
                  placeholder="PRJDB / SAMD ..."
                  value={{@controller.accession}}
                />
              </div>
            </div>

            <div class="row">
              <div class="col-sm-10 offset-sm-2">
                <button type="submit" class="btn btn-primary btn-sm">Filter</button>
                {{#if @controller.hasActiveFilters}}
                  <button type="button" class="btn btn-link btn-sm" {{on "click" @controller.clearFilters}}>
                    Clear filters
                  </button>
                {{/if}}
              </div>
            </div>
          </div>
        </form>
      {{/if}}

      {{#if @model.requests.length}}
        <table class="table border align-middle">
          <thead class="table-light">
            <tr>
              <th>ID</th>
              <th>Database</th>
              {{! Not the ingest status enum: `waiting_application` and
              `applied` are both "nothing to do", and neither phrase tells
              the submitter that. See requestState. }}
              <th>Where it is now</th>
              <th>Source ID</th>
              <th>Accession</th>
              <th>Submitted</th>
            </tr>
          </thead>

          <tbody>
            {{#each @model.requests as |request|}}
              <tr>
                <td>
                  <LinkTo @route="request" @model={{request.id}}>
                    #{{request.id}}
                  </LinkTo>
                </td>

                <td>{{dbLabel request.db}}</td>

                <td>
                  <span class="badge {{stateBadgeClass request}}">{{stateLabel request}}</span>
                </td>

                <td>{{or request.source_id "-"}}</td>
                <td>
                  {{#if request.accession_count}}
                    {{request.first_accession}}
                    {{#unless (eq request.accession_count 1)}}
                      <span class="text-body-secondary ms-1">({{request.accession_count}})</span>
                    {{/unless}}
                  {{else}}
                    -
                  {{/if}}
                </td>
                <td>{{formatDatetime request.created_at}}</td>
              </tr>
            {{/each}}
          </tbody>
        </table>

        {{! LinkTo carries the route's other query params (phase, filters)
        through on its own — only `page` needs restating. }}
        <Pagination @route="index" @current={{@controller.page}} @total={{@model.totalPages}} />
      {{else}}
        <p class="text-body-secondary">Nothing here right now.</p>
      {{/if}}
    {{else}}
      <p class="text-body-secondary">
        You have no submission requests yet.
        <LinkTo @route="new">Submit a new one</LinkTo>
        to get started.
      </p>
    {{/if}}
  </template>
}
