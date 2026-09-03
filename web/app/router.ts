import EmberRouter from '@ember/routing/router';
import config from 'repository/config/environment';

export default class Router extends EmberRouter {
  location = config.locationType;
  rootURL = config.rootURL;
}

Router.map(function () {
  this.route('login');

  // Where the OAuth round trip lands with a freshly minted token —
  // distinct from `login`, which is the page a person arrives at.
  this.route('auth-callback', { path: 'auth/callback' });
  this.route('account');
  this.route('new');

  this.route('db', { path: ':db' }, function () {
    this.route('requests', function () {
      this.route('new');
    });
  });

  // Requests are keyed by a globally-unique id (like the API), so the
  // detail lives at a flat /requests/:id rather than nested under :db.
  this.route('request', { path: 'requests/:request_id' }, function () {
    this.route('accessions');
  });

  // Unauthenticated reviewer view, reached via a share link. The set is
  // fetched by its opaque token, not by id, and nothing hangs off it —
  // the link carries accessions, and they are the page.
  this.route('review', { path: 'reviews/:token' });

  this.route('sets');
  this.route('set', { path: 'sets/:set_id' });

  // Where an invitation mail lands. Readable without a session — the
  // person holding it may not have an account yet.
  this.route('invitation', { path: 'invitations/:token' });

  // Where DDBJ Account sends somebody back after they create one. It
  // carries no token: an invitation token is a bearer credential, and
  // handing it to a second application puts it in that application's
  // logs and in the Referer of every link on its pages. The token waits
  // here instead, and this route picks it up again.
  this.route('invitation-resume', { path: 'invitation' });
});
