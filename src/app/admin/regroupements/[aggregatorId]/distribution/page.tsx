'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { useParams } from 'next/navigation';
import Link from 'next/link';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

// ============================================================================
// /admin/regroupements/[aggregatorId]/distribution
// ----------------------------------------------------------------------------
// Lot 2 — Gouvernance des règles de distribution et des overrides membres.
// Périmètre : distribution_rules / distribution_rule_proposals (double
// approbation : primary_admin du regroupement + operator_admin de
// l'opérateur METALTRACE actif) et member_distribution_overrides /
// member_distribution_override_proposals (triple approbation : organization_
// admin de l'organisation membre + primary_admin du regroupement +
// operator_admin). Toute l'autorité métier reste côté PostgreSQL (RPC,
// migration 09) : cette page ne fait que lire l'état et déclencher les RPC.
// Aucune condition d'autorisation n'est recalculée côté client à des fins
// métier — les flags de rôle ci-dessous ne servent qu'à l'affichage des
// boutons (UX guard). Le serveur revalide systématiquement.
//
// Machine à états reflétée ici (source : signatures RPC réelles, migration
// 09, auditées en base le 31 juillet 2026) :
//
//   distribution_rule_proposals.status :
//     pending -> activated   (carbon_try_activate_distribution_rule_proposal,
//                              déclenché automatiquement après la 2e des 2
//                              approbations : aggregator_admin_approved_by ET
//                              operator_admin_approved_by non nuls)
//     pending -> rejected    (reject_distribution_rule_proposal, raison
//                              obligatoire, par tout rôle approbateur éligible)
//     pending -> withdrawn   (withdraw_distribution_rule_proposal, par
//                              proposed_by uniquement)
//
//   member_distribution_override_proposals.status :
//     pending -> activated   (carbon_try_activate_member_distribution_override_
//                              proposal, après les 3 approbations :
//                              organization_admin + aggregator_admin +
//                              operator_admin)
//     pending -> rejected    (reject_member_distribution_override_proposal)
//     pending -> withdrawn   (withdraw_member_distribution_override_proposal)
//   proposal_type ∈ {create, replace, revoke} — replace/revoke exigent
//   target_override_id (revalidé sous verrou à l'activation, TOCTOU géré
//   côté serveur).
// ============================================================================

interface Aggregator {
  id: string;
  name: string;
}

interface DistributionRule {
  id: string;
  platform_fee_pct: number;
  reserve_pct: number;
  default_weight: number;
  effective_from: string;
  effective_to: string | null;
  proposal_id: string;
  created_at: string;
  created_by: string;
}

interface DistributionRuleProposal {
  id: string;
  platform_fee_pct: number;
  reserve_pct: number;
  default_weight: number;
  status: string;
  proposed_by: string;
  proposed_at: string;
  aggregator_admin_approved_by: string | null;
  aggregator_admin_approved_at: string | null;
  operator_admin_approved_by: string | null;
  operator_admin_approved_at: string | null;
  activated_distribution_rule_id: string | null;
  rejected_by: string | null;
  rejected_at: string | null;
  reject_reason: string | null;
}

interface Membership {
  id: string;
  organization_id: string;
  organization_name: string;
  started_at: string;
  ended_at: string | null;
}

interface MemberOverride {
  id: string;
  aggregator_membership_id: string;
  override_type: string;
  override_value: number;
  effective_from: string;
  effective_until: string;
  created_at: string;
  revoked_at: string | null;
}

interface MemberOverrideProposal {
  id: string;
  proposal_type: 'create' | 'replace' | 'revoke';
  aggregator_membership_id: string;
  target_override_id: string | null;
  override_type: string | null;
  override_value: number | null;
  proposed_effective_from: string | null;
  proposed_effective_until: string | null;
  revoke_reason: string | null;
  status: string;
  proposed_by: string;
  proposed_at: string;
  organization_admin_approved_by: string | null;
  organization_admin_approved_at: string | null;
  aggregator_admin_approved_by: string | null;
  aggregator_admin_approved_at: string | null;
  operator_admin_approved_by: string | null;
  operator_admin_approved_at: string | null;
  activated_override_id: string | null;
  rejected_by: string | null;
  rejected_at: string | null;
  reject_reason: string | null;
}

// ----------------------------------------------------------------------------
// Helpers (repris du style établi Lot 1 : Badge, ErrorBanner, fmtNum,
// fmtDate/fmtDateTime, getErrorMessage — cf. admin/carbon-inventory/page.tsx)
// ----------------------------------------------------------------------------

const OVERRIDE_TYPE_LABELS: Record<string, string> = {
  fee_pct: 'Frais plateforme (%)',
  reserve_pct: 'Réserve (%)',
  weight_multiplier: 'Multiplicateur de pondération',
};

