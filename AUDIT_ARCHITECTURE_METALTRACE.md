# AUDIT D'ARCHITECTURE TECHNIQUE — METALTRACE
**Date de l'audit** : 2026-07-06  
**Version** : 1.0  
**Statut** : Lecture seule — aucune modification effectuée  
**Environnement** : Production — https://metaltrace.ca

---

## TABLE DES MATIÈRES

1. [Vue d'ensemble](#1-vue-densemble)
2. [Arborescence du projet](#2-arborescence-du-projet)
3. [Pages de l'application](#3-pages-de-lapplication)
4. [API Routes](#4-api-routes)
5. [Base de données Supabase](#5-base-de-données-supabase)
6. [Modules fonctionnels](#6-modules-fonctionnels)
7. [Composants React](#7-composants-react)
8. [Authentification et sécurité](#8-authentification-et-sécurité)
9. [Intégrations externes](#9-intégrations-externes)
10. [État du projet](#10-état-du-projet)
11. [Dette technique](#11-dette-technique)
12. [Recommandations](#12-recommandations)

---

## 1. Vue d'ensemble

### Architecture générale

METALTRACE est une **plateforme SaaS de traçabilité intelligente des métaux recyclés**, combinant analyse IA par vision, suivi de transport, comptabilité carbone ISO 14064-2, et gestion multi-entreprises.

| Attribut | Valeur |
|---|---|
| **Framework** | Next.js 15.5.18 (App Router) |
| **Langage** | TypeScript 5.x (strict mode) |
| **Runtime** | Node.js (serveur) + React 19.0.3 (client) |
| **Base de données** | Supabase (PostgreSQL + Auth + RLS) |
| **Styling** | Tailwind CSS 3.4.6 + CSS Variables (design tokens) |
| **IA** | Google Gemini 2.5 Flash (via @rocketnew/llm-sdk) |
| **Transport** | OpenRouteService (géocodage + distances) |
| **Prix métaux** | Metals.Dev API |
| **Déploiement** | Netlify (@netlify/plugin-nextjs) |

### Technologies principales

- **@supabase/ssr 0.12.0** — client SSR avec gestion cookies cross-origin
- **@rocketnew/llm-sdk 1.1.0** — abstraction multi-provider LLM
- **jsqr 1.4.0** — décodage QR code côté client (canvas)
- **qrcode.react 4.2.0** — génération QR code
- **recharts 2.15.2** — graphiques
- **react-hook-form 7.77.0** — formulaires
- **lucide-react 1.7.0** — icônes complémentaires
- **@heroicons/react 2.2.0** — icônes principales
- **pgcrypto** (extension PostgreSQL) — chaîne de hachage SHA-256 des scans

### Organisation du code

Architecture **App Router** Next.js 15 avec séparation claire Server Components / Client Components. Les pages sont des Server Components légers qui délèguent à des composants `'use client'` pour l'interactivité. Les routes API sont des Route Handlers Next.js (`route.ts`).

---

## 2. Arborescence du projet

```
metaltrace/
├── public/
│   ├── assets/images/          # Logo METALTRACE, images statiques
│   └── favicon.ico
│
├── src/
│   ├── app/                    # App Router Next.js 15
│   │   ├── page.tsx            # Dashboard client (/)
│   │   ├── layout.tsx          # Root layout (DM Sans, metadata)
│   │   ├── not-found.tsx       # Page 404
│   │   │
│   │   ├── login/              # Authentification
│   │   ├── inscription/        # Création de compte entreprise
│   │   ├── invitation/[token]/ # Acceptation d'invitation
│   │   │
│   │   ├── admin-dashboard/    # Tableau de bord opérateur
│   │   ├── admin-carbon-projects/   # Gestion projets carbone MRV
│   │   ├── admin-emission-factors/  # Facteurs d'émission GES
│   │   ├── admin-mrv-project/       # Détail projet MRV (tabs)
│   │   ├── admin-transport/         # Gestion transport admin
│   │   ├── admin-verification-sessions/ # Sessions de vérification
│   │   │
│   │   ├── carbon-impact/      # Impact carbone client
│   │   ├── container-detail/   # Détail conteneur + historique
│   │   ├── lot-management/     # Gestion lots + conteneurs
│   │   ├── new-lot/            # Wizard création lot (5 étapes)
│   │   ├── qr-code-scanner/    # Scanner QR (jsqr + canvas)
│   │   ├── transport-tracking/ # Suivi transport client
│   │   ├── verifier-mrv/       # Interface vérificateur ISO 14064-2
│   │   │
│   │   ├── components/         # Composants partagés dashboard client
│   │   │   ├── ClientDashboardContent.tsx
│   │   │   ├── ClientKPIGrid.tsx
│   │   │   ├── ClientQuickActions.tsx
│   │   │   ├── ContainerGrid.tsx
│   │   │   └── RecentLotsTable.tsx
│   │   │
│   │   └── api/                # Route Handlers Next.js
│   │       ├── ai/
│   │       │   ├── analyze-photo/   # Analyse IA photo métal (Gemini)
│   │       │   └── chat-completion/ # Chat LLM multi-provider
│   │       ├── aggregator/
│   │       │   └── calculate-sale/  # Calcul répartition crédits carbone
│   │       ├── external/
│   │       │   └── grouperobert/    # Stubs API Groupe Robert (DEPRECATED)
│   │       ├── ghg/
│   │       │   └── calculate/       # Calcul GES ISO 14064-2
│   │       ├── measurements/
│   │       │   └── confirm/         # Confirmation mesure officielle
│   │       ├── metals-price/        # Prix métaux (Metals.Dev)
│   │       ├── predict/             # Prédiction poids/valeur
│   │       ├── projects/[id]/
│   │       │   ├── iso-report/      # Rapport ISO 14064-2 JSON
│   │       │   └── log-activity/    # Journalisation activité MRV
│   │       ├── stats/
│   │       │   └── update/          # Mise à jour stats globales
│   │       └── transport/
│   │           ├── [id]/status/     # GET/PATCH statut transport
│   │           ├── calculate-distance/ # Calcul distance + GES
│   │           ├── complete/        # Marquer livré + GES
│   │           ├── create/          # DEPRECATED → internal-create
│   │           ├── internal-create/ # Créer transport interne
│   │           ├── poll-status/     # DEPRECATED (Groupe Robert)
│   │           └── update-status/   # Mise à jour statut
│   │
│   ├── components/             # Composants layout globaux
│   │   ├── AppLayout.tsx       # Layout principal (Sidebar + Topbar)
│   │   ├── MobileBottomNav.tsx # Navigation mobile bas d'écran
│   │   ├── Sidebar.tsx         # Navigation latérale (rôle-aware)
│   │   ├── Topbar.tsx          # Barre supérieure (prix + notifs)
│   │   └── ui/                 # Composants UI réutilisables
│   │       ├── AppIcon.tsx     # Wrapper Heroicons
│   │       ├── AppImage.tsx    # Wrapper next/image
│   │       ├── AppLogo.tsx     # Logo METALTRACE
│   │       ├── EmptyState.tsx  # État vide générique
│   │       ├── LoadingSkeleton.tsx
│   │       ├── MetalBadge.tsx  # Badge type métal
│   │       ├── MetricCard.tsx  # Carte KPI
│   │       ├── QRCodeModal.tsx # Modal QR code
│   │       └── StatusBadge.tsx # Badge statut
│   │
│   ├── contexts/
│   │   └── AuthContext.tsx     # Provider auth (non utilisé dans layout)
│   │
│   ├── lib/
│   │   ├── ai/
│   │   │   ├── aiClient.ts     # Wrapper fetch vers /api/ai/*
│   │   │   └── chatCompletion.ts # getChatCompletion / streaming
│   │   ├── distribution-calculator.ts # Calcul répartition crédits carbone (pur)
│   │   ├── hooks/
│   │   │   └── useChat.ts      # Hook React pour chat LLM
│   │   └── supabase/
│   │       ├── client.tsx      # createClient() navigateur (SSR-safe)
│   │       └── server.tsx      # createClient() serveur (cookies)
│   │
│   ├── styles/
│   │   ├── index.css           # Variables CSS globales (non modifiable)
│   │   └── tailwind.css        # Directives Tailwind
│   │
│   ├── middleware.ts           # Auth guard + session refresh
│   └── tests/
│       └── mrv.test.ts         # Tests unitaires MRV (Jest)
│
├── supabase/
│   └── migrations/             # 15 fichiers SQL (chronologiques)
│
├── .env                        # Variables d'environnement
├── next.config.mjs             # Config Next.js
├── tailwind.config.js          # Config Tailwind
├── tsconfig.json               # Config TypeScript (strict)
└── package.json
```

### Rôle des dossiers principaux

| Dossier | Rôle |
|---|---|
| `src/app/` | Pages, layouts, routes API (App Router) |
| `src/components/` | Composants UI réutilisables et layout |
| `src/lib/` | Utilitaires, clients Supabase, IA, hooks |
| `src/contexts/` | Contextes React (AuthContext — partiellement utilisé) |
| `src/styles/` | CSS global et Tailwind |
| `src/tests/` | Tests automatisés (Jest) |
| `supabase/migrations/` | Historique complet du schéma SQL |

---

## 3. Pages de l'application

### Routes publiques (sans authentification)

| URL | Rôle | Composants clés | Tables Supabase |
|---|---|---|---|
| `/login` | Connexion email/mot de passe | `LoginPage`, `AppLogo` | `auth.users` |
| `/inscription` | Création compte + entreprise | `InscriptionPage`, `AppLogo` | `auth.users`, `companies`, `company_members` |
| `/invitation/[token]` | Acceptation invitation par lien | `InvitationPage`, `AppLogo` | `invitations`, `companies`, `company_members` |

### Routes protégées — Rôle Client

| URL | Rôle | Composants clés | Tables Supabase |
|---|---|---|---|
| `/` | Dashboard client — KPIs, lots récents, conteneurs | `ClientDashboardContent`, `ClientKPIGrid`, `RecentLotsTable`, `ContainerGrid`, `ClientQuickActions` | `raw_measurements`, `containers`, `company_members` |
| `/new-lot` | Wizard 5 étapes : photo → IA → résultat → confirmation → soumission | `NewLotWizard`, `StepPhotoCapture`, `StepPhotoAnalysis`, `StepAIResult`, `StepConfirmSubmit`, `StepConfirmation` | `raw_measurements` (via `/api/ai/analyze-photo`) |
| `/lot-management` | Liste lots + conteneurs, détail lot, sidebar | `LotManagementContent`, `LotListSidebar`, `LotDetailPanel`, `ContainersListSection` | `raw_measurements`, `containers`, `scan_events` |
| `/qr-code-scanner` | Scanner QR code (caméra + saisie manuelle) | `QRScannerContent`, `QRScannerViewfinder`, `ManualEntry`, `ContainerResult`, `RecentScans` | `containers`, `scan_events` |
| `/transport-tracking` | Suivi transport client (stepper visuel) | `TransportTrackingPage`, `TransportCard`, `ProgressStepper` | `transport_requests` |
| `/carbon-impact` | Impact carbone client, projets, export rapport ISO | `ClientCarbonImpactPage` | `projects`, `project_activity_logs` |

### Routes protégées — Rôle Admin

| URL | Rôle | Composants clés | Tables Supabase |
|---|---|---|---|
| `/admin-dashboard` | Tableau de bord opérateur — KPIs, lots en attente, alertes | `AdminDashboardContent`, `AdminKPIGrid`, `PendingLotsTable`, `AdminCharts`, `SensorAlerts` | `raw_measurements`, `/api/metals-price` |
| `/admin-carbon-projects` | Liste projets carbone MRV | `AdminCarbonProjectsPage`, `NewProjectModal`, `StatusBadge` | `projects` |
| `/admin-mrv-project` | Détail projet MRV (tabs : overview, activités, preuves, vérification) | `MRVProjectContent` | `projects`, `project_activity_logs`, `evidence_files`, `verification_sessions` |
| `/admin-emission-factors` | CRUD facteurs d'émission GES | `AdminEmissionFactorsPage`, `FactorModal` | `emission_factors` |
| `/admin-verification-sessions` | Gestion sessions de vérification tierces | `AdminVerificationSessionsPage`, `SessionModal` | `verification_sessions`, `projects` |
| `/admin-transport` | Gestion complète transport (création, statuts, livraison GES) | `AdminTransportPage`, `DetailModal`, `CreateTransportModal` | `transport_requests`, `raw_measurements`, `containers` |
| `/lot-management` | Partagée admin/client — gestion lots | (idem client) | (idem client) |
| `/container-detail` | Détail conteneur (chart remplissage, QR, historique) | `ContainerDetailContent`, `ContainerHeader`, `ContainerInfoPanel`, `ContainerFillChart`, `ContainerQRCode`, `SensorPanel`, `ContainerLotHistory` | `containers`, `scan_events`, `raw_measurements` |
| `/container-detail/[id]` | Variante avec ID dans l'URL | (idem) | (idem) |

### Routes protégées — Rôle Vérificateur

| URL | Rôle | Composants clés | Tables Supabase |
|---|---|---|---|
| `/verifier-mrv` | Interface vérificateur ISO 14064-2 — sessions, activités, chaîne de hachage, observations | `VerifierMRVPage`, `SubmitReportModal`, `AddObservationModal` | `verification_sessions`, `project_activity_logs`, `scan_events`, `verifier_observations`, `projects` |

---

## 4. API Routes

### Module IA

| Endpoint | Méthode | Objectif | Tables | Dépendances |
|---|---|---|---|---|
| `/api/ai/analyze-photo` | POST | Analyse photo métal via Gemini Vision → stockage `raw_measurements` | `raw_measurements` | `GEMINI_API_KEY`, `@rocketnew/llm-sdk`, `getChatCompletion` |
| `/api/ai/chat-completion` | POST | Chat LLM multi-provider (Gemini, OpenAI, Anthropic, Perplexity) avec streaming SSE | — | `GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `PERPLEXITY_API_KEY` |

### Module Mesures

| Endpoint | Méthode | Objectif | Tables | Dépendances |
|---|---|---|---|---|
| `/api/measurements/confirm` | POST | Confirme mesure officielle (poids, type, prix) + déclenche GES + log MRV | `raw_measurements`, `project_activity_logs`, `evidence_files` | `/api/ghg/calculate`, `/api/projects/[id]/log-activity` |
| `/api/predict` | POST | Prédit poids/valeur depuis stats globales ou profils objets | `global_stats`, `object_profiles` | Supabase server client |
| `/api/stats/update` | POST | Recalcule `global_stats` et `object_profiles` depuis toutes les mesures | `raw_measurements`, `global_stats`, `object_profiles` | `SUPABASE_SERVICE_ROLE_KEY` (bypass RLS) |

### Module Transport

| Endpoint | Méthode | Objectif | Tables | Dépendances |
|---|---|---|---|---|
| `/api/transport/internal-create` | POST | Crée transport interne + preuves + log MRV optionnel | `transport_requests`, `evidence_files` | `/api/ghg/calculate`, `/api/projects/[id]/log-activity` |
| `/api/transport/create` | POST | **DEPRECATED** — redirige vers `internal-create` | — | `NEXT_PUBLIC_SITE_URL` |
| `/api/transport/update-status` | POST | Met à jour statut transport | `transport_requests` | — |
| `/api/transport/complete` | POST | Marque livré + calcule distance (OSRM) + GES + log MRV | `transport_requests`, `project_activity_logs` | Nominatim, OSRM (OSM), Supabase |
| `/api/transport/[id]/status` | GET | Retourne statut courant | `transport_requests` | — |
| `/api/transport/[id]/status` | PATCH | Met à jour statut manuellement | `transport_requests` | — |
| `/api/transport/calculate-distance` | POST | Géocode + calcule distance routière + GES | — | `OPENROUTESERVICE_API_KEY` |
| `/api/transport/poll-status` | POST | **DEPRECATED** (Groupe Robert) — retourne 410 | — | — |

### Module MRV / Carbone

| Endpoint | Méthode | Objectif | Tables | Dépendances |
|---|---|---|---|---|
| `/api/ghg/calculate` | POST | Calcule GES baseline vs projet (ADEME) | `projects`, `emission_factors` | Supabase server client |
| `/api/projects/[id]/log-activity` | POST | Crée log activité MRV + fichier preuve | `project_activity_logs`, `evidence_files` | Supabase server client |
| `/api/projects/[id]/log-activity` | GET | Liste logs d'un projet | `project_activity_logs` | Supabase server client |
| `/api/projects/[id]/iso-report` | GET | Génère rapport ISO 14064-2 JSON complet | `projects`, `project_activity_logs`, `evidence_files`, `verification_sessions`, `emission_factors` | Supabase server client |

### Module Agrégateur / Crédits Carbone

| Endpoint | Méthode | Objectif | Tables | Dépendances |
|---|---|---|---|---|
| `/api/aggregator/calculate-sale` | POST | Calcule répartition revenus vente crédits carbone entre membres | `credit_sales`, `credit_sale_lots`, `credit_lots`, `projects`, `distribution_rules`, `member_distribution_overrides`, `credit_sale_allocations` | `distribution-calculator.ts`, Supabase server client |

### Module Prix Métaux

| Endpoint | Méthode | Objectif | Tables | Dépendances |
|---|---|---|---|---|
| `/api/metals-price` | GET | Prix spot métaux (cuivre, aluminium) en $CA/kg + tendance | — | `METALS_API_KEY` (Metals.Dev), ISR 10 min |

### Stubs externes (DEPRECATED)

| Endpoint | Méthode | Objectif |
|---|---|---|
| `/api/external/grouperobert/create-shipment` | POST | Stub mock Groupe Robert (non connecté) |
| `/api/external/grouperobert/shipment-status` | GET | Stub mock Groupe Robert (non connecté) |

---

## 5. Base de données Supabase

### Carte des relations entre tables

```
auth.users
    │
    ├──► company_members (user_id) ──► companies (id)
    │                                      │
    │                                      ├──► invitations (company_id)
    │                                      ├──► containers (company_id)
    │                                      │       └──► scan_events (container_id)
    │                                      └──► raw_measurements (company_id)
    │                                               └──► transport_requests (via transport_request_id)
    │
    ├──► projects (client_id → companies.id)
    │       ├──► project_activity_logs (project_id)
    │       │       └──► evidence_files (related_activity_log_id)
    │       │       └──► verifier_observations (activity_log_id)
    │       ├──► evidence_files (project_id)
    │       └──► verification_sessions (project_id)
    │
    ├──► global_stats (anonyme — agrégats par métal)
    ├──► object_profiles (anonyme — agrégats par type objet)
    ├──► audit_learning_log (anonyme — journal apprentissage)
    ├──► emission_factors (référentiel GES)
    └──► app_settings (feature flags)

Tables agrégateur (schéma implicite — pas de migration trouvée) :
    credit_sales ──► credit_sale_lots ──► credit_lots ──► projects
    credit_sales ──► credit_sale_allocations (company_id)
    distribution_rules (aggregator_id)
    member_distribution_overrides (aggregator_id, company_id)
```

### Détail des tables

#### `raw_measurements`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | Identifiant mesure |
| `client_id` | UUID | Ancien identifiant client (legacy) |
| `company_id` | UUID FK → companies | Entreprise propriétaire |
| `container_id` | UUID FK → containers | Conteneur associé |
| `transport_request_id` | UUID FK → transport_requests | Transport associé |
| `metal_type_predicted` | TEXT | Type métal prédit par IA |
| `confidence` | NUMERIC(4,3) | Confiance IA (0-1) |
| `width_cm`, `height_cm`, `depth_cm` | NUMERIC | Dimensions estimées |
| `volume_estimated_m3` | NUMERIC | Volume estimé |
| `compaction_visual`, `purity_visual` | NUMERIC | Indicateurs visuels |
| `object_type` | TEXT | Type d'objet identifié |
| `raw_analysis_json` | JSONB | Réponse brute Gemini |
| `official_weight_kg` | NUMERIC | Poids officiel (pesée) |
| `official_metal_type` | TEXT | Type métal confirmé |
| `density_real` | NUMERIC | Densité calculée |
| `price_paid` | NUMERIC | Prix payé |
| `weight_kg` | NUMERIC | Poids (colonne additionnelle) |
| `status` | TEXT | `submitted` / `processed` / `invoiced` |
| `notes` | TEXT | Notes libres |
| `image_url` | TEXT | URL photo |
| `created_at`, `updated_at` | TIMESTAMPTZ | Horodatages |

**RLS** : Membres de l'entreprise (`is_company_member(company_id)`) pour SELECT/INSERT/UPDATE. `service_role` bypass total.

#### `companies`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | Identifiant entreprise |
| `name` | TEXT | Nom de l'entreprise |
| `created_at` | TIMESTAMPTZ | Date création |

**RLS** : Membres voient leur entreprise. Propriétaires peuvent modifier/supprimer. Tout utilisateur authentifié peut créer.

#### `company_members`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `company_id` | UUID FK → companies | |
| `user_id` | UUID | Référence `auth.users` |
| `role` | ENUM (`owner`, `terrain`) | Rôle dans l'entreprise |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Membres voient leurs collègues. Propriétaires gèrent les membres. Bootstrap premier owner autorisé. Invitation acceptée permet auto-insertion.

#### `invitations`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `company_id` | UUID FK → companies | |
| `email` | TEXT | Email invité |
| `role` | ENUM | Rôle proposé |
| `token` | TEXT UNIQUE | Token d'invitation (hex 32 bytes) |
| `status` | ENUM (`pending`, `accepted`, `expired`, `revoked`) | |
| `expires_at` | TIMESTAMPTZ | Expiration (7 jours) |
| `accepted_at` | TIMESTAMPTZ | Date acceptation |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Propriétaires gèrent. Invité peut lire/accepter sa propre invitation (match email JWT).

#### `containers`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `company_id` | UUID FK → companies | |
| `qr_code` | TEXT UNIQUE | Code QR unique |
| `name` | TEXT | Nom du conteneur |
| `location` | TEXT | Emplacement |
| `status` | TEXT | `active` / `inactive` / `maintenance` |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Membres SELECT. Propriétaires INSERT/UPDATE/DELETE.

#### `scan_events`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `container_id` | UUID FK → containers | |
| `company_id` | UUID FK → companies | |
| `user_id` | UUID | Utilisateur ayant scanné |
| `action_type` | TEXT | `depot` / `collecte` / `verification` |
| `gps_lat`, `gps_lng` | NUMERIC | Coordonnées GPS |
| `gps_accuracy_m` | NUMERIC | Précision GPS |
| `scanned_at` | TIMESTAMPTZ | |
| `previous_hash` | TEXT | Hash événement précédent |
| `event_hash` | TEXT NOT NULL | Hash SHA-256 (chaîne) |

**RLS** : Membres SELECT/INSERT. Pas de UPDATE/DELETE (immuable).  
**Trigger** : `compute_scan_event_hash` (BEFORE INSERT) — chaîne de hachage avec advisory lock.  
**Fonction** : `verify_container_chain(container_id)` — vérifie l'intégrité de la chaîne.

#### `transport_requests`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `lot_id` | TEXT | Référence lot |
| `company_id` | UUID | Entreprise |
| `container_id` | TEXT | Conteneur |
| `pickup_address`, `dropoff_address` | TEXT | Adresses |
| `scheduled_time`, `arrival_eta` | TIMESTAMPTZ | Planification |
| `transporter` | TEXT | Nom transporteur |
| `provider` | TEXT | `internal` / `client` |
| `transport_status` | TEXT | `scheduled` / `in_transit` / `arrived` / `delivered` / `cancelled` |
| `driver_name`, `truck_number` | TEXT | Chauffeur/camion |
| `transport_mode` | TEXT | `camion` / `train` / `navire` |
| `gps_start`, `gps_end` | JSONB | Coordonnées GPS départ/arrivée |
| `proof_photo_url`, `proof_document_url` | TEXT | Preuves |
| `distance_km` | NUMERIC | Distance calculée |
| `ghg_transport_kgco2e` | NUMERIC | Émissions GES transport |
| `emission_factor_used` | NUMERIC | Facteur ADEME utilisé |
| `weight_tonnes` | NUMERIC | Poids en tonnes |
| `notes` | TEXT | Notes |
| `created_at`, `updated_at` | TIMESTAMPTZ | |

**RLS** : Tous les utilisateurs authentifiés peuvent SELECT/INSERT/UPDATE.

#### `projects`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `client_id` | UUID | Référence entreprise cliente |
| `name` | TEXT | Nom du projet |
| `description` | TEXT | Description |
| `system_boundaries` | JSONB | Frontières du système |
| `baseline_description` | TEXT | Description baseline |
| `project_scenario_description` | TEXT | Description scénario projet |
| `start_date`, `end_date` | DATE | Période |
| `status` | ENUM (`draft`, `active`, `verified`) | |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Admin full access. Client lit ses propres projets. Vérificateur lit tout.

#### `emission_factors`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `category` | TEXT | Ex: `transport_routier`, `recyclage_acier` |
| `source_reference` | TEXT | Ex: `ADEME Base Carbone 2023` |
| `unit` | TEXT | Ex: `kgCO2e/tkm` |
| `value` | FLOAT8 | Valeur du facteur |
| `uncertainty_percent` | FLOAT8 | Incertitude (%) |
| `valid_from`, `valid_to` | DATE | Période de validité |
| `version` | TEXT | Version |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Admin gère. Tous les authentifiés lisent.

#### `project_activity_logs`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `project_id` | UUID FK → projects | |
| `activity_type` | TEXT | Ex: `transport`, `recyclage_acier` |
| `related_lot_id`, `related_container_id`, `related_transport_request_id` | UUID | Références croisées |
| `raw_data_ref` | UUID | Référence mesure brute |
| `ghg_emissions_baseline_kgco2e` | FLOAT8 | GES baseline |
| `ghg_emissions_project_kgco2e` | FLOAT8 | GES projet |
| `ghg_reduction_kgco2e` | FLOAT8 | Réduction GES |
| `uncertainty_percent` | FLOAT8 | Incertitude |
| `timestamp` | TIMESTAMPTZ | |
| `actor_id` | UUID | Utilisateur ayant déclenché |

**RLS** : Admin full. Vérificateur lit tout. Client lit ses propres projets.

#### `evidence_files`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `project_id` | UUID FK → projects | |
| `file_url` | TEXT | URL fichier preuve |
| `type` | TEXT | `photo_pesee`, `proof_photo`, `proof_document` |
| `related_activity_log_id` | UUID FK → project_activity_logs | |
| `gps` | JSONB | Coordonnées GPS |
| `timestamp` | TIMESTAMPTZ | |
| `actor_id` | UUID | |

**RLS** : Admin full. Vérificateur lit. Client lit ses propres projets.

#### `verification_sessions`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `project_id` | UUID FK → projects | |
| `verifier_org` | TEXT | Organisme vérificateur |
| `verifier_contact` | TEXT | Contact |
| `scope` | JSONB | Périmètre de vérification |
| `status` | ENUM (`planned`, `in_progress`, `completed`) | |
| `report_url` | TEXT | URL rapport final |
| `comments` | TEXT | Commentaires |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Admin full. Vérificateur lit. Client lit.

#### `verifier_observations`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `activity_log_id` | UUID FK → project_activity_logs | |
| `verifier_id` | UUID | Vérificateur auteur |
| `observation_text` | TEXT | Texte de l'observation |
| `status` | TEXT | `conforme` / `non_conforme` / `a_clarifier` |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Vérificateur gère ses propres observations. Admin lit tout.

#### `global_stats`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `metal_type` | TEXT UNIQUE | Type métal |
| `density_mean` | NUMERIC | Densité moyenne |
| `compaction_mean`, `purity_mean` | NUMERIC | Moyennes visuelles |
| `volume_error_mean` | NUMERIC | Erreur volume moyenne |
| `nb_measurements` | INTEGER | Nombre de mesures |
| `updated_at` | TIMESTAMPTZ | |

**RLS** : Tous lisent (y compris anon). `service_role` écrit.

#### `object_profiles`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `object_type` | TEXT UNIQUE | Type d'objet |
| `avg_width_cm`, `avg_height_cm`, `avg_depth_cm` | NUMERIC | Dimensions moyennes |
| `avg_weight_kg` | NUMERIC | Poids moyen |
| `density_mean` | NUMERIC | Densité moyenne |
| `nb_measurements` | INTEGER | |
| `updated_at` | TIMESTAMPTZ | |

**RLS** : Tous lisent (y compris anon). `service_role` écrit.

#### `audit_learning_log`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `event_type` | TEXT | Type d'événement |
| `metal_type`, `object_type` | TEXT | Contexte |
| `measurement_id` | UUID | Mesure déclenchante |
| `delta_density`, `delta_compaction`, `delta_purity` | NUMERIC | Variations |
| `nb_measurements_before`, `nb_measurements_after` | INT | Compteurs |
| `triggered_by` | TEXT | Déclencheur |
| `created_at` | TIMESTAMPTZ | |

**RLS** : Tous les authentifiés lisent. `service_role` écrit.

#### `app_settings`
| Colonne | Type | Rôle |
|---|---|---|
| `id` | UUID PK | |
| `key` | TEXT UNIQUE | Clé du paramètre |
| `value` | JSONB | Valeur |
| `description` | TEXT | Description |
| `updated_at` | TIMESTAMPTZ | |

**Valeur actuelle** : `external_transport_enabled = false`  
**RLS** : Tous les authentifiés lisent et modifient (politique trop permissive — voir section 11).

#### `clients` (legacy)
Table initiale remplacée par `companies`. Contient `id` et `name`. Probablement inutilisée en production.

#### Tables agrégateur (référencées dans le code, sans migration trouvée)
Les tables suivantes sont référencées dans `/api/aggregator/calculate-sale` mais **aucune migration SQL n'a été trouvée** dans le dépôt :
- `credit_sales` — ventes de crédits carbone
- `credit_sale_lots` — lots associés à une vente
- `credit_lots` — lots de crédits
- `credit_sale_allocations` — répartitions calculées
- `distribution_rules` — règles de distribution par agrégateur
- `member_distribution_overrides` — overrides par membre

### Fonctions PostgreSQL

| Fonction | Rôle |
|---|---|
| `set_updated_at()` | Trigger `updated_at` automatique |
| `set_transport_updated_at()` | Idem pour transport |
| `is_company_member(UUID)` | Vérifie appartenance entreprise |
| `is_company_owner(UUID)` | Vérifie rôle owner |
| `company_has_no_members(UUID)` | Bootstrap premier owner |
| `is_project_admin()` | Vérifie rôle admin MRV |
| `is_verifier()` | Vérifie rôle vérificateur |
| `is_project_client()` | Vérifie rôle client projet |
| `is_admin_from_auth()` | Vérifie rôle admin depuis `auth.users` |
| `compute_scan_event_hash()` | Trigger hash SHA-256 + advisory lock |
| `verify_container_chain(UUID)` | Vérifie intégrité chaîne de hachage |
| `get_invitation_by_token(TEXT)` | RPC SECURITY DEFINER (accessible anon) |

---

## 6. Modules fonctionnels

### Module 1 — Authentification & Organisation

**Responsabilités** : Inscription entreprise, connexion, invitation membres, gestion rôles.

- Inscription : création `auth.users` → `companies` → `company_members` (owner)
- Connexion : `signInWithPassword` → redirection selon rôle (`app_metadata.role`)
- Invitation : génération token → email → page `/invitation/[token]` → acceptation
- Rôles applicatifs : `admin`, `project_admin`, `verifier`, `client` (dans `auth.users` metadata)
- Rôles entreprise : `owner`, `terrain` (dans `company_members`)

### Module 2 — Analyse IA des Métaux

**Responsabilités** : Analyse photo par vision IA, estimation poids/valeur, stockage mesures.

- Capture photo (caméra ou upload)
- Envoi à Gemini 2.5 Flash via `/api/ai/analyze-photo`
- Prompt structuré : identification métal, dimensions, volume, poids, valeur
- Normalisation résultat (aliases métal, coefficients densité)
- Stockage dans `raw_measurements`
- Prédiction améliorée via `/api/predict` (stats globales ou profils objets)

### Module 3 — Traçabilité des Conteneurs

**Responsabilités** : Gestion conteneurs, scan QR, chaîne de hachage immuable.

- CRUD conteneurs par entreprise
- Scanner QR (jsqr + canvas) avec saisie manuelle de secours
- Enregistrement `scan_events` (dépôt, collecte, vérification)
- Chaîne de hachage SHA-256 avec advisory lock (anti-concurrence)
- Vérification intégrité via `verify_container_chain()`
- Visualisation historique et graphique remplissage

### Module 4 — Transport

**Responsabilités** : Création et suivi transport interne, calcul distance et GES.

- Transport interne METALTRACE (provider = `internal`)
- Transport client (provider = `client`)
- Calcul distance via OpenRouteService (géocodage + itinéraire HGV)
- Calcul GES transport (facteur ADEME 0.062 kgCO2e/tkm camion)
- Statuts : `scheduled` → `in_transit` → `arrived` → `delivered`
- Preuves : photo + document
- Intégration MRV : log activité automatique à la livraison
- Feature flag `external_transport_enabled` (actuellement `false`)
- Stubs Groupe Robert présents mais non connectés

### Module 5 — MRV Carbone (ISO 14064-2)

**Responsabilités** : Monitoring, Reporting, Verification des réductions GES.

- Gestion projets carbone (draft → active → verified)
- Calcul GES : baseline vs scénario projet (ADEME Base Carbone 2023)
- Activités : transport, recyclage (acier, aluminium, cuivre)
- Facteurs d'émission configurables (CRUD admin)
- Logs d'activité avec preuves (photos, documents, GPS)
- Sessions de vérification tierces (Bureau Veritas, etc.)
- Export rapport ISO 14064-2 JSON
- Interface vérificateur dédiée avec observations (conforme/non conforme/à clarifier)
- Tests automatisés (Jest) couvrant calculs GES et logique RLS

### Module 6 — Agrégateur / Crédits Carbone

**Responsabilités** : Calcul répartition revenus vente crédits carbone entre membres.

- Fonction pure `calculateDistribution` (src/lib/distribution-calculator.ts)
- Cascade : pondération → part brute → frais plateforme → réserve → montant net
- Overrides par membre (fee_pct, reserve_pct, weight_multiplier) avec dates d'effet
- Route API POST `/api/aggregator/calculate-sale`
- Upsert dans `credit_sale_allocations`
- **Note** : tables SQL non migrées (voir section 11)

### Module 7 — Prix Métaux

**Responsabilités** : Affichage prix spot métaux en temps réel.

- Fetch Metals.Dev API (cuivre, aluminium en $CA/kg)
- Cache ISR 10 minutes
- Tendance up/down/neutral (comparaison cache précédent)
- Affichage dans Topbar (ticker desktop) et AdminKPIGrid (carte cuivre)
- Fer et Acier marqués `available: false` (non disponibles dans Metals.Dev)

### Module 8 — Administration

**Responsabilités** : Tableau de bord opérateur, gestion lots en attente, alertes.

- KPIs temps réel (lots en attente, traités, confiance IA, prix cuivre)
- Table lots en attente avec actions
- Graphiques (AdminCharts via Recharts)
- Alertes capteurs (SensorAlerts — données statiques actuellement)

---

## 7. Composants React

### Composants de layout (globaux)

| Composant | Rôle | Dépendances |
|---|---|---|
| `AppLayout` | Layout principal — Sidebar + Topbar + MobileBottomNav | Supabase auth, rôle-aware |
| `Sidebar` | Navigation latérale collapsible, rôle-aware (client/admin/verifier) | `company_members`, `raw_measurements` (badge) |
| `Topbar` | Barre supérieure — ticker prix, notifications, déconnexion | `/api/metals-price`, `raw_measurements` |
| `MobileBottomNav` | Navigation mobile bas d'écran | — |

### Composants UI réutilisables (`src/components/ui/`)

| Composant | Rôle |
|---|---|
| `AppIcon` | Wrapper Heroicons (outline/solid) |
| `AppImage` | Wrapper next/image avec fallback |
| `AppLogo` | Logo METALTRACE (image + fallback texte) |
| `EmptyState` | État vide générique (icône + message + action) |
| `LoadingSkeleton` | Skeleton de chargement |
| `MetalBadge` | Badge coloré type métal |
| `MetricCard` | Carte KPI (valeur, tendance, icône, variante) |
| `QRCodeModal` | Modal affichage QR code (qrcode.react) |
| `StatusBadge` | Badge statut générique |

### Composants dashboard client (`src/app/components/`)

| Composant | Rôle | Tables |
|---|---|---|
| `ClientDashboardContent` | Orchestrateur dashboard client | — |
| `ClientKPIGrid` | Grille KPIs client (lots, conteneurs, GES) | `raw_measurements`, `containers` |
| `ClientQuickActions` | Actions rapides (nouveau lot, scanner) | — |
| `ContainerGrid` | Grille conteneurs avec statuts | `containers` |
| `RecentLotsTable` | Tableau lots récents | `raw_measurements` |

### Composants admin dashboard (`src/app/admin-dashboard/components/`)

| Composant | Rôle | Tables |
|---|---|---|
| `AdminDashboardContent` | Orchestrateur dashboard admin | — |
| `AdminKPIGrid` | KPIs admin (lots, confiance IA, prix cuivre) | `raw_measurements`, `/api/metals-price` |
| `PendingLotsTable` | Table lots en attente de traitement | `raw_measurements` |
| `AdminCharts` / `AdminChartsInner` | Graphiques (Recharts, Server/Client split) | `raw_measurements` |
| `SensorAlerts` | Alertes capteurs (statique) | — |

### Composants wizard nouveau lot (`src/app/new-lot/components/`)

| Composant | Rôle |
|---|---|
| `NewLotWizard` | Orchestrateur wizard 5 étapes |
| `StepContainer` | Wrapper étape avec progression |
| `StepPhotoCapture` | Capture photo (caméra/upload) |
| `StepPhotoAnalysis` | Envoi photo + paramètres à l'API |
| `StepAIResult` | Affichage résultat analyse IA |
| `StepConfirmSubmit` | Confirmation avant soumission |
| `StepConfirmation` | Confirmation finale |

### Composants scanner QR (`src/app/qr-code-scanner/components/`)

| Composant | Rôle |
|---|---|
| `QRScannerContent` | Orchestrateur scanner |
| `QRScannerViewfinder` | Viewfinder caméra + décodage jsqr |
| `ManualEntry` | Saisie manuelle QR |
| `ContainerResult` | Résultat scan (info conteneur) |
| `RecentScans` | Historique scans récents |

### Composants détail conteneur (`src/app/container-detail/components/`)

| Composant | Rôle |
|---|---|
| `ContainerDetailContent` | Orchestrateur |
| `ContainerHeader` | En-tête conteneur |
| `ContainerInfoPanel` | Informations générales |
| `ContainerFillChart` / `ContainerFillChartInner` | Graphique remplissage (Server/Client split) |
| `ContainerQRCode` | Affichage QR code |
| `SensorPanel` | Données capteurs |
| `ContainerLotHistory` | Historique lots |

### Composants gestion lots (`src/app/lot-management/components/`)

| Composant | Rôle |
|---|---|
| `LotManagementContent` | Orchestrateur |
| `LotListSidebar` | Liste lots avec filtres |
| `LotDetailPanel` | Détail lot sélectionné |
| `ContainersListSection` | Section conteneurs |

---

## 8. Authentification et sécurité

### Authentification

- **Provider** : Supabase Auth (email/password uniquement)
- **Client navigateur** : `createBrowserClient` (@supabase/ssr) avec fallback localStorage si cookies tiers bloqués
- **Client serveur** : `createServerClient` (@supabase/ssr) avec cookies Next.js
- **Session** : JWT Supabase, refresh automatique via middleware
- **Cookies** : `SameSite=None; Secure; Partitioned` (cross-origin iframe compatible)

### Middleware (`src/middleware.ts`)

- Intercepte toutes les routes sauf `_next/static`, `_next/image`, `favicon.ico`, `assets/`, `api/`
- Routes publiques : `/login`, `/invitation/*`
- Non authentifié → redirect `/login`
- Authentifié sur `/login` → redirect `/`
- Refresh session à chaque requête

### Autorisation par rôle

Les rôles sont stockés dans `auth.users.app_metadata.role` ou `user_metadata.role` :

| Rôle | Accès | Redirection login |
|---|---|---|
| `admin` / `project_admin` | Dashboard admin, toutes les pages admin | `/admin-dashboard` |
| `verifier` | Interface vérificateur uniquement | `/verifier-mrv` |
| `client` (défaut) | Dashboard client, pages client | `/` |

`AppLayout` vérifie le rôle côté client et redirige si incohérence (ex: client accédant à `/admin-dashboard`).

### Row Level Security (RLS)

Toutes les tables ont RLS activé. Stratégies principales :

| Pattern | Tables concernées |
|---|---|
| `client_id = auth.uid()` | `raw_measurements` (legacy) |
| `is_company_member(company_id)` | `raw_measurements`, `containers`, `scan_events` |
| `is_company_owner(company_id)` | `containers` (write), `company_members` (write), `invitations` (write) |
| `is_project_admin()` | `projects`, `emission_factors`, `project_activity_logs`, `evidence_files`, `verification_sessions` |
| `is_verifier()` | Lecture `projects`, `project_activity_logs`, `evidence_files`, `verification_sessions` |
| `verifier_id = auth.uid()` | `verifier_observations` |
| `service_role` bypass | `raw_measurements`, `global_stats`, `object_profiles` |
| Lecture publique | `global_stats`, `object_profiles` (y compris anon) |

### Points de sécurité notables

- **Chaîne de hachage** : `scan_events` utilise SHA-256 + advisory lock pour garantir l'immuabilité et l'ordre des scans
- **RPC SECURITY DEFINER** : `get_invitation_by_token` accessible par `anon` (nécessaire pour la page d'invitation)
- **Service role** : utilisé uniquement dans `/api/stats/update` pour agréger les stats globales (bypass RLS justifié)
- **Patch fetch** : le client navigateur injecte un token `x-sb-token` dans les requêtes internes (workaround cross-origin)
- **`AuthContext`** : présent dans `src/contexts/` mais **non injecté dans `layout.tsx`** — non utilisé dans l'application principale

---

## 9. Intégrations externes

### Supabase

- **URL** : `NEXT_PUBLIC_SUPABASE_URL` (configuré)
- **Anon Key** : `NEXT_PUBLIC_SUPABASE_ANON_KEY` (configuré)
- **Service Role Key** : `SUPABASE_SERVICE_ROLE_KEY` (utilisé dans `/api/stats/update`)
- **Utilisation** : Auth, base de données (PostgreSQL), RLS, RPC, pgcrypto

### Google Gemini (IA)

- **Clé** : `GEMINI_API_KEY` (configurée)
- **Modèle** : `gemini/gemini-2.5-flash`
- **SDK** : `@rocketnew/llm-sdk` (abstraction multi-provider)
- **Utilisation** : Analyse photo métal (vision multimodale), chat completion
- **Route** : `/api/ai/analyze-photo` et `/api/ai/chat-completion`
- **Prompt** : Identification métal, dimensions, volume, poids, valeur estimée

### Metals.Dev API

- **Clé** : `METALS_API_KEY` (⚠️ **non trouvée dans `.env`** — variable manquante)
- **Endpoint** : `https://api.metals.dev/v1/latest?currency=CAD&unit=kg`
- **Utilisation** : Prix spot cuivre et aluminium en $CA/kg
- **Cache** : ISR 10 minutes + in-memory pour tendances
- **Route** : `/api/metals-price`

### OpenRouteService

- **Clé** : `OPENROUTESERVICE_API_KEY` (⚠️ placeholder `your-openrouteservice-api-key-here`)
- **Endpoints** : Géocodage (`/geocode/search`) + Directions HGV (`/v2/directions/driving-hgv`)
- **Utilisation** : Calcul distance routière pour transport
- **Route** : `/api/transport/calculate-distance`

### OpenStreetMap / OSRM (Nominatim + OSRM)

- **Pas de clé requise** (services publics)
- **Utilisation** : Géocodage et calcul distance dans `/api/transport/complete`
- **Endpoints** : `nominatim.openstreetmap.org`, `router.project-osrm.org`
- **Note** : Deux systèmes de géocodage coexistent (OpenRouteService ET Nominatim/OSRM)

### Groupe Robert (DEPRECATED)

- **Clé** : `GROUPE_ROBERT_API_KEY` (non configurée, non utilisée)
- **Statut** : Stubs mock présents dans `/api/external/grouperobert/` — non connectés
- **Remplacement** : Transport interne METALTRACE

### OpenAI / Anthropic / Perplexity

- **Clés** : `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `PERPLEXITY_API_KEY` (placeholders)
- **Utilisation** : Disponibles via `/api/ai/chat-completion` mais non utilisés activement
- **Statut** : Infrastructure prête, clés non configurées

### Webflow

- **Intégration** : Mentionnée dans `integration_context` mais aucun code Webflow trouvé dans le projet

### Google Analytics / AdSense

- **Clés** : `NEXT_PUBLIC_GA_MEASUREMENT_ID`, `NEXT_PUBLIC_ADSENSE_ID` (placeholders)
- **Statut** : Non implémentés dans le code

### Stripe

- **Clé** : `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` (placeholder)
- **Statut** : Non implémenté

---

## 10. État du projet

### ✅ Fonctionnalités terminées

| Fonctionnalité | Détail |
|---|---|
| Authentification complète | Login, inscription, invitation, middleware, rôles |
| Gestion multi-entreprises | Companies, members, invitations avec RLS |
| Analyse IA photo métal | Gemini Vision, wizard 5 étapes, stockage |
| Scanner QR | jsqr + canvas, saisie manuelle, historique |
| Traçabilité conteneurs | CRUD, scan events, chaîne de hachage SHA-256 |
| Transport interne | Création, statuts, preuves, calcul GES |
| MRV ISO 14064-2 | Projets, logs, preuves, sessions, rapport JSON |
| Facteurs d'émission | CRUD admin, calcul GES avec fallbacks ADEME |
| Interface vérificateur | Sessions, observations, vérification chaîne |
| Prix métaux temps réel | Metals.Dev, cache ISR, tendances |
| Dashboard admin | KPIs, lots en attente, prix cuivre live |
| Dashboard client | KPIs, lots récents, conteneurs |
| Calcul répartition crédits | `distribution-calculator.ts` + route API |
| Tests automatisés MRV | Jest, 4 suites, calculs GES et RLS |

### ⚠️ Fonctionnalités partielles

| Fonctionnalité | Ce qui manque |
|---|---|
| Module agrégateur | Tables SQL (`credit_sales`, `credit_lots`, etc.) non migrées |
| Calcul distance transport | Deux systèmes coexistent (OpenRouteService + OSRM) — incohérence |
| Notifications | Affichées dans Topbar mais pas de système de marquage lu/archivage |
| Facturation | KPI "Factures impayées" = 0 statique, module non implémenté |
| Capteurs IoT | KPI "Conteneurs ≥ 85%" = 0 statique, SensorAlerts statique |
| Filtrage par projet (carbon-impact) | `filteredLogs` ne filtre pas réellement par projet (TODO dans le code) |
| `AuthContext` | Présent mais non utilisé dans l'app (non injecté dans layout) |

### ❌ Fonctionnalités incomplètes / non implémentées

| Fonctionnalité | État |
|---|---|
| Intégration Groupe Robert | Stubs mock uniquement, pas de vraie API |
| Carte GPS transport | Placeholder "intégration à venir" dans TransportCard |
| Module facturation | Mentionné dans sidebar admin mais pointe vers `/` |
| Module "Prix métaux" admin | Lien sidebar pointe vers `/` (non implémenté) |
| Module "Clients" admin | Lien sidebar pointe vers `/` (non implémenté) |
| Module "Factures" admin | Lien sidebar pointe vers `/` (non implémenté) |
| Stripe | Clé présente mais aucun code Stripe |
| Google Analytics | Clé présente mais non implémenté |
| Webflow | Mentionné dans intégrations mais aucun code |
| `audit_learning_log` | Table créée, jamais alimentée par le code applicatif |
| `clients` table | Table legacy, probablement inutilisée |

### 📝 TODO identifiés dans le code

| Fichier | TODO |
|---|---|
| `carbon-impact/page.tsx` | Filtrage logs par projet non implémenté (commentaire dans le code) |
| `api/external/grouperobert/create-shipment/route.ts` | "Replace this mock with real Groupe Robert API integration" |
| `api/external/grouperobert/shipment-status/route.ts` | "Replace this mock with real Groupe Robert API integration" |
| `api/measurements/confirm/route.ts` | `transportFees` toujours 0 même si `transport_provider !== 'internal'` |

---

## 11. Dette technique

### Duplications

| Problème | Détail |
|---|---|
| Deux systèmes de géocodage | `OpenRouteService` dans `/api/transport/calculate-distance` ET `Nominatim + OSRM` dans `/api/transport/complete` — logique dupliquée, comportements potentiellement différents |
| Deux routes de mise à jour statut | `/api/transport/update-status` (POST) ET `/api/transport/[id]/status` (PATCH) — fonctionnalité identique |
| `client_id` et `company_id` | `raw_measurements` a les deux colonnes — `client_id` est legacy, `company_id` est le modèle actuel. Coexistence source de confusion |
| Calcul GES dupliqué | Logique GES dans `/api/ghg/calculate`, `/api/transport/complete`, et `/api/transport/internal-create` — facteurs ADEME hardcodés à plusieurs endroits |
| Rôle admin vérifié de deux façons | `is_project_admin()` (via `raw_user_meta_data`) ET `is_admin_from_auth()` (même logique, autre nom) — deux fonctions SQL pour le même besoin |

### Dépendances inutiles ou à risque

| Dépendance | Risque |
|---|---|
| `@jest/globals ^30.4.1` | Dépendance de test en `dependencies` (pas `devDependencies`) — alourdit le bundle |
| `lucide-react ^1.7.0` | Coexiste avec `@heroicons/react` — deux librairies d'icônes |
| `SUPABASE_SERVICE_ROLE_KEY` | Utilisé côté serveur dans `/api/stats/update` — clé non visible dans `.env` audité (masquée ou absente) |
| `METALS_API_KEY` | Non présente dans `.env` — la route `/api/metals-price` retourne 500 si absente |

### Risques identifiés

| Risque | Sévérité | Détail |
|---|---|---|
| Tables agrégateur sans migration | 🔴 Élevé | `/api/aggregator/calculate-sale` référence 6 tables inexistantes en base — la route échoue en production |
| `METALS_API_KEY` manquante | 🔴 Élevé | Variable non trouvée dans `.env` — prix métaux non fonctionnels |
| `app_settings` RLS trop permissive | 🟡 Moyen | Tout utilisateur authentifié peut modifier les feature flags (ex: activer transport externe) |
| `AuthContext` non utilisé | 🟡 Moyen | Présent mais non injecté — risque de confusion pour les développeurs futurs |
| `client_id` legacy dans `raw_measurements` | 🟡 Moyen | Colonne orpheline, RLS basée sur `company_id` — `client_id` peut induire en erreur |
| Timestamp hardcodé dans AdminDashboardContent | 🟢 Faible | "04/06/2026 14:02" codé en dur dans le composant |
| `lot-management/page.tsx` force `userRole="admin"` | 🟡 Moyen | Page partagée admin/client mais rôle forcé à `admin` — les clients ne peuvent pas y accéder correctement |
| Pas de rate limiting sur les routes API | 🟡 Moyen | Routes IA et stats sans protection contre les abus |
| `OPENROUTESERVICE_API_KEY` placeholder | 🟡 Moyen | Calcul distance transport non fonctionnel |
| Fetch interne avec `NEXT_PUBLIC_SITE_URL` | 🟢 Faible | Plusieurs routes font des fetch internes vers d'autres routes — fragile en cas de changement d'URL |

### Points sensibles

| Point | Détail |
|---|---|
| Chaîne de hachage scan_events | Fonctionnalité critique pour l'audit — tout bug dans `compute_scan_event_hash` invalide la traçabilité |
| Service role key | Utilisée dans `/api/stats/update` — si exposée, accès total à la base |
| RPC `get_invitation_by_token` accessible anon | Nécessaire mais expose des informations d'entreprise à des utilisateurs non authentifiés |
| `ignoreBuildErrors: true` dans next.config.mjs | Les erreurs TypeScript ne bloquent pas le build — risque de régressions silencieuses |

---

## 12. Recommandations

### 🔴 Priorité élevée

| # | Recommandation | Justification |
|---|---|---|
| P1 | **Créer les migrations SQL pour le module agrégateur** | 6 tables référencées dans `/api/aggregator/calculate-sale` n'existent pas en base — la route est non fonctionnelle |
| P2 | **Configurer `METALS_API_KEY`** | Sans cette clé, le ticker de prix et la carte "Prix index cuivre" retournent des erreurs 500 |
| P3 | **Configurer `OPENROUTESERVICE_API_KEY`** | Sans cette clé, le calcul de distance transport est non fonctionnel |
| P4 | **Restreindre la RLS de `app_settings`** | Actuellement tout utilisateur authentifié peut modifier les feature flags — restreindre aux admins |
| P5 | **Supprimer ou migrer `client_id` de `raw_measurements`** | Colonne legacy source de confusion — migrer vers `company_id` uniquement |

### 🟡 Priorité moyenne

| # | Recommandation | Justification |
|---|---|---|
| P6 | **Unifier les systèmes de géocodage** | Choisir entre OpenRouteService et Nominatim/OSRM — supprimer le doublon |
| P7 | **Supprimer la route DEPRECATED `/api/transport/create`** | Redirige vers `internal-create` — source de confusion et latence inutile |
| P8 | **Supprimer la route DEPRECATED `/api/transport/poll-status`** | Retourne 410 — peut être supprimée |
| P9 | **Déplacer `@jest/globals` en `devDependencies`** | Dépendance de test ne doit pas être en `dependencies` |
| P10 | **Supprimer ou unifier les deux fonctions admin** | `is_project_admin()` et `is_admin_from_auth()` font la même chose — consolider |
| P11 | **Corriger `lot-management/page.tsx`** | `userRole="admin"` forcé — les clients ne peuvent pas accéder à leur gestion de lots |
| P12 | **Implémenter le filtrage par projet dans `carbon-impact`** | Le filtre est présent dans l'UI mais non fonctionnel (TODO dans le code) |
| P13 | **Supprimer ou documenter `AuthContext`** | Non utilisé dans l'app — soit l'intégrer dans `layout.tsx`, soit le supprimer |
| P14 | **Unifier la mise à jour de statut transport** | Deux routes pour la même chose — garder uniquement `PATCH /api/transport/[id]/status` |
| P15 | **Retirer le timestamp hardcodé** | "04/06/2026 14:02" dans `AdminDashboardContent` — utiliser `new Date()` |

### 🟢 Priorité faible

| # | Recommandation | Justification |
|---|---|---|
| P16 | **Supprimer `lucide-react` ou `@heroicons/react`** | Deux librairies d'icônes coexistent — choisir une seule |
| P17 | **Supprimer la table `clients` legacy** | Remplacée par `companies` — source de confusion |
| P18 | **Alimenter `audit_learning_log`** | Table créée mais jamais utilisée par le code applicatif |
| P19 | **Activer `ignoreBuildErrors: false`** | Les erreurs TypeScript doivent bloquer le build en production |
| P20 | **Ajouter rate limiting sur les routes IA** | `/api/ai/analyze-photo` et `/api/ai/chat-completion` sans protection |
| P21 | **Implémenter les modules manquants** | Facturation, Clients admin, Prix métaux admin (liens sidebar pointent vers `/`) |
| P22 | **Documenter le module agrégateur** | Schéma SQL, RLS, et flux métier non documentés |
| P23 | **Remplacer les fetch internes** | Utiliser des imports directs plutôt que des fetch vers `NEXT_PUBLIC_SITE_URL` |
| P24 | **Supprimer les stubs Groupe Robert** | `/api/external/grouperobert/*` — code mort si l'intégration n'est pas prévue |

---

*Rapport généré automatiquement le 2026-07-06 — Audit en lecture seule — Aucune modification effectuée.*
