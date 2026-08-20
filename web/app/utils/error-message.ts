// The sentence the server wrote for whoever is reading it.
//
// Rails answers a refusal it has words for with `{"error": "..."}` (see
// PublicError on that side) and everything else with the status alone, so
// what comes back here is either something worth putting on the screen or
// nothing at all — never a stack trace or a SQL statement.
export function errorMessage(error: unknown): string | undefined {
  const content = (error as { content?: { error?: string } } | undefined)?.content;

  return content?.error;
}
