// Values WebsController injects into the shell as meta tags, so the same
// build can be served by every environment. Absent in a bare build, in
// which case whatever depends on them is simply not shown rather than
// naming a host we are not sure about.
function meta(name: string): string | undefined {
  return document.querySelector(`meta[name="${name}"]`)?.getAttribute('content') || undefined;
}

// DDBJ Account (Cloakman). Its front page rather than a deep link to the
// registration form wherever somebody merely *might* need an account: the
// front page also handles the cases they might actually be in, like having
// one already under another address.
export function accountURL(): string | undefined {
  return meta('account-url');
}

// The registration form itself, for the one place that knows the reader
// has no account: an invitation they cannot walk through without one.
//
// `returnTo` brings them back afterwards. Cloakman only honours return
// addresses it has been told about, and ignores anything else rather than
// refusing — a link that cannot be followed back is still a link that
// creates the account.
//
// Relative to the configured base rather than root-absolute, so a
// deployment served under a path prefix keeps it; and guarded, because
// this runs inside a getter during render and a malformed meta tag must
// not take the page down with it.
export function signUpURL(returnTo: string): string | undefined {
  const base = accountURL();
  if (!base) return undefined;

  try {
    const url = new URL('account/new', base.endsWith('/') ? base : `${base}/`);
    url.searchParams.set('return_to', returnTo);

    return url.toString();
  } catch {
    return undefined;
  }
}

export function identityProviderHost(): string | undefined {
  const url = meta('identity-provider');
  if (!url) return undefined;

  try {
    return new URL(url).host;
  } catch {
    return undefined;
  }
}
