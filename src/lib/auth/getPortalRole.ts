import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Rôle de PORTAIL (routage frontend uniquement) — ne constitue jamais une
 * autorisation. Toute vérification d'accès réelle passe par les policies
 * RLS et les fonctions serveur (is_platform_superadmin(), is_project_admin(),
 * is_authorized_verifier_identity(), is_assigned_verifier(), etc.), évaluées
 * côté serveur sur chaque requête protégée.
 */
export type PortalRole = 'admin' | 'verifier' | 'client';

const VALID_ROLES: readonly PortalRole[] = ['admin', 'verifier', 'client'];

/**
 * Portail par défaut associé à chaque rôle — utilisé pour la redirection
 * post-connexion.
 *
 * admin -> '/admin' (PAS '/admin-dashboard') : '/admin-dashboard' est une
 * interface logistique legacy (Sidebar.tsx/MobileBottomNav.tsx :
 * legacyLogisticsUI: true, masquée en DEMO via
 * NEXT_PUBLIC_DEMO_HIDE_LEGACY_LOGISTICS_NAV). Le portail admin réel et
 * actuel est '/admin' (src/app/admin/page.tsx), dont le SEUL gate est
 * is_platform_superadmin() — exactement le bucket 'admin' de
 * get_my_portal_role() depuis la révision v2 (voir
 * supabase/carbon_migrations_proposed/14_get_my_portal_role_rpc.sql pour la
 * preuve live et la matrice des 6 comptes démo justifiant ce choix).
 */
export const PORTAL_ROLE_ROUTES: Record<PortalRole, string> = {
  admin: '/admin',
  verifier: '/verifier-mrv',
  client: '/',
};

export class PortalRoleError extends Error {
  cause?: unknown;
  constructor(message: string, cause?: unknown) {
    super(message);
    this.name = 'PortalRoleError';
    this.cause = cause;
  }
}

/**
 * Résout le rôle de portail de l'utilisateur actuellement authentifié via la
 * RPC public.get_my_portal_role() (SECURITY DEFINER, sans paramètre —
 * s'appuie exclusivement sur auth.uid() côté serveur).
 *
 * Point d'appel UNIQUE pour cette résolution — login/page.tsx et
 * AppLayout.tsx doivent tous deux passer par cette fonction plutôt que de
 * relire app_metadata.role/user_metadata.role du JWT (source obsolète pour
 * les comptes dont le statut vérificateur vit dans accredited_verifiers,
 * pas dans le JWT).
 *
 * Ne retourne JAMAIS de valeur par défaut silencieuse : toute erreur (RPC
 * indisponible, session absente, réponse inattendue) est levée sous forme de
 * PortalRoleError. L'appelant DOIT traiter explicitement l'échec — jamais
 * de repli implicite vers 'client'.
 */
export async function getPortalRole(supabase: SupabaseClient): Promise<PortalRole> {
  const { data, error } = await supabase.rpc('get_my_portal_role');

  if (error) {
    throw new PortalRoleError(
      `Échec de la RPC get_my_portal_role() : ${error.message}`,
      error
    );
  }

  if (typeof data !== 'string' || !VALID_ROLES.includes(data as PortalRole)) {
    throw new PortalRoleError(
      `Réponse inattendue de get_my_portal_role() : ${JSON.stringify(data)}`
    );
  }

  return data as PortalRole;
}
