import { LinkTo } from '@ember/routing';
import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';

<template>
  <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="Administration")}} />

  <h1 class="display-6 mb-4">Administration</h1>

  <h2 class="h5 mt-4">Databases</h2>

  <div class="row g-3">
    <div class="col-md-4">
      <LinkTo @route="admin.db" @model="st26" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">ST.26</h3>
          <p class="card-text text-body-secondary mb-0">Browse all users' requests and submissions.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="admin.db" @model="bioproject" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">BioProject</h3>
          <p class="card-text text-body-secondary mb-0">Browse all users' requests and submissions.</p>
        </div>
      </LinkTo>
    </div>

    <div class="col-md-4">
      <LinkTo @route="admin.db" @model="biosample" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">BioSample</h3>
          <p class="card-text text-body-secondary mb-0">Browse all users' requests and submissions.</p>
        </div>
      </LinkTo>
    </div>
  </div>

  <h2 class="h5 mt-5">Tools</h2>

  <div class="row g-3">
    <div class="col-md-4">
      <LinkTo @route="admin.proxy-login" class="card text-decoration-none h-100">
        <div class="card-body">
          <h3 class="card-title h5">Proxy Login</h3>
          <p class="card-text text-body-secondary mb-0">Act on behalf of a D-way user.</p>
        </div>
      </LinkTo>
    </div>

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
