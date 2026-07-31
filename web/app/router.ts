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

  // Unauthenticated reviewer view, reached via a share link. The request
  // is fetched by its opaque token, not by id.
  this.route('review', { path: 'reviews/:token' }, function () {
    this.route('accessions');
  });
});
