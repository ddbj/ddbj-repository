export default function getLastPageFromLinkHeader(header?: string | null) {
  if (!header) return undefined;

  const match = header.match(/(?<=<)(\S+)(?=>; rel="last")/);

  if (!match) return undefined;

  return parseInt(new URL(match[0]).searchParams.get('page')!, 10);
}
