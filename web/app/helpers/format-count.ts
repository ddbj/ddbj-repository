import { helper } from '@ember/component/helper';

// Thousands separated, the way the admin screens do it with
// `number_with_delimiter`. A record can hold tens of thousands of rows
// and "Showing 20 of 1842" is a number somebody has to count digits on.
//
// `undefined` rather than a locale: the browser's own, which is what the
// reader set.
export default helper<{ Args: { Positional: [number | null | undefined] }; Return: string }>(([count]) =>
  count === null || count === undefined ? '' : count.toLocaleString(),
);
