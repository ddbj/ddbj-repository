import type { TOC } from '@ember/component/template-only';

// Everything under a share link, whichever page of it. The notice is here
// rather than on the list because a forwarded URL can land on a record —
// and the reader arriving that way is exactly the one who has not been
// told where they are.
export default <template>
  <div class="alert alert-info py-2 small" role="note">
    You are looking at data shared with you through a link. No account is needed, and nothing here can be changed.
  </div>

  {{outlet}}
</template> satisfies TOC<object>;
