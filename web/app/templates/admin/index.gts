import { array, hash } from '@ember/helper';

import Breadcrumb from 'repository/components/breadcrumb';
import NavCard from 'repository/components/nav-card';

<template>
  <Breadcrumb @items={{array (hash label="Home" route="index") (hash label="Administration")}} />

  <h1 class="mb-6 text-3xl font-light">Administration</h1>

  <h2 class="mt-4 mb-3 text-base font-medium text-gray-500 uppercase">Databases</h2>

  <div class="grid gap-4 md:grid-cols-3">
    <NavCard
      @route="admin.db"
      @model="st26"
      @title="ST.26"
      @description="Browse all users' requests and submissions."
    />
    <NavCard
      @route="admin.db"
      @model="bioproject"
      @title="BioProject"
      @description="Browse all users' requests and submissions."
    />
    <NavCard
      @route="admin.db"
      @model="biosample"
      @title="BioSample"
      @description="Browse all users' requests and submissions."
    />
  </div>

  <h2 class="mt-8 mb-3 text-base font-medium text-gray-500 uppercase">Tools</h2>

  <div class="grid gap-4 md:grid-cols-3">
    <NavCard @route="admin.proxy-login" @title="Proxy Login" @description="Act on behalf of a DDBJ Account user." />
    <NavCard
      @route="admin.regenerate-flatfiles"
      @title="Regenerate Flatfiles"
      @description="Recreate flatfiles for all submissions."
    />
  </div>
</template>
