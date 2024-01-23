import type CurrentUserService from 'ddbj-repository/services/current-user';

export default async function downloadFile(url: string, currentUser: CurrentUserService) {
  const res = await fetch(url, {
    headers: currentUser.authorizationHeader,
  });

  if (!res.ok) {
    throw new Error(res.statusText);
  }

  location.href = res.url;
}
