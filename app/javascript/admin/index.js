import '@hotwired/turbo-rails';
import '@popperjs/core';
import 'bootstrap';

import { Application } from '@hotwired/stimulus';
import { eagerLoadControllersFrom } from '@hotwired/stimulus-loading';

const application = Application.start();

eagerLoadControllersFrom('admin/controllers', application);
