import safeFetch from 'ddbj-repository/utils/safe-fetch';

import type CurrentUserService from 'ddbj-repository/services/current-user';

export default async function downloadFile(url: string, currentUser: CurrentUserService) {
  const res = await safeFetch(url, {
    headers: currentUser.authorizationHeader,
  });

  location.href = res.url;
}