const PROPOSAL_STATUS_CONFIG: Record<string, { label: string; color: string; icon: string }> = {
  pending:   { label: 'En attente',  color: 'text-amber-700 bg-amber-50 border-amber-200', icon: 'ClockIcon' },
  activated: { label: 'Activée',     color: 'text-green-700 bg-green-50 border-green-200', icon: 'CheckBadgeIcon' },
  rejected:  { label: 'Rejetée',     color: 'text-red-700 bg-red-50 border-red-200',        icon: 'XCircleIcon' },
  withdrawn: { label: 'Retirée',     color: 'text-gray-700 bg-gray-100 border-gray-300',    icon: 'ArrowUturnLeftIcon' },
};

const PROPOSAL_TYPE_LABELS: Record<string, string> = {
  create: 'Création',
  replace: 'Remplacement',
  revoke: 'Révocation',
};

function StatusBadge({ status }: { status: string }) {
  const cfg = PROPOSAL_STATUS_CONFIG[status] ?? { label: status, color: 'text-gray-700 bg-gray-100 border-gray-300', icon: 'QuestionMarkCircleIcon' };
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-600 border ${cfg.color}`}>
      <Icon name={cfg.icon} size={12} />
      {cfg.label}
    </span>
  );
}

function ErrorBanner({ message }: { message: string | null }) {
  if (!message) return null;
  return <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700 mb-4">{message}</div>;
}

function fmtNum(n: number | null | undefined, digits = 4): string {
  if (n === null || n === undefined) return '—';
  return Number(n).toLocaleString('fr-CA', { maximumFractionDigits: digits, minimumFractionDigits: 0 });
}

function fmtDate(s: string | null | undefined): string {
  if (!s) return '—';
  // Colonnes `date` pures (effective_from/until, proposed_effective_*) :
  // même correctif que Lot 1 (fmtDate) — construire la date en LOCAL plutôt
  // que de laisser new Date(str) l'interpréter en UTC minuit, ce qui décale
  // d'un jour en arrière au Québec (UTC-4/-5).
  const dateOnly = /^\d{4}-\d{2}-\d{2}$/.exec(s);
  if (dateOnly) {
    const [y, m, d] = s.split('-').map(Number);
    return new Date(y, m - 1, d).toLocaleDateString('fr-CA');
  }
  return new Date(s).toLocaleDateString('fr-CA');
}

function fmtDateTime(s: string | null | undefined): string {
  if (!s) return '—';
  return new Date(s).toLocaleString('fr-CA');
}

function getErrorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err) return String((err as { message: unknown }).message);
  return 'Erreur inconnue.';
}

// ----------------------------------------------------------------------------
// Modale : proposer une nouvelle règle de distribution
// (propose_distribution_rule — pas de date d'entrée en vigueur : effective_from
// est généré par le serveur à l'activation, jamais fourni par le client)
// ----------------------------------------------------------------------------

function ProposeRuleModal({
  aggregatorId, onClose, onCreated,
}: { aggregatorId: string; onClose: () => void; onCreated: () => void }) {
  const [feePct, setFeePct] = useState('');
  const [reservePct, setReservePct] = useState('');
  const [defaultWeight, setDefaultWeight] = useState('1');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    const fee = parseFloat(feePct);
    const reserve = parseFloat(reservePct);
    const weight = parseFloat(defaultWeight);
    if (Number.isNaN(fee) || Number.isNaN(reserve) || Number.isNaN(weight)) {
      setError('Valeurs numériques requises.');
      return;
    }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('propose_distribution_rule', {
      p_aggregator_id: aggregatorId,
      p_platform_fee_pct: fee,
      p_reserve_pct: reserve,
      p_default_weight: weight,
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onCreated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">Proposer une règle de distribution</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <p className="text-xs text-muted-foreground">
            La date d&apos;entrée en vigueur n&apos;est pas saisissable ici : le serveur la fixe automatiquement à l&apos;instant de la double approbation.
          </p>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Frais plateforme (%)</label>
            <input type="number" step="0.01" min="0" max="100" className="input w-full" value={feePct} onChange={(e) => setFeePct(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Réserve (%)</label>
            <input type="number" step="0.01" min="0" max="100" className="input w-full" value={reservePct} onChange={(e) => setReservePct(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Pondération par défaut</label>
            <input type="number" step="0.01" min="0.01" className="input w-full" value={defaultWeight} onChange={(e) => setDefaultWeight(e.target.value)} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Envoi...' : 'Proposer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale : proposer un override membre (create / replace / revoke)
// ----------------------------------------------------------------------------

function ProposeOverrideModal({
  membership, activeOverrides, onClose, onCreated,
}: {
  membership: Membership;
  activeOverrides: MemberOverride[];
  onClose: () => void;
  onCreated: () => void;
}) {
  const [proposalType, setProposalType] = useState<'create' | 'replace' | 'revoke'>('create');
  const [targetOverrideId, setTargetOverrideId] = useState('');
  const [overrideType, setOverrideType] = useState('fee_pct');
  const [overrideValue, setOverrideValue] = useState('');
  const [effectiveFrom, setEffectiveFrom] = useState('');
  const [effectiveUntil, setEffectiveUntil] = useState('');
  const [revokeReason, setRevokeReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const needsTarget = proposalType === 'replace' || proposalType === 'revoke';
  const needsValueFields = proposalType === 'create' || proposalType === 'replace';

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (needsTarget && !targetOverrideId) { setError('Sélectionner l’override ciblé.'); return; }
    if (needsValueFields) {
      const v = parseFloat(overrideValue);
      if (Number.isNaN(v)) { setError('Valeur numérique requise.'); return; }
      if (!effectiveFrom || !effectiveUntil) { setError('Dates de validité requises.'); return; }
    }
    if (proposalType === 'revoke' && !revokeReason.trim()) { setError('Motif de révocation requis.'); return; }

    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('propose_member_distribution_override', {
      p_proposal_type: proposalType,
      p_aggregator_membership_id: membership.id,
      p_target_override_id: needsTarget ? targetOverrideId : null,
      p_override_type: needsValueFields ? overrideType : null,
      p_override_value: needsValueFields ? parseFloat(overrideValue) : null,
      p_effective_from: needsValueFields ? effectiveFrom : null,
      p_effective_until: needsValueFields ? effectiveUntil : null,
      p_revoke_reason: proposalType === 'revoke' ? revokeReason.trim() : null,
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onCreated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card">
          <h2 className="text-lg font-700 text-foreground">Proposer un override — {membership.organization_name}</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Type de proposition</label>
            <select className="input w-full" value={proposalType} onChange={(e) => setProposalType(e.target.value as 'create' | 'replace' | 'revoke')}>
              <option value="create">Création — nouvel override</option>
              <option value="replace">Remplacement d&apos;un override actif</option>
              <option value="revoke">Révocation d&apos;un override actif</option>
            </select>
          </div>

          {needsTarget && (
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Override ciblé (actif)</label>
              <select className="input w-full" value={targetOverrideId} onChange={(e) => setTargetOverrideId(e.target.value)}>
                <option value="">— Choisir —</option>
                {activeOverrides.map((o) => (
                  <option key={o.id} value={o.id}>
                    {OVERRIDE_TYPE_LABELS[o.override_type] ?? o.override_type} = {fmtNum(o.override_value, 2)} ({fmtDate(o.effective_from)} → {fmtDate(o.effective_until)})
                  </option>
                ))}
              </select>
              {activeOverrides.length === 0 && (
                <p className="text-xs text-muted-foreground mt-1">Aucun override actif pour cette adhésion.</p>
              )}
            </div>
          )}

          {needsValueFields && (
            <>
              <div>
                <label className="block text-sm font-600 text-foreground mb-1">Type d&apos;override</label>
                <select className="input w-full" value={overrideType} onChange={(e) => setOverrideType(e.target.value)}>
                  {Object.entries(OVERRIDE_TYPE_LABELS).map(([code, label]) => (
                    <option key={code} value={code}>{label}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-600 text-foreground mb-1">Valeur</label>
                <input type="number" step="0.0001" className="input w-full" value={overrideValue} onChange={(e) => setOverrideValue(e.target.value)} />
                <p className="text-xs text-muted-foreground mt-1">
                  fee_pct / reserve_pct : 0–100. weight_multiplier : &gt; 0.
                </p>
              </div>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm font-600 text-foreground mb-1">Effectif à partir du</label>
                  <input type="date" className="input w-full" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} />
                </div>
                <div>
                  <label className="block text-sm font-600 text-foreground mb-1">Effectif jusqu&apos;au</label>
                  <input type="date" className="input w-full" value={effectiveUntil} onChange={(e) => setEffectiveUntil(e.target.value)} />
                </div>
              </div>
            </>
          )}

          {proposalType === 'revoke' && (
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Motif de révocation</label>
              <textarea className="input w-full h-20 resize-none" value={revokeReason} onChange={(e) => setRevokeReason(e.target.value)} />
            </div>
          )}

          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Envoi...' : 'Proposer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale générique : rejet (raison obligatoire, all-or-none côté serveur)
// ----------------------------------------------------------------------------

function RejectModal({
  title, onClose, onConfirm,
}: { title: string; onClose: () => void; onConfirm: (reason: string) => Promise<void> }) {
  const [reason, setReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!reason.trim()) { setError('Motif requis.'); return; }
    setSaving(true);
    try {
      await onConfirm(reason.trim());
      onClose();
    } catch (err) {
      setError(getErrorMessage(err));
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-sm">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">{title}</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Motif du rejet</label>
            <textarea className="input w-full h-20 resize-none" value={reason} onChange={(e) => setReason(e.target.value)} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="bg-red-600 hover:bg-red-700 text-white flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Envoi...' : 'Rejeter'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Page
// ----------------------------------------------------------------------------

export default function DistributionGovernancePage() {
  const params = useParams();
  const aggregatorId = params.aggregatorId as string;

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const [aggregator, setAggregator] = useState<Aggregator | null>(null);
  const [activeRule, setActiveRule] = useState<DistributionRule | null>(null);
  const [ruleHistory, setRuleHistory] = useState<DistributionRule[]>([]);
  const [ruleProposals, setRuleProposals] = useState<DistributionRuleProposal[]>([]);
  const [memberships, setMemberships] = useState<Membership[]>([]);
  const [overrides, setOverrides] = useState<MemberOverride[]>([]);
  const [overrideProposals, setOverrideProposals] = useState<MemberOverrideProposal[]>([]);
  const [profileNames, setProfileNames] = useState<Map<string, string>>(new Map());

  // ── Rôle courant (UX guard uniquement — le serveur revalide) ────────────────
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [isSuperadmin, setIsSuperadmin] = useState(false);
  const [isAggregatorPrimaryAdmin, setIsAggregatorPrimaryAdmin] = useState(false);
  const [isOperatorAdmin, setIsOperatorAdmin] = useState(false);
  const [orgAdminOrgIds, setOrgAdminOrgIds] = useState<Set<string>>(new Set());

  const [showProposeRule, setShowProposeRule] = useState(false);
  const [proposeOverrideFor, setProposeOverrideFor] = useState<Membership | null>(null);
  const [rejectTarget, setRejectTarget] = useState<
    { kind: 'rule' | 'override'; id: string } | null
  >(null);
  const [actionError, setActionError] = useState('');

  const resolveName = useCallback(
    (id: string | null): string => {
      if (!id) return '—';
      return profileNames.get(id) ?? `${id.slice(0, 8)}…`;
    },
    [profileNames]
  );

  // ── Détection de rôle ────────────────────────────────────────────────────────
  useEffect(() => {
    if (!aggregatorId) return;
    (async () => {
      const supabase = createClient();
      const { data: { session } } = await supabase.auth.getSession();
      const uid = session?.user?.id ?? null;
      setCurrentUserId(uid);
      const role = session?.user?.app_metadata?.role;
      const superadmin = role === 'admin';
      setIsSuperadmin(superadmin);
      if (!uid) return;

      const [aaRes, opRes, omRes] = await Promise.all([
        supabase
          .from('aggregator_admins')
          .select('id')
          .eq('aggregator_id', aggregatorId)
          .eq('user_id', uid)
          .eq('role', 'primary_admin')
          .is('revoked_at', null)
          .maybeSingle(),
        supabase.from('platform_operators').select('organization_id').is('revoked_at', null).maybeSingle(),
        supabase.from('organization_members').select('organization_id').eq('user_id', uid).eq('org_role', 'admin').eq('status', 'active'),
      ]);
      setIsAggregatorPrimaryAdmin(!!aaRes.data);
      setOrgAdminOrgIds(new Set((omRes.data ?? []).map((r: { organization_id: string }) => r.organization_id)));

      const operatorOrgId = opRes.data?.organization_id ?? null;
      if (operatorOrgId) {
        const { data: opAdmin } = await supabase
          .from('organization_members')
          .select('id')
          .eq('organization_id', operatorOrgId)
          .eq('user_id', uid)
          .eq('org_role', 'admin')
          .eq('status', 'active')
          .maybeSingle();
        setIsOperatorAdmin(!!opAdmin || superadmin);
      } else {
        setIsOperatorAdmin(superadmin);
      }
    })();
  }, [aggregatorId]);

  // ── Chargement des données ───────────────────────────────────────────────────
  const fetchAll = useCallback(async () => {
    if (!aggregatorId) return;
    setLoading(true);
    setError('');
    const supabase = createClient();

    const [aggRes, rulesRes, ruleProposalsRes, membershipsRes] = await Promise.all([
      supabase.from('aggregators').select('id, name').eq('id', aggregatorId).maybeSingle(),
      supabase.from('distribution_rules').select('*').eq('aggregator_id', aggregatorId).order('effective_from', { ascending: false }),
      supabase.from('distribution_rule_proposals').select('*').eq('aggregator_id', aggregatorId).order('proposed_at', { ascending: false }),
      supabase
        .from('aggregator_memberships')
        .select('id, organization_id, started_at, ended_at, organizations(name)')
        .eq('aggregator_id', aggregatorId)
        .order('started_at', { ascending: true }),
    ]);

    const firstErrors = [aggRes.error, rulesRes.error, ruleProposalsRes.error, membershipsRes.error].filter(Boolean);
    if (firstErrors.length > 0) {
      setError(firstErrors.map((e) => getErrorMessage(e)).join(' · '));
      setLoading(false);
      return;
    }

    setAggregator((aggRes.data as Aggregator) ?? null);
    const rules = (rulesRes.data as DistributionRule[]) ?? [];
    setActiveRule(rules.find((r) => r.effective_to === null) ?? null);
    setRuleHistory(rules.filter((r) => r.effective_to !== null));
    setRuleProposals((ruleProposalsRes.data as DistributionRuleProposal[]) ?? []);

    const mems: Membership[] = ((membershipsRes.data ?? []) as unknown as {
      id: string; organization_id: string; started_at: string; ended_at: string | null;
      organizations: { name: string } | null;
    }[]).map((m) => ({
      id: m.id,
      organization_id: m.organization_id,
      organization_name: m.organizations?.name ?? m.organization_id,
      started_at: m.started_at,
      ended_at: m.ended_at,
    }));
    setMemberships(mems);

    const membershipIds = mems.map((m) => m.id);
    let overridesData: MemberOverride[] = [];
    let overrideProposalsData: MemberOverrideProposal[] = [];
    if (membershipIds.length > 0) {
      const [ovRes, ovPropRes] = await Promise.all([
        supabase.from('member_distribution_overrides').select('*').in('aggregator_membership_id', membershipIds),
        supabase.from('member_distribution_override_proposals').select('*').in('aggregator_membership_id', membershipIds).order('proposed_at', { ascending: false }),
      ]);
      const secondErrors = [ovRes.error, ovPropRes.error].filter(Boolean);
      if (secondErrors.length > 0) {
        setError(secondErrors.map((e) => getErrorMessage(e)).join(' · '));
        setLoading(false);
        return;
      }
      overridesData = (ovRes.data as MemberOverride[]) ?? [];
      overrideProposalsData = (ovPropRes.data as MemberOverrideProposal[]) ?? [];
    }
    setOverrides(overridesData);
    setOverrideProposals(overrideProposalsData);

    // Résolution des noms d'acteurs (proposé par / approuvé par / rejeté par)
    const actorIds = new Set<string>();
    rules.forEach((r) => actorIds.add(r.created_by));
    (ruleProposalsRes.data as DistributionRuleProposal[] ?? []).forEach((p) => {
      actorIds.add(p.proposed_by);
      if (p.aggregator_admin_approved_by) actorIds.add(p.aggregator_admin_approved_by);
      if (p.operator_admin_approved_by) actorIds.add(p.operator_admin_approved_by);
      if (p.rejected_by) actorIds.add(p.rejected_by);
    });
    overrideProposalsData.forEach((p) => {
      actorIds.add(p.proposed_by);
      if (p.organization_admin_approved_by) actorIds.add(p.organization_admin_approved_by);
      if (p.aggregator_admin_approved_by) actorIds.add(p.aggregator_admin_approved_by);
      if (p.operator_admin_approved_by) actorIds.add(p.operator_admin_approved_by);
      if (p.rejected_by) actorIds.add(p.rejected_by);
    });
    const idList = [...actorIds].filter(Boolean);
    if (idList.length > 0) {
      const { data: profilesData } = await supabase.from('profiles').select('id, full_name, email').in('id', idList);
      const map = new Map<string, string>();
      ((profilesData ?? []) as { id: string; full_name: string | null; email: string }[]).forEach((p) => {
        map.set(p.id, p.full_name || p.email || p.id);
      });
      setProfileNames(map);
    }

    setLoading(false);
  }, [aggregatorId]);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  // ── Actions règle de distribution ───────────────────────────────────────────
  const runRuleAction = async (fn: string, proposalId: string, extra?: Record<string, unknown>) => {
    setActionError('');
    const supabase = createClient();
    const { error: err } = await supabase.rpc(fn, { p_proposal_id: proposalId, ...(extra ?? {}) });
    if (err) { setActionError(getErrorMessage(err)); return; }
    fetchAll();
  };

  // ── Actions overrides membres ───────────────────────────────────────────────
  const runOverrideAction = async (fn: string, proposalId: string, extra?: Record<string, unknown>) => {
    setActionError('');
    const supabase = createClient();
    const { error: err } = await supabase.rpc(fn, { p_proposal_id: proposalId, ...(extra ?? {}) });
    if (err) { setActionError(getErrorMessage(err)); return; }
    fetchAll();
  };

  const canProposeRule = isAggregatorPrimaryAdmin || isOperatorAdmin || isSuperadmin;

  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="flex flex-col items-center gap-3">
          <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
          <p className="text-sm text-muted-foreground">Chargement…</p>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8 space-y-8">

        {/* Header */}
        <div>
          <Link href="/admin" className="text-xs text-muted-foreground hover:text-primary inline-flex items-center gap-1 mb-2">
            <Icon name="ChevronLeftIcon" size={12} /> Administration
          </Link>
          <h1 className="text-2xl font-700 text-foreground">Gouvernance de distribution</h1>
          <p className="text-sm text-muted-foreground mt-1">
            {aggregator ? aggregator.name : aggregatorId} — règles de distribution et overrides membres
          </p>
        </div>

        <ErrorBanner message={error} />
        <ErrorBanner message={actionError} />

        {/* ── Règle de distribution ────────────────────────────────────────── */}
        <section>
          <div className="flex items-center justify-between mb-4">
            <div>
              <h2 className="text-base font-700 text-foreground">Règle de distribution</h2>
              <p className="text-sm text-muted-foreground mt-0.5">Double approbation : primary_admin du regroupement + operator_admin METALTRACE</p>
            </div>
            {canProposeRule && (
              <button onClick={() => setShowProposeRule(true)} className="btn-primary flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600">
                <Icon name="PlusCircleIcon" size={16} />
                Proposer une règle
              </button>
            )}
          </div>

          {/* Règle active */}
          {activeRule ? (
            <div className="bg-card border border-border rounded-xl p-5 mb-4">
              <div className="flex items-center gap-2 mb-3">
                <Icon name="CheckBadgeIcon" size={16} className="text-green-600" />
                <p className="text-sm font-700 text-foreground">Règle active</p>
              </div>
              <div className="grid grid-cols-3 gap-4 text-sm">
                <div>
                  <p className="text-xs text-muted-foreground">Frais plateforme</p>
                  <p className="font-600 text-foreground">{fmtNum(activeRule.platform_fee_pct, 2)}%</p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Réserve</p>
                  <p className="font-600 text-foreground">{fmtNum(activeRule.reserve_pct, 2)}%</p>
                </div>
                <div>
                  <p className="text-xs text-muted-foreground">Pondération par défaut</p>
                  <p className="font-600 text-foreground">{fmtNum(activeRule.default_weight, 2)}</p>
                </div>
              </div>
              <p className="text-xs text-muted-foreground mt-3">Effective depuis le {fmtDateTime(activeRule.effective_from)}</p>
            </div>
          ) : (
            <div className="bg-muted rounded-lg p-4 text-sm text-muted-foreground mb-4">Aucune règle de distribution active pour ce regroupement.</div>
          )}

          {/* Propositions en attente */}
          {ruleProposals.filter((p) => p.status === 'pending').map((p) => (
            <div key={p.id} className="bg-card border border-amber-200 rounded-xl p-5 mb-3">
              <div className="flex items-start justify-between gap-3 mb-3">
                <div>
                  <StatusBadge status={p.status} />
                  <p className="text-xs text-muted-foreground mt-1">Proposée par {resolveName(p.proposed_by)} le {fmtDateTime(p.proposed_at)}</p>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-4 text-sm mb-3">
                <div><p className="text-xs text-muted-foreground">Frais plateforme</p><p className="font-600 text-foreground">{fmtNum(p.platform_fee_pct, 2)}%</p></div>
                <div><p className="text-xs text-muted-foreground">Réserve</p><p className="font-600 text-foreground">{fmtNum(p.reserve_pct, 2)}%</p></div>
                <div><p className="text-xs text-muted-foreground">Pondération</p><p className="font-600 text-foreground">{fmtNum(p.default_weight, 2)}</p></div>
              </div>
              <div className="flex flex-wrap gap-2 text-xs text-muted-foreground mb-3">
                <span className={p.aggregator_admin_approved_by ? 'text-green-700' : ''}>
                  Approbation regroupement : {p.aggregator_admin_approved_by ? `${resolveName(p.aggregator_admin_approved_by)} (${fmtDateTime(p.aggregator_admin_approved_at)})` : 'en attente'}
                </span>
                <span className="text-border">·</span>
                <span className={p.operator_admin_approved_by ? 'text-green-700' : ''}>
                  Approbation opérateur : {p.operator_admin_approved_by ? `${resolveName(p.operator_admin_approved_by)} (${fmtDateTime(p.operator_admin_approved_at)})` : 'en attente'}
                </span>
              </div>
              <div className="flex flex-wrap gap-2">
                {isAggregatorPrimaryAdmin && !p.aggregator_admin_approved_by && (
                  <button onClick={() => runRuleAction('approve_distribution_rule_as_aggregator_admin', p.id)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600">
                    Approuver (regroupement)
                  </button>
                )}
                {isOperatorAdmin && !p.operator_admin_approved_by && (
                  <button onClick={() => runRuleAction('approve_distribution_rule_as_operator_admin', p.id)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600">
                    Approuver (opérateur)
                  </button>
                )}
                {(isAggregatorPrimaryAdmin || isOperatorAdmin || isSuperadmin) && (
                  <button onClick={() => setRejectTarget({ kind: 'rule', id: p.id })} className="px-3 py-1.5 rounded-lg text-xs font-600 border border-red-200 text-red-700 hover:bg-red-50">
                    Rejeter
                  </button>
                )}
                {p.proposed_by === currentUserId && (
                  <button onClick={() => runRuleAction('withdraw_distribution_rule_proposal', p.id)} className="px-3 py-1.5 rounded-lg text-xs font-600 border border-border hover:bg-muted">
                    Retirer
                  </button>
                )}
              </div>
            </div>
          ))}

          {/* Historique propositions non pending + règles closes */}
          {(ruleProposals.filter((p) => p.status !== 'pending').length > 0 || ruleHistory.length > 0) && (
            <details className="mt-2">
              <summary className="text-sm text-muted-foreground cursor-pointer hover:text-foreground">Historique (règles closes et propositions traitées)</summary>
              <div className="mt-3 space-y-2">
                {ruleProposals.filter((p) => p.status !== 'pending').map((p) => (
                  <div key={p.id} className="bg-card border border-border rounded-lg p-3 text-xs">
                    <div className="flex items-center gap-2 mb-1"><StatusBadge status={p.status} /><span className="text-muted-foreground">proposée par {resolveName(p.proposed_by)} le {fmtDateTime(p.proposed_at)}</span></div>
                    <p className="text-muted-foreground">
                      Frais {fmtNum(p.platform_fee_pct, 2)}% · Réserve {fmtNum(p.reserve_pct, 2)}% · Pondération {fmtNum(p.default_weight, 2)}
                      {p.status === 'rejected' && p.reject_reason && ` · Motif : ${p.reject_reason}`}
                    </p>
                  </div>
                ))}
                {ruleHistory.map((r) => (
                  <div key={r.id} className="bg-muted rounded-lg p-3 text-xs text-muted-foreground">
                    Frais {fmtNum(r.platform_fee_pct, 2)}% · Réserve {fmtNum(r.reserve_pct, 2)}% · Pondération {fmtNum(r.default_weight, 2)}
                    {' · '}{fmtDateTime(r.effective_from)} → {fmtDateTime(r.effective_to)}
                  </div>
                ))}
              </div>
            </details>
          )}
        </section>

        {/* ── Overrides membres ────────────────────────────────────────────── */}
        <section>
          <div className="mb-4">
            <h2 className="text-base font-700 text-foreground">Overrides membres</h2>
            <p className="text-sm text-muted-foreground mt-0.5">Triple approbation : organization_admin de l&apos;organisation membre + primary_admin du regroupement + operator_admin</p>
          </div>

          {memberships.length === 0 ? (
            <div className="bg-muted rounded-lg p-4 text-sm text-muted-foreground">Aucune adhésion pour ce regroupement.</div>
          ) : (
            <div className="space-y-4">
              {memberships.map((m) => {
                const activeOverridesForM = overrides.filter((o) => o.aggregator_membership_id === m.id && !o.revoked_at);
                const closedOverridesForM = overrides.filter((o) => o.aggregator_membership_id === m.id && o.revoked_at);
                const proposalsForM = overrideProposals.filter((p) => p.aggregator_membership_id === m.id);
                const pendingForM = proposalsForM.filter((p) => p.status === 'pending');
                const historyForM = proposalsForM.filter((p) => p.status !== 'pending');
                const canProposeForM = orgAdminOrgIds.has(m.organization_id) || isAggregatorPrimaryAdmin || isOperatorAdmin || isSuperadmin;

                return (
                  <div key={m.id} className="bg-card border border-border rounded-xl p-5">
                    <div className="flex items-center justify-between gap-3 mb-3">
                      <div>
                        <p className="text-sm font-700 text-foreground">{m.organization_name}</p>
                        <p className="text-xs text-muted-foreground">
                          Membre depuis {fmtDateTime(m.started_at)}{m.ended_at ? ` · terminé le ${fmtDateTime(m.ended_at)}` : ''}
                        </p>
                      </div>
                      {canProposeForM && (
                        <button onClick={() => setProposeOverrideFor(m)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600 flex items-center gap-1.5">
                          <Icon name="PlusCircleIcon" size={14} />
                          Proposer un override
                        </button>
                      )}
                    </div>

                    {activeOverridesForM.length > 0 ? (
                      <div className="space-y-1.5 mb-3">
                        {activeOverridesForM.map((o) => (
                          <div key={o.id} className="flex items-center gap-2 text-sm bg-muted rounded-lg px-3 py-2">
                            <Icon name="AdjustmentsHorizontalIcon" size={14} className="text-muted-foreground" />
                            <span className="text-foreground font-600">{OVERRIDE_TYPE_LABELS[o.override_type] ?? o.override_type} = {fmtNum(o.override_value, 2)}</span>
                            <span className="text-xs text-muted-foreground">({fmtDate(o.effective_from)} → {fmtDate(o.effective_until)})</span>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="text-xs text-muted-foreground mb-3">Aucun override actif.</p>
                    )}

                    {pendingForM.map((p) => (
                      <div key={p.id} className="bg-amber-50/50 border border-amber-200 rounded-lg p-3 mb-2">
                        <div className="flex items-center gap-2 mb-2">
                          <StatusBadge status={p.status} />
                          <span className="text-xs font-600 text-foreground">{PROPOSAL_TYPE_LABELS[p.proposal_type]}</span>
                          <span className="text-xs text-muted-foreground">proposée par {resolveName(p.proposed_by)} le {fmtDateTime(p.proposed_at)}</span>
                        </div>
                        {p.proposal_type !== 'revoke' && (
                          <p className="text-xs text-muted-foreground mb-2">
                            {OVERRIDE_TYPE_LABELS[p.override_type ?? ''] ?? p.override_type} = {fmtNum(p.override_value, 2)}
                            {' · '}{fmtDate(p.proposed_effective_from)} → {fmtDate(p.proposed_effective_until)}
                          </p>
                        )}
                        {p.proposal_type === 'revoke' && p.revoke_reason && (
                          <p className="text-xs text-muted-foreground mb-2">Motif : {p.revoke_reason}</p>
                        )}
                        <div className="flex flex-wrap gap-2 text-xs text-muted-foreground mb-2">
                          <span className={p.organization_admin_approved_by ? 'text-green-700' : ''}>
                            Org. membre : {p.organization_admin_approved_by ? resolveName(p.organization_admin_approved_by) : 'en attente'}
                          </span>
                          <span className="text-border">·</span>
                          <span className={p.aggregator_admin_approved_by ? 'text-green-700' : ''}>
                            Regroupement : {p.aggregator_admin_approved_by ? resolveName(p.aggregator_admin_approved_by) : 'en attente'}
                          </span>
                          <span className="text-border">·</span>
                          <span className={p.operator_admin_approved_by ? 'text-green-700' : ''}>
                            Opérateur : {p.operator_admin_approved_by ? resolveName(p.operator_admin_approved_by) : 'en attente'}
                          </span>
                        </div>
                        <div className="flex flex-wrap gap-2">
                          {orgAdminOrgIds.has(m.organization_id) && !p.organization_admin_approved_by && (
                            <button onClick={() => runOverrideAction('approve_member_distribution_override_as_organization_admin', p.id)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600">
                              Approuver (org. membre)
                            </button>
                          )}
                          {isAggregatorPrimaryAdmin && !p.aggregator_admin_approved_by && (
                            <button onClick={() => runOverrideAction('approve_member_distribution_override_as_aggregator_admin', p.id)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600">
                              Approuver (regroupement)
                            </button>
                          )}
                          {isOperatorAdmin && !p.operator_admin_approved_by && (
                            <button onClick={() => runOverrideAction('approve_member_distribution_override_as_operator_admin', p.id)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600">
                              Approuver (opérateur)
                            </button>
                          )}
                          {(orgAdminOrgIds.has(m.organization_id) || isAggregatorPrimaryAdmin || isOperatorAdmin || isSuperadmin) && (
                            <button onClick={() => setRejectTarget({ kind: 'override', id: p.id })} className="px-3 py-1.5 rounded-lg text-xs font-600 border border-red-200 text-red-700 hover:bg-red-50">
                              Rejeter
                            </button>
                          )}
                          {p.proposed_by === currentUserId && (
                            <button onClick={() => runOverrideAction('withdraw_member_distribution_override_proposal', p.id)} className="px-3 py-1.5 rounded-lg text-xs font-600 border border-border hover:bg-muted">
                              Retirer
                            </button>
                          )}
                        </div>
                      </div>
                    ))}

                    {(historyForM.length > 0 || closedOverridesForM.length > 0) && (
                      <details className="mt-2">
                        <summary className="text-xs text-muted-foreground cursor-pointer hover:text-foreground">Historique</summary>
                        <div className="mt-2 space-y-1.5">
                          {historyForM.map((p) => (
                            <div key={p.id} className="text-xs bg-muted rounded-lg px-3 py-2">
                              <div className="flex items-center gap-2 mb-0.5"><StatusBadge status={p.status} /><span className="text-muted-foreground">{PROPOSAL_TYPE_LABELS[p.proposal_type]} · {resolveName(p.proposed_by)} · {fmtDateTime(p.proposed_at)}</span></div>
                              {p.status === 'rejected' && p.reject_reason && <p className="text-muted-foreground">Motif : {p.reject_reason}</p>}
                            </div>
                          ))}
                          {closedOverridesForM.map((o) => (
                            <div key={o.id} className="text-xs bg-muted rounded-lg px-3 py-2 text-muted-foreground">
                              {OVERRIDE_TYPE_LABELS[o.override_type] ?? o.override_type} = {fmtNum(o.override_value, 2)} — révoqué le {fmtDateTime(o.revoked_at)}
                            </div>
                          ))}
                        </div>
                      </details>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </section>
      </div>

      {showProposeRule && (
        <ProposeRuleModal aggregatorId={aggregatorId} onClose={() => setShowProposeRule(false)} onCreated={fetchAll} />
      )}
      {proposeOverrideFor && (
        <ProposeOverrideModal
          membership={proposeOverrideFor}
          activeOverrides={overrides.filter((o) => o.aggregator_membership_id === proposeOverrideFor.id && !o.revoked_at)}
          onClose={() => setProposeOverrideFor(null)}
          onCreated={fetchAll}
        />
      )}
      {rejectTarget && (
        <RejectModal
          title={rejectTarget.kind === 'rule' ? 'Rejeter la proposition de règle' : "Rejeter la proposition d'override"}
          onClose={() => setRejectTarget(null)}
          onConfirm={async (reason) => {
            const supabase = createClient();
            const fn = rejectTarget.kind === 'rule' ? 'reject_distribution_rule_proposal' : 'reject_member_distribution_override_proposal';
            const { error: err } = await supabase.rpc(fn, { p_proposal_id: rejectTarget.id, p_reason: reason });
            if (err) throw err;
            fetchAll();
          }}
        />
      )}
    </div>
  );
}
