# Pin npm packages by running ./bin/importmap

pin 'admin', to: 'admin/index.js'
pin_all_from 'app/javascript/admin/controllers', under: 'admin/controllers'

pin '@hotwired/turbo-rails',     to: 'turbo.min.js',     preload: true
pin '@hotwired/stimulus',        to: 'stimulus.min.js',  preload: true
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js', preload: true
pin '@popperjs/core',            to: 'popper.js',        preload: true
pin 'bootstrap',                 to: 'bootstrap.min.js', preload: true
