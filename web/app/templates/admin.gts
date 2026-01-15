import { LinkTo } from '@ember/routing';

import { pageTitle } from 'ember-page-title';

<template>
  {{pageTitle "Administration"}}

  <ul class="nav nav-tabs mb-3">
    <li class="nav-item">
      <LinkTo @route="admin.proxy-login" class="nav-link">Proxy Login</LinkTo>
    </li>
  </ul>

  {{outlet}}
</template>
