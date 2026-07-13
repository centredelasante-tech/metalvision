# Brief Rocket — Écran S08 (`/evenements`)

**Contexte :** le backend de S08 est déjà complet et conforme — aucune migration corrective nécessaire (voir `ADR-MVP.md` §9novies). Cet écran est **en lecture seule** : aucune RPC, aucune insertion, aucune transition de statut à gérer côté frontend.

---

## 1. Objectif de l'écran

Route `/evenements`. Journal des événements métier (`business_events`), filtrable par objet, projet, organisation. Référence : backlog technique v1.0, E10 (« Événements métier et audit logs »), tâche E10-T03.

## 2. Schéma existant — `public.business_events` (ne pas modifier, lecture seule)

| Colonne | Type | Détail |
|---|---|---|
| `id` | UUID | PK |
| `event_type` | ENUM `ccf_event_type` | Catalogue fermé, 19 valeurs (liste ci-dessous) |
| `object_type` | text | `organization`, `capability`, `opportunity`, `project`, `mandate`, `document`, `logistics_step`, `value_report` |
| `object_id` | UUID | Référence polymorphique vers l'objet concerné |
| `actor_id` | UUID | Utilisateur ayant déclenché l'événement (`profiles.id`) |
| `organization_id` | UUID | Organisation associée à l'événement |
| `payload` | jsonb | Détails variables selon `event_type` — pas de schéma fixe, afficher tel quel ou extraire les clés connues au cas par cas |
| `created_at` | timestamptz | |

### Catalogue `ccf_event_type` (19 valeurs)

```
organization_created, organization_suspended,
member_invited, member_activated,
mandate_issued, mandate_accepted, mandate_revoked,
capability_declared, capability_qualified,
opportunity_created, opportunity_qualified,
project_created, project_phase_changed,
document_submitted, document_approved, document_rejected, document_archived,
logistics_step_updated, value_report_generated
```

Ne pas coder cette liste en dur si possible — elle peut évoluer. Si un affichage lisible par type est nécessaire (icône, libellé français), prévoir un mapping mais garder un fallback générique pour toute valeur non reconnue (l'ENUM peut recevoir de nouvelles valeurs sans que le frontend soit mis à jour en même temps).

## 3. Comportement de visibilité (RLS déjà en place — ne pas filtrer côté client)

Une simple `SELECT * FROM business_events` retourne déjà exactement ce que l'utilisateur a le droit de voir :
- Les événements où `organization_id` correspond à une organisation dont il est membre actif, **ou**
- Les événements dont il est lui-même `actor_id` (même hors de son organisation actuelle), **ou**
- Tout, s'il est super-admin plateforme.

**Point important à comprendre avant de construire les filtres** : la visibilité est scoped à l'organisation *enregistrée sur l'événement*, pas à tous les participants d'un projet lié. Un utilisateur ne verra donc pas automatiquement l'historique complet d'un projet auquel il participe si les événements ont été enregistrés sous l'organisation d'une autre partie prenante. C'est le comportement voulu par la spec actuelle (pas un bug) — à garder en tête si un utilisateur rapporte « je ne vois pas tous les événements de mon projet ».

## 4. Filtres attendus

- **Par organisation** : filtre direct sur `organization_id` (limité aux organisations dont l'utilisateur est membre, puisque RLS ne retournera rien d'autre de toute façon).
- **Par type d'objet** : filtre direct sur `object_type`.
- **Par objet spécifique** : filtre sur `object_type` + `object_id` (utile pour le composant `ObjectTimeline`, voir §5).
- **Par « projet »** : **clarification de portée pour le MVP** — `business_events` n'a pas de colonne `project_id`. Un filtre "projet" ne peut donc, sans jointure supplémentaire, cibler que les événements où `object_type = 'project'` et `object_id = <id du projet choisi>` (c'est-à-dire les événements du projet lui-même : `project_created`, `project_phase_changed` — pas les événements des documents/mandats/étapes logistiques qui lui sont rattachés). Une vue agrégée « tout ce qui concerne ce projet, tous objets confondus » nécessiterait de croiser plusieurs tables (documents, mandats, étapes logistiques liés au projet) et est **hors scope pour cette itération** — le construire uniquement si explicitement demandé, pas par défaut.

## 5. Composant `ObjectTimeline`

Composant réutilisable mentionné au backlog : « Affiche événements métier liés à un objet ». Reçoit `object_type` + `object_id` en props, affiche la liste chronologique des `business_events` correspondants (filtre direct, pas de jointure). Prévu pour être réutilisé plus tard sur d'autres écrans (ex. panneau de détail d'un document ou d'un mandat) — le construire comme un composant autonome, importable, pas comme du code dupliqué à l'intérieur de la page `/evenements`.

## 6. Ce qu'il n'y a pas à construire

- Aucun bouton d'action, aucune écriture. Écran 100 % lecture seule.
- Aucune RPC à appeler.
- Aucun risque de doublon `business_events` ici, puisque rien n'est inséré depuis cet écran.

## 7. Note de fond (informationnelle, pas une demande pour cette itération)

Le backlog technique prévoit un service applicatif partagé `publishBusinessEvent` (E10-T02) pour centraliser toutes les insertions dans `business_events`. Il n'a jamais été construit — chaque écran (mandats, opportunités, documents) réimplémente son propre insert. Ce n'est pas un blocage pour S08 (écran en lecture seule), mais si une prochaine itération touche à nouveau à un écran qui publie des événements, ce serait le bon moment pour centraliser plutôt que dupliquer une fois de plus.

## 8. Avant de livrer

PR revu selon `ROCKET_REVIEW_CHECKLIST.md` avant fusion, comme pour S06/S07 — en particulier vérifier qu'aucune écriture n'a été ajoutée par erreur sur un écran censé être en lecture seule, et que la branche part bien de `main` à jour sur l'ensemble des fichiers (pas seulement ceux annoncés comme modifiés).
