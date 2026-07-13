/**
 * getErrorMessage — extraction sûre d'un message d'erreur affichable.
 *
 * Contexte (INC-S07-05 / stabilisation du 13 juillet 2026, voir ADR-MVP.md) :
 * une erreur renvoyée par supabase.from(...).insert()/.update()/.rpc() est un
 * PostgrestError — un objet simple, PAS une instance d'`Error`. Le pattern
 * `e instanceof Error ? e.message : '<fallback générique>'`, utilisé tel quel
 * dans plusieurs écrans, est donc systématiquement faux pour ces erreurs :
 * le message réel (contrainte violée, RLS refusée, etc.) est remplacé par un
 * texte générique inutile pour le diagnostic — exactement le bug trouvé et
 * corrigé dans src/app/documents/page.tsx (§9quinvicies), maintenant
 * généralisé ici pour éviter la même régression ailleurs.
 *
 * Reconnaît : les instances d'Error, et tout objet portant un champ `message`
 * de type chaîne (couvre PostgrestError et les erreurs Supabase en général).
 */
export function getErrorMessage(e: unknown, fallback: string): string {
  if (e instanceof Error) return e.message;
  if (e && typeof e === 'object' && 'message' in e && typeof (e as { message: unknown }).message === 'string') {
    return (e as { message: string }).message;
  }
  return fallback;
}
