-- ============================================================
-- SEED DÉMO METALVISION — 01. Comptes de démonstration par rôle
-- ============================================================
--
-- ⚠️  ENVIRONNEMENT DE DÉMONSTRATION UNIQUEMENT (METALVISION-DEMO) ⚠️
-- Ne JAMAIS exécuter sur un projet contenant des données réelles.
-- Placé hors de supabase/migrations/ pour ne jamais être appliqué
-- automatiquement par le pipeline CI/CD.
--
-- Nécessite un accès SQL direct privilégié (rôle postgres / service_role
-- via le SQL Editor Supabase ou psql sur la chaîne de connexion directe),
-- PAS le rôle `authenticator` PostgREST — ce script insère directement
-- dans auth.users, ce qu'aucun rôle API n'est autorisé à faire.
--
-- APPLICATION : dans l'ordre, fichiers 01 → 06. Ce premier fichier exige
-- OBLIGATOIREMENT une variable psql `demo_password` fournie à l'invocation
-- (jamais de valeur par défaut en clair dans ce fichier versionné) :
--
--   psql "$DATABASE_URL" -v demo_password="'<mot-de-passe-réel>'" \
--        -f supabase/seeds/demo/01_users_and_roles.sql
--
-- (Notez les guillemets simples DANS la valeur -v : psql substitue le texte
-- brut avant envoi au serveur, il faut donc lui-même fournir un littéral
-- SQL valide.) Dans le SQL Editor Supabase (qui ne supporte pas -v), copier
-- le script et remplacer manuellement `:demo_password` par le littéral SQL
-- avant exécution, puis ne jamais committer cette copie modifiée.
--
-- Le mot de passe réel n'est communiqué que hors dépôt (gestionnaire de
-- secrets / canal sécurisé), jamais en clair dans Git — cf. procédure de
-- rotation dans ADR-MVP.md.
--
-- SIX RÔLES COUVERTS (un compte par rôle-clé de la plateforme) :
--   1. superadmin@demo.metaltrace.ca   — Superadmin plateforme (JWT app_metadata.role='admin')
--   2. operateur@demo.metaltrace.ca    — Admin de l'organisation opératrice METALTRACE désignée
--   3. aggregateur@demo.metaltrace.ca  — Admin principal (primary_admin) du regroupement
--   4. producteur@demo.metaltrace.ca   — Admin d'une organisation membre, coordinateur CCF
--   5. recycleur@demo.metaltrace.ca    — Admin d'une seconde organisation membre du regroupement
--   6. verificateur@demo.metaltrace.ca — Vérificateur accrédité MRV/carbone
--
-- profiles est peuplé automatiquement par le trigger handle_new_user_profile
-- (AFTER INSERT ON auth.users) — aucun INSERT manuel nécessaire sur profiles.
-- ============================================================

DO $$
DECLARE
    v_instance_id UUID := '00000000-0000-0000-0000-000000000000';
    -- Fourni obligatoirement par la variable psql `demo_password` (voir
    -- en-tête du fichier) — aucune valeur par défaut en clair ici. Si la
    -- variable n'est pas définie, psql envoie le littéral `:demo_password`
    -- tel quel, ce qui provoque une erreur de syntaxe SQL immédiate et
    -- bloque le script (échec explicite plutôt qu'un mot de passe non
    -- initialisé silencieux).
    v_password    TEXT := :demo_password;

    v_superadmin    UUID := 'a0000000-0000-4000-a000-000000000001';
    v_operateur     UUID := 'a0000000-0000-4000-a000-000000000002';
    v_aggregateur   UUID := 'a0000000-0000-4000-a000-000000000003';
    v_producteur    UUID := 'a0000000-0000-4000-a000-000000000004';
    v_recycleur     UUID := 'a0000000-0000-4000-a000-000000000005';
    v_verificateur  UUID := 'a0000000-0000-4000-a000-000000000006';
