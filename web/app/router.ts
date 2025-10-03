import EmberRouter from '@ember/routing/router';
import config from 'repository/config/environment';

export default class Router extends EmberRouter {
  location = config.locationType;
  rootURL = config.rootURL;
}

Router.map(function () {
  this.route('login');
  this.route('account');

  this.route('validations', function () {
    this.route('new');
    this.route('validation', { path: ':validation_id', resetNamespace: true });
  });

  this.route('submissions', function () {
    this.route('submission', { path: ':submission_id', resetNamespace: true }, function () {
      this.route('accession', { path: '/accessions/:number', resetNamespace: true }, function () {
        this.route('accession_renewals', { resetNamespace: true }, function () {
          this.route('new');
          this.route('accession_renewal', { path: ':accession_renewal_id', resetNamespace: true });
        });
      });
    });
  });

  this.route('admin', function () {
    this.route('validations', function () {
      this.route('validation', { path: ':validation_id' });
    });

    this.route('proxy-login');
  });
});
