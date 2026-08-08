import { defineConfig } from 'vitest/config';
import path from 'node:path';

/**
 * Config vitest — GATE IA-1.
 *
 * Portée volontairement limitée à `src/tests/assistant-ask.test.ts` : le
 * dépôt contient déjà `src/tests/mrv.test.ts`, écrit contre `@jest/globals`
 * (aucun binaire/config jest présent — boilerplate non exécutable, constaté
 * indépendamment de cette passe). Le faire tourner sous vitest échouerait
 * pour une raison sans rapport avec GATE IA-1. Ne pas élargir `include` sans
 * traiter ce fichier séparément.
 */
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/tests/assistant-ask.test.ts'],
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
