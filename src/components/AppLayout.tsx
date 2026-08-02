'use client';

import React, { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import Sidebar from './Sidebar';
import Topbar from './Topbar';
import MobileBottomNav from './MobileBottomNav';
import { createClient } from '@/lib/supabase/client';
import { getPortalRole, PORTAL_ROLE_ROUTES, PortalRoleError, type PortalRole } from '@/lib/auth/getPortalRole';

interface AppLayoutProps {
  children: React.ReactNode;
  activeRoute?: string;
  userRole?: PortalRole;
}

// Garde-fou anti-boucle : si plus de REDIRECT_GUARD_LIMIT redirections de
// correction de rôle se produisent dans une fenêtre glissante de
// REDIRECT_GUARD_WINDOW_MS, on arrête et on affiche une erreur explicite
// plutôt que de rediriger indéfiniment (ex. si roleRoutes et le userRole
// déclaré par une page divergent un jour par erreur de configuration).
const REDIRECT_GUARD_KEY = 'portal_role_redirect_guard';
const REDIRECT_GUARD_LIMIT = 3;
const REDIRECT_GUARD_WINDOW_MS = 5000;

function checkAndBumpRedirectGuard(): boolean {
  // Retourne true si la limite est dépassée (il faut arrêter de rediriger).
  if (typeof window === 'undefined') return false;
  const now = Date.now();
  let guard = { count: 0, ts: now };
  try {
    const raw = window.sessionStorage.getItem(REDIRECT_GUARD_KEY);
    if (raw) guard = JSON.parse(raw);
  } catch {
    // sessionStorage indisponible ou corrompu : on repart d'un compteur propre.
  }
  if (now - guard.ts > REDIRECT_GUARD_WINDOW_MS) {
    guard = { count: 0, ts: now };
  }
  guard.count += 1;
  guard.ts = now;
  try {
    window.sessionStorage.setItem(REDIRECT_GUARD_KEY, JSON.stringify(guard));
  } catch {
    // Best-effort — l'absence de persistance ne doit pas bloquer l'app.
  }
  return guard.count > REDIRECT_GUARD_LIMIT;
}

function clearRedirectGuard(): void {
  if (typeof window === 'undefined') return;
  try {
    window.sessionStorage.removeItem(REDIRECT_GUARD_KEY);
  } catch {
    // Best-effort.
  }
}

export default function AppLayout({
  children,
  activeRoute = '/',
  userRole: userRoleProp,
}: AppLayoutProps) {
  const router = useRouter();
  // Pas de valeur par défaut 'client' silencieuse : tant que le rôle réel
  // n'est pas confirmé par le serveur, on reste en état "checkingAccess" et
  // AUCUN contenu de portail (client, admin ou verifier) n'est rendu — donc
  // aucun flash de mauvais portail possible, quelle que soit la valeur
  // initiale de cet état.
  const [userRole, setUserRole] = useState<PortalRole>(userRoleProp ?? 'client');
  const [checkingAccess, setCheckingAccess] = useState(true);
  const [roleError, setRoleError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    // Réinitialisation explicite : nécessaire maintenant que l'effet peut se
    // ré-exécuter (deps [router, userRoleProp] ci-dessous, pas []) — sans
    // ceci, un roleError ou un checkingAccess=false résiduel d'une exécution
    // précédente resterait affiché pendant la nouvelle vérification.
    setCheckingAccess(true);
    setRoleError(null);

    const fetchRole = async () => {
      const supabase = createClient();

      let normalised: PortalRole;
      try {
        normalised = await getPortalRole(supabase);
      } catch (err) {
        if (cancelled) return;
        console.error(err);
        setRoleError(
          err instanceof PortalRoleError
            ? 'Impossible de vérifier votre accès à cet espace. Reconnectez-vous ou contactez un administrateur.'
            : 'Une erreur inattendue est survenue lors de la vérification de votre accès.'
        );
        setCheckingAccess(false);
        return;
      }
      if (cancelled) return;

      setUserRole(normalised);

      if (userRoleProp && normalised !== userRoleProp) {
        if (checkAndBumpRedirectGuard()) {
          setRoleError(
            `Redirection de portail répétée détectée (rôle résolu : ${normalised}, portail attendu : ${userRoleProp}). ` +
            'Arrêt pour éviter une boucle — contactez un administrateur.'
          );
          setCheckingAccess(false);
          return;
        }
        router.replace(PORTAL_ROLE_ROUTES[normalised]);
        return;
      }

      clearRedirectGuard();
      setCheckingAccess(false);
    };

    fetchRole();
    return () => {
      cancelled = true;
    };
    // Dépendances exhaustives (router, userRoleProp) plutôt que [] : router
    // est référentiellement stable entre rendus (App Router Next.js), donc
    // aucune ré-exécution supplémentaire en pratique ; userRoleProp ne change
    // jamais après montage pour les pages actuelles (chacune passe un littéral
    // constant), mais si un futur appelant le faisait varier, l'effet doit se
    // relancer plutôt que d'agir sur un rôle attendu périmé. Sûr par
    // construction : le flag `cancelled` ci-dessus empêche une exécution
    // précédente d'écrire un état après qu'une nouvelle ait démarré, et le
    // garde-fou anti-boucle (checkAndBumpRedirectGuard) plafonne déjà les
    // redirections répétées quelle qu'en soit la cause.
  }, [router, userRoleProp]);

  if (roleError) {
    return (
      <div className="flex h-screen items-center justify-center bg-background px-4">
        <div className="max-w-md text-center space-y-3">
          <p className="text-sm text-red-600">{roleError}</p>
          <button
            type="button"
            onClick={async () => {
              const supabase = createClient();
              // scope:'local' : révocation limitée à cette session (pas les
              // autres appareils). NE dispense PAS d'un appel réseau — vérifié
              // dans @supabase/auth-js 2.108.2 installé (cf. commentaire
              // détaillé dans login/page.tsx) : signOut() appelle toujours le
              // serveur quel que soit le scope, et n'efface le stockage local
              // qu'après cet appel. Le try/catch ci-dessous journalise un
              // échec réseau éventuel sans bloquer la redirection vers /login.
              try {
                await supabase.auth.signOut({ scope: 'local' });
              } catch (signOutError) {
                console.error('Échec de la déconnexion locale :', signOutError);
              }
              router.push('/login');
            }}
            className="btn-primary rounded-lg px-4 py-2 text-sm font-semibold"
          >
            Se déconnecter
          </button>
        </div>
      </div>
    );
  }

  if (checkingAccess) {
    return (
      <div className="flex h-screen items-center justify-center bg-background">
        <div className="w-8 h-8 border-4 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="flex h-screen overflow-hidden bg-background">
      <Sidebar activeRoute={activeRoute} userRole={userRole} />
      <div className="flex flex-col flex-1 min-w-0 overflow-hidden">
        <Topbar userRole={userRole} />
        <main className="flex-1 overflow-y-auto pb-20 lg:pb-0">
          <div className="max-w-screen-2xl mx-auto px-4 md:px-6 lg:px-8 xl:px-10 2xl:px-12 py-4 md:py-6">
            {children}
          </div>
        </main>
      </div>
      {/* Mobile bottom navigation */}
      <MobileBottomNav activeRoute={activeRoute} userRole={userRole} />
    </div>
  );
}