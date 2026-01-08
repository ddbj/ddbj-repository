import Component from '@glimmer/component';
import { modifier } from 'ember-modifier';

import { Diff2HtmlUI } from 'diff2html/lib/ui/js/diff2html-ui-slim.js';

import 'highlight.js/styles/github.css';
import 'diff2html/bundles/css/diff2html.min.css';

export default class extends Component {
  drawDiff = modifier((element: HTMLElement) => {
    new Diff2HtmlUI(element, this.args.diff, {
      drawFileList: false
    }).draw();
  });

  <template>
    <div {{this.drawDiff}}></div>
  </template>
}
