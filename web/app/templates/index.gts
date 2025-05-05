import { pageTitle } from 'ember-page-title';

import ENV from 'repository/config/environment';

const authURL = new URL('/auth/keycloak', ENV.apiURL).href;

<template>
  {{pageTitle "Login"}}

  <form action={{authURL}} method="POST">
    <button type="submit" class="btn btn-primary btn-lg">Login</button>
  </form>
</template>