BEGIN
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password,
        email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
        created_at, updated_at, confirmation_token, email_change,
        email_change_token_new, recovery_token, is_sso_user, is_anonymous
    ) VALUES
        (v_instance_id, v_superadmin, 'authenticated', 'authenticated',
         'superadmin@demo.metaltrace.ca', crypt(v_password, gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"],"role":"admin"}'::jsonb,
         '{"full_name":"Démo — Superadmin plateforme"}'::jsonb,
         now(), now(), '', '', '', '', false, false),

        (v_instance_id, v_operateur, 'authenticated', 'authenticated',
         'operateur@demo.metaltrace.ca', crypt(v_password, gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         '{"full_name":"Démo — Admin Opérateur METALTRACE"}'::jsonb,
         now(), now(), '', '', '', '', false, false),

        (v_instance_id, v_aggregateur, 'authenticated', 'authenticated',
         'aggregateur@demo.metaltrace.ca', crypt(v_password, gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         '{"full_name":"Démo — Admin Regroupement Laurentides"}'::jsonb,
         now(), now(), '', '', '', '', false, false),

        (v_instance_id, v_producteur, 'authenticated', 'authenticated',
         'producteur@demo.metaltrace.ca', crypt(v_password, gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         '{"full_name":"Démo — Admin Aciérie Boréale (coordinateur CCF)"}'::jsonb,
         now(), now(), '', '', '', '', false, false),

        (v_instance_id, v_recycleur, 'authenticated', 'authenticated',
         'recycleur@demo.metaltrace.ca', crypt(v_password, gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         '{"full_name":"Démo — Admin RecyclMétal Estrie"}'::jsonb,
         now(), now(), '', '', '', '', false, false),

        (v_instance_id, v_verificateur, 'authenticated', 'authenticated',
         'verificateur@demo.metaltrace.ca', crypt(v_password, gen_salt('bf')), now(),
         '{"provider":"email","providers":["email"]}'::jsonb,
         '{"full_name":"Démo — Vérificateur accrédité"}'::jsonb,
         now(), now(), '', '', '', '', false, false)
    ON CONFLICT (id) DO NOTHING;

    -- Identités email/mot de passe (requises pour la connexion via le
    -- fournisseur 'email' — sans cette ligne, signInWithPassword échoue).
    INSERT INTO auth.identities (
        id, provider_id, user_id, identity_data, provider, created_at, updated_at, last_sign_in_at
    ) VALUES
        (gen_random_uuid(), v_superadmin::text, v_superadmin,
         jsonb_build_object('sub', v_superadmin::text, 'email', 'superadmin@demo.metaltrace.ca', 'email_verified', true),
         'email', now(), now(), now()),
        (gen_random_uuid(), v_operateur::text, v_operateur,
         jsonb_build_object('sub', v_operateur::text, 'email', 'operateur@demo.metaltrace.ca', 'email_verified', true),
         'email', now(), now(), now()),
        (gen_random_uuid(), v_aggregateur::text, v_aggregateur,
         jsonb_build_object('sub', v_aggregateur::text, 'email', 'aggregateur@demo.metaltrace.ca', 'email_verified', true),
         'email', now(), now(), now()),
        (gen_random_uuid(), v_producteur::text, v_producteur,
         jsonb_build_object('sub', v_producteur::text, 'email', 'producteur@demo.metaltrace.ca', 'email_verified', true),
         'email', now(), now(), now()),
        (gen_random_uuid(), v_recycleur::text, v_recycleur,
         jsonb_build_object('sub', v_recycleur::text, 'email', 'recycleur@demo.metaltrace.ca', 'email_verified', true),
         'email', now(), now(), now()),
        (gen_random_uuid(), v_verificateur::text, v_verificateur,
         jsonb_build_object('sub', v_verificateur::text, 'email', 'verificateur@demo.metaltrace.ca', 'email_verified', true),
         'email', now(), now(), now())
    ON CONFLICT DO NOTHING;

    -- Accréditation vérificateur MRV/carbone (table dédiée, distincte du
    -- rôle JWT legacy 'verifier' — is_assigned_verifier()/is_authorized_
    -- verifier_identity() s'appuient sur accredited_verifiers, pas le JWT).
    INSERT INTO public.accredited_verifiers (user_id, accredited_by, accredited_at, active)
    VALUES (v_verificateur, v_superadmin, now(), true)
    ON CONFLICT (user_id) DO NOTHING;

    RAISE NOTICE '✅ 01_users_and_roles appliqué : 6 comptes démo créés (mot de passe fourni via la variable demo_password — non journalisé).';
END $$;
