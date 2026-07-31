import ENV from 'repository/config/environment';

import type { TOC } from '@ember/component/template-only';

const authURL = ENV.authURL;

// The front door. It used to live inside the requests list as the
// `{{else}}` branch of `isLoggedIn`, which meant the one page a first-time
// visitor sees was a button with no statement of what the system is — a
// screen that only works for somebody who already knows, i.e. a returning
// bookmark. It also left the list template carrying two unrelated jobs.
//
// The right column is here because two groups who land on this page do not
// need an account at all; without a visible branch they become help desk
// traffic.
export default <template>
  <div class="row g-5 py-4">
    <div class="col-12 col-lg-7">
      <div class="eyebrow text-uppercase text-body-tertiary fw-semibold small mb-3">
        DNA Data Bank of Japan
      </div>

      <h1 class="display-6 mb-3">Submit and track your data with DDBJ</h1>

      <p class="fs-5 text-body-secondary prose mb-4">
        Upload BioProject, BioSample and sequence records, follow validation and curation, exchange messages with
        curators, and receive your accession numbers — all in one place.
      </p>

      <form action={{authURL}} method="POST">
        <button type="submit" class="btn btn-primary btn-lg">Log in with DDBJ Account</button>
      </form>

      {{! Naming the destination up front: the button leaves for a different
      domain, and an unexplained hop to an unfamiliar host is where people
      stop. }}
      {{#if (identityProviderHost)}}
        <p class="text-body-tertiary small mt-3 mb-0">
          You will be redirected to
          {{identityProviderHost}}
          and returned here.
        </p>
      {{/if}}
    </div>

    <div class="col-12 col-lg-5">
      <div class="border-start ps-lg-4">
        <div class="py-3 border-bottom">
          <div class="fw-semibold small">Reviewing a manuscript?</div>
          <p class="small text-body-secondary mb-0">
            A reviewer share link works without an account — open the link you were given.
          </p>
        </div>

        <div class="py-3 border-bottom">
          <div class="fw-semibold small">Submitting programmatically?</div>
          <p class="small text-body-secondary mb-0">
            The API takes an API key — no browser login.
          </p>
        </div>

        <div class="py-3">
          <div class="fw-semibold small">Trouble signing in?</div>
          <p class="small text-body-secondary mb-0">
            Account questions go to the DDBJ help desk.
          </p>
        </div>
      </div>
    </div>
  </div>
</template> satisfies TOC<object>;

// Injected per environment by WebsController; absent in tests and in a
// bare build, in which case the line is simply not shown rather than
// naming a host we are not sure about.
function identityProviderHost(): string | undefined {
  const url = document.querySelector('meta[name="identity-provider"]')?.getAttribute('content');
  if (!url) return undefined;

  try {
    return new URL(url).host;
  } catch {
    return undefined;
  }
}
