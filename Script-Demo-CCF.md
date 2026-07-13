# Script de démonstration — MetalTrace CCF (Centre de Consolidation Ferroviaire)

**Base de données** : reset du 13 juillet 2026 (voir `ADR-MVP.md` §9quinquatricies). Données 100 % issues de `supabase/seeds/demo_ccf.sql`, aucun artefact de test QA restant.

**Comptes réels utilisables en direct :**

| Compte | Rôle | Organisation |
|---|---|---|
| `centredelasante@gmail.com` | admin | Centre de Consolidation Ferroviaire Québec (coordonnateur) |
| `claudefairplay@hotmail.com` | membre | Acier Laurentien Inc. (manufacturier, participant) |

Il n'existe **pas** de compte réel rattaché à RecyclMétal Estrie (recycleur, 3ᵉ organisation du seed) — si le point de vue recycleur doit être montré, le faire uniquement en lecture via le compte coordonnateur (qui voit tout), pas par connexion directe.

---

## Avant de commencer (5 min avant la démo)

1. Se connecter avec `centredelasante@gmail.com` et vérifier que `/projets` affiche bien « 1 projet accessible » — déjà confirmé le 13 juillet, mais à revérifier le jour même.
2. **Point d'attention : l'onglet Documents du projet est actuellement vide** (le seed ne crée aucun document, et un document implique un vrai fichier dans Storage, pas seulement une ligne SQL). Deux options, à décider avant la démo :
   - Déposer un document de démonstration (ex. « Bon de transport ») quelques minutes avant, pour que l'onglet ne soit pas vide.
   - Ou transformer ça en moment interactif : déposer le document **en direct** devant l'audience (§4 ci-dessous) — montre que l'outil est réellement fonctionnel, pas une maquette statique. Recommandé si le temps le permet.
3. Avoir les deux comptes prêts dans deux fenêtres/navigateurs différents (ou navigation privée) si le passage coordonnateur → membre doit être montré en direct.

---

## Trame narrative (≈ 12-15 minutes)

### 1. Mise en contexte (1 min)

Expliquer le problème que MetalTrace CCF résout : des organisations qui manipulent des métaux (manufacturiers, recycleurs) veulent consolider leurs chargements pour un transport ferroviaire plus économique et moins polluant, mais elles ne se connaissent pas et n'ont pas d'outil pour coordonner ça. Le CCF joue le rôle de coordonnateur neutre.

### 2. Les organisations et leurs capacités (2 min)

Connecté comme `centredelasante@gmail.com` (coordonnateur) :

- Aller sur **Organisations** — montrer les 3 organisations pilotes (Centre de Consolidation Ferroviaire Québec, Acier Laurentien Inc., RecyclMétal Estrie), leurs régions (Laurentides, Estrie) et niveaux de maturité.
- Aller sur **Capacités** — montrer les 3 capacités déclarées : acier ferreux (45 t/mois, qualifiée), aluminium (12,5 t/mois, déclarée — pas encore qualifiée, bon exemple pour expliquer le cycle de qualification), cuivre (8 t/mois, qualifiée).

Point de discours : une capacité « déclarée » doit être qualifiée par le coordonnateur avant de pouvoir être associée à une opportunité — filtre de qualité.

### 3. L'opportunité et le fit des capacités (2 min)

Aller sur **Opportunités** — ouvrir « Consolidation ferroviaire — Métaux ferreux et non-ferreux Q3 2026 » :

- Volume cible 65 tonnes, corridor Laurentides → Estrie → Québec, priorité haute.
- Montrer les 2 capacités associées avec leur score de compatibilité (fit score) : acier 92 %, aluminium 78 % — illustre l'aide à la décision pour le coordonnateur.
- Mentionner que cette opportunité a déjà été convertie en projet (statut qualifiée → projet créé).

### 4. Le projet en cours d'exécution (5-6 min, cœur de la démo)

Aller sur **Projets** → ouvrir « Projet CCF-2026-Q3 — Consolidation ferroviaire Laurentides-Estrie », phase **Exécution**.

- **Onglet Participants** : Acier Laurentien Inc. et RecyclMétal Estrie, tous deux actifs, rôle contributeur — montrer que chacun a un mandat opérationnel distinct (permissions différentes selon le rôle : le manufacturier peut inviter/gérer les participants, le recycleur peut accepter des invitations et soumettre des preuves logistiques).
- **Onglet Documents** : si un document a été pré-déposé, le montrer (statut, version) ; sinon, déposer un document en direct ici — bon moment pour montrer le cycle de vie (brouillon → soumis → approuvé).
- **Onglet Logistique** : montrer les 3 étapes — ramassage (complétée), chargement (complétée), livraison (planifiée, dans 10 jours). Bonne histoire visuelle : le projet avance réellement dans le temps. Optionnel : montrer le bouton « Ajouter une étape » sans nécessairement l'utiliser.
- **Onglet Rapport de valeur** : montrer le rapport brouillon — 57,5 tonnes consolidées, 12 800 $ d'économies logistiques estimées, ~4,2 tCO2e de réduction GES. C'est le chiffre qui justifie la valeur du CCF pour un investisseur/partenaire.

### 5. Les mandats (2 min)

Aller sur **Mandats** — montrer les 2 mandats actifs (coordonnateur → manufacturier, coordonnateur → recycleur), leurs portées (« opérationnel ») et les permissions accordées (JSON `actions`). Bon endroit pour expliquer que chaque organisation n'a accès qu'à ce que son mandat autorise explicitement — pas d'accès implicite.

### 6. (Optionnel) Point de vue d'un participant (2 min)

Si le temps le permet, se reconnecter avec `claudefairplay@hotmail.com` (Acier Laurentien) pour montrer que la vue est différente : accès limité à ses propres projets/mandats, pas de vue d'ensemble multi-organisations comme le coordonnateur.

### 7. Clôture (1 min)

Résumer le parcours complet montré (organisation → capacité → opportunité → projet → logistique → valeur) et, si pertinent pour l'audience, mentionner la feuille de route suivante (volet crédit carbone / regroupement, en cours d'audit, pas encore construit — ne pas sur-promettre).

---

## Pièges à éviter

- Ne pas cliquer sur « Ajouter une étape » ou modifier un statut logistique sans avoir un plan de retour (remettre l'étape à son état d'origine après, comme fait pendant les tests du 13 juillet) — sinon la prochaine démo repart d'un état différent.
- Le compte `claudefairplay@hotmail.com` n'est PAS admin — certains boutons (inviter une organisation, ajouter une étape) ne lui seront pas visibles, c'est le comportement attendu, pas un bug.
- Si une erreur survient pendant la démo, le message affiché est maintenant le vrai message Postgres/RLS (voir `ADR-MVP.md` §9quatertricies) — plus lisible qu'avant, mais à anticiper si une action est tentée hors du scénario prévu.
