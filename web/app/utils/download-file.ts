import safeFetch from 'repository/utils/safe-fetch';

import type CurrentUserService from 'repository/services/current-user';

export default async function downloadFile(url: string, currentUser: CurrentUserService) {
  const res = await safeFetch(url, {
    headers: currentUser.authorizationHeader,
  });

  location.href = res.url;
}
