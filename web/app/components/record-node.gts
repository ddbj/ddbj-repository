import Component from '@glimmer/component';

import formatCount from 'repository/helpers/format-count';

import type { components } from 'schema/openapi';

type Node = components['schemas']['RecordNode'];

interface Signature {
  Args: {
    node: Node;

    // The one thing the shape does not decide: the same `fields` has a
    // card's width under a section and about 150px inside a table cell,
    // and a two-column grid in the narrow one puts the key column where
    // it wraps — taking the value with it and stretching every row.
    // Set when recursing from a table or a list, so it follows the width
    // rather than the field.
    dense?: boolean;
  };
}

// One node of a record, drawn by its shape. Recurses into itself, so
// nesting needs no extra template and no depth limit — the record is a
// tree and this follows it.
//
// The counterpart of admin/submission_requests/_record_node.html.erb.
// Two renderers of one layout, which is the price of two front ends; the
// layout itself is decided once, on the server, and arrives as the node.
export default class RecordNode extends Component<Signature> {
  get hiddenColumns() {
    return (this.args.node.hidden_columns ?? []).join(', ');
  }

  <template>
    {{#if (eq @node.kind "value")}}
      {{#if @node.free_text}}
        <div class="small text-pre-wrap">{{@node.value}}</div>
      {{else}}
        {{@node.value}}
      {{/if}}

    {{else if (eq @node.kind "empty")}}
      <span class="text-body-secondary small">—</span>

    {{else if (eq @node.kind "elided")}}
      <span class="text-body-secondary small" data-test-record-elided>not expanded</span>

    {{else if (eq @node.kind "fields")}}
      {{#if @dense}}
        {{! key: value on one line. A single-key hash then costs one line
        rather than a wrapped two-column grid, which is most of what
        makes nested cells unreadable. }}
        <div class="small">
          {{#each @node.fields as |field|}}
            <div>
              <span class="text-body-secondary">{{field.key}}:</span>
              <RecordNode @node={{field.node}} @dense={{true}} />
            </div>
          {{/each}}
        </div>
      {{else}}
        {{! A fixed key column rather than a proportion: a column that
        grows with the card puts a one-key hash's key and value several
        hundred pixels apart, and the pair stops reading as a pair. }}
        <dl class="mb-0 small record-fields">
          {{#each @node.fields as |field|}}
            <dt class="fw-normal text-body-secondary">{{field.key}}</dt>
            <dd class="mb-1"><RecordNode @node={{field.node}} @dense={{true}} /></dd>
          {{/each}}
        </dl>
      {{/if}}

    {{else if (eq @node.kind "list")}}
      <ul class="list-unstyled mb-0 small">
        {{#each @node.items as |item|}}
          <li><RecordNode @node={{item}} @dense={{true}} /></li>
        {{/each}}
      </ul>

    {{else if (eq @node.kind "table")}}
      {{! Wide records are common — an attribute bag alone can run to
      dozens of columns — so the table scrolls inside its own box rather
      than pushing the page sideways. }}
      <div class="table-responsive">
        <table class="table table-sm table-bordered small mb-1">
          <thead class="table-light">
            <tr>
              {{#each @node.columns as |column|}}
                <th scope="col" class="text-nowrap">{{column}}</th>
              {{/each}}
            </tr>
          </thead>

          <tbody>
            {{#each @node.cells as |row|}}
              <tr>
                {{#each row as |cell|}}
                  <td>
                    {{#if cell}}
                      <RecordNode @node={{cell}} @dense={{true}} />
                    {{/if}}
                  </td>
                {{/each}}
              </tr>
            {{/each}}
          </tbody>
        </table>
      </div>

      {{#if @node.hidden_columns.length}}
        <p class="small text-body-secondary mb-1" data-test-record-columns-hidden>
          {{@node.hidden_columns.length}}
          more
          {{if (eq @node.hidden_columns.length 1) "column" "columns"}}
          not shown:
          {{this.hiddenColumns}}
        </p>
      {{/if}}
    {{/if}}

    {{! Where the omission happened, because that is where somebody is
    reading — and browser search will not tell them. Ctrl+F answers "not
    here" for a value that is in the record and not on the page, so the
    line has to say so itself. }}
    {{#if @node.hidden}}
      <p class="small text-body-secondary mb-0" data-test-record-truncated>
        Showing
        {{formatCount @node.shown}}
        of
        {{formatCount @node.total}}
        —
        {{formatCount @node.hidden}}
        more not drawn.
      </p>
    {{/if}}
  </template>
}
