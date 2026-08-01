-- ============================================================================
-- Migration 12 — start_verification_session() : combler le trou fonctionnel
-- "Démarrer la vérification" (planned -> in_progress)
-- ============================================================================
--
-- CONTEXTE / BUG RÉEL TROUVÉ EN PRODUCTION (Lot 4, régression transverse) :
--
-- La page /verifier-mrv (utilisée par le vérificateur accrédité assigné,
-- PAS /admin-verification-sessions qui est réservée au coordinateur MRV)
-- exécute pour le bouton "Démarrer la vérification" un UPDATE direct :
--
--     supabase.from('verification_sessions').update({status:'in_progress'}).eq('id', sessionId)
--
-- Or les policies RLS réelles sur verification_sessions sont :
--   - admin_manage_verification_sessions : ALL, is_project_admin()  (coordinateur MRV)
--   - verifier_read_verification_sessions : SELECT seulement, is_assigned_verifier(id)
--   - client_read_verification_sessions   : SELECT seulement
--
-- Aucune policy UPDATE n'existe pour le vérificateur assigné lui-même.
-- Résultat observé : l'UPDATE ne lève AUCUNE erreur (PostgREST/RLS filtre
-- silencieusement la ligne hors du WHERE effectif de l'UPDATE -> 0 ligne
-- affectée, succès HTTP, aucune alerte déclenchée côté frontend). Confirmé
-- par lecture directe : le statut de la session reste 'planned' après clic.
--
-- Ce trou est structurel, pas cosmétique : complete_verification_session()
-- refuse explicitement toute clôture tant que status = 'planned'
-- ("Session non prête : le statut doit être in_progress ou completed").
-- Sans transition planned -> in_progress fonctionnelle, aucune vérification
-- ne peut jamais être complétée par le vérificateur assigné lui-même.
--
-- Point notable : le CHECK carbon_business_events_event_type_check autorise
-- déjà la valeur 'verification_session_started' depuis la migration 05,
-- mais AUCUNE ligne ne l'utilise en production (count = 0 vérifié) : cette
-- RPC était prévue dans la conception d'origine mais n'a jamais été écrite.
-- Le frontend a improvisé un UPDATE direct à la place, sans RPC ni
-- policy — d'où le trou.
--
-- FIX : nouvelle RPC start_verification_session(), suivant exactement le
-- même patron que plan_verification_session() / complete_verification_session()
-- (SECURITY DEFINER, verrou FOR UPDATE, vérification accréditation active
-- FOR SHARE, garde de transition explicite, événement d'audit). Le frontend
-- (/verifier-mrv/page.tsx handleStart()) doit être modifié pour appeler
-- cette RPC au lieu de l'UPDATE direct — voir commit associé.
--
-- AUCUNE migration existante (01 à 11) n'est modifiée. Ce fichier est
-- strictement additif (CREATE FUNCTION + GRANT).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.start_verification_session(p_verification_session_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_actor  UUID;
    v_status public.verification_status;
BEGIN
    v_actor := auth.uid();
    IF v_actor IS NULL THEN
        RAISE EXCEPTION 'Authentification requise.';
    END IF;

    -- Verrou + portée : seul le vérificateur assigné à CETTE session peut
    -- la démarrer (pas un vérificateur accrédité quelconque, pas l'admin).
    SELECT status INTO v_status
    FROM public.verification_sessions
    WHERE id = p_verification_session_id
      AND verifier_user_id = v_actor
    FOR UPDATE;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'Session introuvable ou accès refusé.';
    END IF;

    -- Revalidation de l'accréditation active au moment du démarrage (même
    -- garde que complete_verification_session() — une accréditation peut
    -- avoir été révoquée entre la planification et le démarrage).
    PERFORM 1 FROM public.accredited_verifiers WHERE user_id = v_actor AND active FOR SHARE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Accréditation de vérificateur révoquée ou introuvable : impossible de démarrer une vérification.';
    END IF;

    IF v_status <> 'planned' THEN
        RAISE EXCEPTION 'Transition refusée : la session doit être au statut planned pour démarrer (statut actuel : %).', v_status;
    END IF;

    UPDATE public.verification_sessions
    SET status = 'in_progress'
    WHERE id = p_verification_session_id;

    INSERT INTO public.carbon_business_events (
        event_type, object_type, object_id, verification_session_id, actor_id, payload
    ) VALUES (
        'verification_session_started', 'verification_session', p_verification_session_id,
        p_verification_session_id, v_actor, NULL
    );

    RETURN p_verification_session_id;
END;
$function$;

COMMENT ON FUNCTION public.start_verification_session(uuid) IS
'Transition planned -> in_progress par le vérificateur assigné lui-même. Comble le trou fonctionnel du bouton "Démarrer la vérification" (/verifier-mrv), qui effectuait un UPDATE direct sans policy RLS correspondante. Migration 12, Lot 4.';

GRANT EXECUTE ON FUNCTION public.start_verification_session(uuid) TO authenticated;
