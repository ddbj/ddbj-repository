import Component from '@glimmer/component';
import { action } from '@ember/object';
import { on } from '@ember/modifier';
import { service } from '@ember/service';
import { tracked } from '@glimmer/tracking';
import { concat, uniqueId } from '@ember/helper';

import { pageTitle } from 'ember-page-title';
import { task } from 'ember-concurrency';
import style from 'ember-style-modifier';

import autoRefresh from 'repository/modifiers/auto-refresh';

import type { RequestManager } from '@warp-drive/core';
import type RouterService from '@ember/routing/router-service';
import type { Model } from 'repository/routes/admin/regenerate-flatfiles';
import type { TOC } from '@ember/component/template-only';

class RegenerateFlatfilesForm extends Component<{ Args: { model: Model } }> {
  @service declare requestManager: RequestManager;
  @service declare router: RouterService;

  @tracked date = '';
  @tracked force = false;

  get loading() {
    return this.args.model.status.loading;
  }

  get progress() {
    const { total, processed } = this.args.model.status;

    if (total === null || processed === null) return null;

    return {
      total,
      processed,
      percent: total === 0 ? 100 : Math.round((processed / total) * 100),
    };
  }

  get completed() {
    return (
      this.submitTask.lastSuccessful &&
      !this.loading &&
      this.progress &&
      this.progress.processed === this.progress.total
    );
  }

  get canSubmit() {
    return this.date && !this.loading && !this.submitTask.isRunning;
  }

  @action
  setDate(e: Event) {
    this.date = (e.target as HTMLInputElement).value;
  }

  @action
  setForce(e: Event) {
    this.force = (e.target as HTMLInputElement).checked;
  }

  submitTask = task(async (e: Event) => {
    e.preventDefault();

    await this.requestManager.request({
      url: '/admin/regenerate_flatfiles',
      method: 'POST',
      data: { date: this.date, force: this.force },
    });

    this.router.refresh();
  });

  <template>
    <div {{autoRefresh while=this.loading interval=3000}}>
      <div class="card">
        <div class="card-body">
          <form {{on "submit" this.submitTask.perform}}>
            <div class="mb-3">
              {{#let (uniqueId) as |id|}}
                <label for={{id}} class="form-label">LOCUS Date</label>
                <input
                  type="date"
                  value={{this.date}}
                  id={{id}}
                  class="form-control"
                  disabled={{this.loading}}
                  {{on "input" this.setDate}}
                />
              {{/let}}
            </div>

            <div class="form-check mb-3">
              {{#let (uniqueId) as |id|}}
                <input
                  type="checkbox"
                  checked={{this.force}}
                  id={{id}}
                  class="form-check-input"
                  disabled={{this.loading}}
                  {{on "change" this.setForce}}
                />
                <label for={{id}} class="form-check-label">
                  Force update all submissions (even if content is unchanged)
                </label>
              {{/let}}
            </div>

            <button type="submit" class="btn btn-primary" disabled={{unless this.canSubmit true}}>
              Regenerate
            </button>
          </form>
        </div>
      </div>

      {{#if this.loading}}
        <div class="card mt-3">
          <div class="card-body">
            {{#if this.progress}}
              <p class="mb-2">Processing: {{this.progress.processed}} / {{this.progress.total}} submissions</p>

              <div class="progress">
                <div class="progress-bar" role="progressbar" {{style width=(concat this.progress.percent "%")}}></div>
              </div>
            {{else}}
              <p class="mb-0">Starting...</p>
            {{/if}}
          </div>
        </div>
      {{else if this.completed}}
        <div class="alert alert-success mt-3 mb-0" role="alert">
          Completed:
          {{this.progress.processed}}
          submissions regenerated.
        </div>
      {{/if}}
    </div>
  </template>
}

export default <template>
  {{pageTitle "Regenerate Flatfiles"}}

  <RegenerateFlatfilesForm @model={{@model}} />
</template> satisfies TOC<{ Args: { model: Model } }>;
