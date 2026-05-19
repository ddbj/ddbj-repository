import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';

<template>
  <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="Administration")}} />

  <h1 class="display-6 mb-4">Administration</h1>

  <h2 class="h5 mt-4">Browse</h2>

  <div class="row g-3">
    <div class="col-md-4">
      <LinkTo @route="admin.requests" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">Submission requests</h3>
          <p class="card-text text-body-secondary mb-0">Browse submission requests across all DBs and users.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="admin.submissions" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">Submissions</h3>
          <p class="card-text text-body-secondary mb-0">Browse applied submissions across all DBs and users.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="admin.users" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">Users</h3>
          <p class="card-text text-body-secondary mb-0">Browse D-way users and proxy-login as one of them.</p>
        </div>
      </LinkTo>
    </div>
  </div>

  <h2 class="h5 mt-5">Tools</h2>

  <div class="row g-3">
    <div class="col-md-4">
      <LinkTo @route="admin.regenerate-flatfiles" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">Regenerate Flatfiles</h3>
          <p class="card-text text-body-secondary mb-0">Recreate flatfiles for all submissions.</p>
        </div>
      </LinkTo>
    </div>
  </div>
</template>
