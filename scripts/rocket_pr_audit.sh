#!/usr/bin/env bash
# ============================================================================
# rocket_pr_audit.sh — Audit automatique d'une PR/branche livrée par Rocket
# ============================================================================
#
# Contexte : Rocket réintroduit systématiquement, PR après PR (10 occurrences
# confirmées au 13 juillet 2026, voir ADR-MVP.md et ROCKET_REVIEW_CHECKLIST.md
# §6), du contenu de fichiers déjà corrigé — même quand la branche part
# techniquement d'un commit à jour de `main`. La revue manuelle (diff +
# lecture ligne par ligne) reste nécessaire pour le contenu réellement neuf,
# mais elle est lente et sujette à l'erreur pour détecter les reverts.
#
# Ce script automatise la partie mécanique : pour chaque fichier modifié
# entre `origin/main` et la branche de Rocket, il vérifie si le contenu
# livré par Rocket est OCTET-IDENTIQUE à une version plus ancienne de ce même
# fichier dans l'historique de `main` (pas seulement la version actuelle).
# Si oui, c'est un signal fort et automatique de "stale revert" — le contenu
# existait déjà, a été remplacé/corrigé depuis, et Rocket vient de le
# réintroduire tel quel.
#
# Ce script ne remplace PAS la revue humaine du contenu réellement nouveau :
# il élimine seulement le travail répétitif de comparaison manuelle
# (git show <ref>:<path> | md5sum) qui a été fait à la main à chaque PR
# jusqu'ici.
#
# Usage :
#   scripts/rocket_pr_audit.sh <nom-de-branche-distante>
#   ex: scripts/rocket_pr_audit.sh rocket-update
#
# Prérequis : être dans le dépôt git, avoir un accès réseau à `origin`.
# ============================================================================

set -euo pipefail

BRANCH="${1:-}"
if [ -z "$BRANCH" ]; then
  echo "Usage: $0 <nom-de-branche-distante>" >&2
  echo "  ex: $0 rocket-update" >&2
  exit 1
fi

echo "→ Récupération de origin/main et origin/$BRANCH..."
git fetch origin main "$BRANCH" --quiet

BASE="origin/main"
HEAD="origin/$BRANCH"

if ! git rev-parse --verify "$HEAD" >/dev/null 2>&1; then
  echo "Erreur : la branche '$BRANCH' n'existe pas sur origin." >&2
  exit 1
fi

MERGE_BASE=$(git merge-base "$BASE" "$HEAD" 2>/dev/null || echo "")
MAIN_HEAD=$(git rev-parse "$BASE")

echo
echo "=== Résumé ==="
echo "origin/main         : $MAIN_HEAD"
echo "origin/$BRANCH       : $(git rev-parse "$HEAD")"
if [ "$MERGE_BASE" = "$MAIN_HEAD" ]; then
  echo "Point de départ     : la branche part bien du commit actuel de main (aucune divergence de base)."
else
  echo "Point de départ     : ⚠️  la branche NE part PAS du commit actuel de main (merge-base = $MERGE_BASE)."
fi

echo
echo "=== Diffstat ($BASE..$HEAD) ==="
git diff --stat "$BASE" "$HEAD"

echo
echo "=== Analyse fichier par fichier ==="

CHANGED_FILES=$(git diff --name-only "$BASE" "$HEAD")
STALE_COUNT=0
NEW_COUNT=0
UNCHANGED_COUNT=0
TOTAL_COUNT=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  TOTAL_COUNT=$((TOTAL_COUNT + 1))

  NEW_HASH=$(git rev-parse "$HEAD:$f" 2>/dev/null || echo "")
  CURRENT_HASH=$(git rev-parse "$BASE:$f" 2>/dev/null || echo "")

  if [ -z "$NEW_HASH" ]; then
    echo ""
    echo "· $f"
    echo "  [SUPPRIMÉ] Ce fichier existe sur main mais a été supprimé par la branche."
    echo "  → Vérifier si sa suppression est intentionnelle et demandée, sinon REJETER."
    continue
  fi

  if [ "$NEW_HASH" = "$CURRENT_HASH" ]; then
    UNCHANGED_COUNT=$((UNCHANGED_COUNT + 1))
    continue
  fi

  # Cherche si ce blob hash correspond à une version antérieure du fichier
  # n'importe où dans l'historique de main (pas seulement HEAD).
  MATCH_LINE=""
  if git cat-file -e "$BASE:$f" 2>/dev/null; then
    while IFS= read -r sha_date; do
      sha=$(echo "$sha_date" | awk '{print $1}')
      date=$(echo "$sha_date" | awk '{print $2}')
      old_hash=$(git rev-parse "${sha}:${f}" 2>/dev/null || echo "")
      if [ "$old_hash" = "$NEW_HASH" ]; then
        MATCH_LINE="$sha ($date)"
        break
      fi
    done < <(git log --format='%H %ad' --date=short "$BASE" -- "$f")
  fi

  echo ""
  echo "· $f"
  if [ -z "$CURRENT_HASH" ]; then
    echo "  [NOUVEAU FICHIER] N'existe pas sur main actuellement."
    echo "  → Revue manuelle complète requise (fonctionnalité neuve attendue ou fichier fantôme ?)."
    NEW_COUNT=$((NEW_COUNT + 1))
  elif [ -n "$MATCH_LINE" ]; then
    echo "  ⚠️  STALE REVERT SUSPECTÉ — contenu identique à une version antérieure : $MATCH_LINE"
    echo "  → main a divergé de ce contenu depuis. Rejeter cette version sans y toucher,"
    echo "    sauf si le brief demandait explicitement de revenir à cet état (rare)."
    STALE_COUNT=$((STALE_COUNT + 1))
  else
    echo "  ✅ Contenu modifié, aucune correspondance historique trouvée — probablement du travail neuf légitime."
    echo "  → Revue manuelle du contenu requise (diff détaillé, vérifier RLS/migrations si backend)."
    NEW_COUNT=$((NEW_COUNT + 1))
  fi
done <<< "$CHANGED_FILES"

echo ""
echo "=== Bilan ==="
echo "Fichiers analysés            : $TOTAL_COUNT"
echo "Identiques à main (no-op)    : $UNCHANGED_COUNT"
echo "Stale reverts suspectés       : $STALE_COUNT"
echo "Nouveaux/modifiés à revoir    : $NEW_COUNT"
echo ""
if [ "$STALE_COUNT" -gt 0 ]; then
  echo "⚠️  $STALE_COUNT fichier(s) semblent réintroduire du contenu déjà corrigé."
  echo "   Ne PAS fusionner cette branche directement. Revoir chaque fichier marqué"
  echo "   \"NOUVEAU/MODIFIÉ\" individuellement, extraire le contenu légitime à la main,"
  echo "   et l'appliquer sur la version actuelle de main — jamais l'inverse."
fi
echo ""
echo "--- Limite connue de ce script ---"
echo "La détection de \"stale revert\" ne fonctionne que si le contenu périmé a"
echo "existé un jour comme commit sur main. Si un correctif a été écrit"
echo "directement dans la version finale (sans jamais committer la version"
echo "cassée que Rocket avait livrée), un revert vers cette version cassée"
echo "apparaîtra ici comme \"NOUVEAU/MODIFIÉ\" et nécessite une revue manuelle"
echo "du contenu — ce script réduit le travail répétitif, il ne le remplace pas."
