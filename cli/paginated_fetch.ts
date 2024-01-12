export default async function paginatedFetch(url: string, apiKey: string, callback: (res: Response) => Promise<void>) {
  const res = await fetch(url, {
    headers: { 'Authorization': `Bearer ${apiKey}` },
  });

  await callback(res);

  const next = getNextUrl(res.headers.get('link'));

  if (!next) return;

  await paginatedFetch(next, apiKey, callback);
}

function getNextUrl(header: string | null) {
  if (!header) return null;

  return /<([^>]+)>; rel="next"/.exec(header)?.[1];
}
