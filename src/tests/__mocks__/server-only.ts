// Stub pour l'environnement de test (vitest/Node).
//
// Le vrai package `server-only` lève une exception dès qu'il est importé en
// dehors d'un build Next.js "Server Component" (il détecte l'absence d'un
// marqueur interne posé par le bundler Next). Sous vitest, ce marqueur
// n'existe jamais — on substitue donc ce module par un no-op, uniquement
// pour les tests (voir vitest.config.ts, alias `server-only`). Le
// comportement réel de garde `server-only` en build Next.js n'est pas
// affecté : cet alias n'existe que dans la config vitest, pas dans
// tsconfig.json ni next.config.js.
export {};
