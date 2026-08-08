import { defineConfig } from 'vitest/config';
import path from 'node:path';

/**
 * Config vitest — GATE IA-1.
 *
 * Ne restreint PAS le périmètre de collecte des tests : `main` ne définissait
 * aucun `include`/runner de tests avant cette branche (aucun `vitest.config.ts`,
 * aucun script `test` dans package.json). Une version précédente de ce fichier
 * limitait `include` à `src/tests/assistant-ask.test.ts`, ce qui aurait
 * silencieusement exclu `src/tests/mrv.test.ts` de toute exécution future de
 * `npm test` / `vitest run` sans le dire — corrigé ici.
 *
 * `src/tests/mrv.test.ts` (préexistant, hors périmètre GATE IA-1) est écrit
 * contre `@jest/globals` sans jest installé/configuré dans ce dépôt — il
 * échouera sous vitest pour une raison sans rapport avec cette passe. C'est
 * visible tel quel dans `vitest run` (pas masqué), et non corrigé ici.
 *
 * Pour lancer uniquement les tests de l'Agent d'aide sans toucher au
 * périmètre général : `npx vitest run src/tests/assistant-ask.test.ts`
 * (chemin explicite en argument, pas via `include`).
 */
export default defineConfig({
  test: {
    environment: 'node',
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
      // Voir src/tests/__mocks__/server-only.ts — le vrai package lève une
      // exception hors d'un build Next.js "Server Component", ce qui n'a
      // aucun rapport avec ce qu'on teste ici (garde-fous de la route).
      'server-only': path.resolve(__dirname, './src/tests/__mocks__/server-only.ts'),
    },
  },
});
