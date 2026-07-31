'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

// ============================================================================
// /admin/carbon-inventory
// ----------------------------------------------------------------------------
// Vertical slice « Cockpit opérateur — Émissions, lots et inventaire ».
// Périmètre : verification_outcomes (lecture) -> credit_issuances -> credit_lots.
// Toute l'autorité métier reste côté PostgreSQL (RPC) : cette page ne fait
// que lire l'état et déclencher les RPC. Aucun calcul de statut, de
// transition ou de capacité n'est recalculé côté client.
//
// Machine à états reflétée ici (source : définitions réelles des triggers/RPC
// de production, migrations 07/08 — carbon_credit_issuances_before_update,
// carbon_credit_lots_before_update, et les fonctions RPC elles-mêmes) :
//
//   Émission (credit_issuances.issuance_status) :
//     internal   -> eligible              (mark_credit_issuance_eligible)
//     internal   -> voided                (void_credit_issuance)
//     eligible   -> submitted             (submit_credit_issuance)
//     eligible   -> voided                (void_credit_issuance)
//     submitted  -> issued                (record_registry_issuance)
//     submitted  -> externally_rejected   (record_externally_rejected)
//     issued     -> externally_cancelled  (record_external_cancellation)
//   void_credit_issuance() est REFUSÉ depuis submitted/issued (le serveur
//   l'indique explicitement : utiliser record_externally_rejected()/
//   record_external_cancellation() à la place).
//
//   Lot (credit_lots.commercial_status) — uniquement ce qui relève de ce
//   module (hors cycle de vente, non construit ici) :
//     available -> voided   (void_credit_lot, void_cause=internal_correction,
//                             exige que l'émission parente soit encore issued)
//   reserved/sold/retired sont pilotés par le module Ventes (credit_sales /
//   credit_sale_lots, hors périmètre de ce lot) : aucune action n'est
//   proposée ici pour ces statuts.
// ============================================================================

type TabId = 'outcomes' | 'issuances' | 'lots';

interface VerificationOutcome {
  id: string;
  verification_session_id: string;
  status: string;
  calculated_reduction_tco2e: number;
  verified_reduction_tco2e: number;
  eligible_tco2e: number;
  verified_at: string;
  adjustment_reason: string | null;
  verification_sessions?: {
    project_id: string | null;
    reporting_period_start: string | null;
    reporting_period_end: string | null;
    projects?: { name: string } | null;
  } | null;
}

interface CreditIssuance {
  id: string;
  verification_outcome_id: string;
  aggregator_id: string;
  operator_organization_id: string;
  quantity_tco2e: number;
  issuance_status: string;
  registry_name: string | null;
  registry_reference: string | null;
  registry_issued_at: string | null;
  external_cancellation_date: string | null;
  external_cancellation_reference: string | null;
  external_rejection_date: string | null;
  external_rejection_reference: string | null;
  void_reason: string | null;
  created_at: string;
  aggregators?: { name: string } | null;
  operator?: { name: string } | null;
}

interface CreditIssuanceSource {
  id: string;
  organization_id: string;
  aggregator_membership_id: string;
  commercialization_mandate_id: string;
  contributed_tco2e: number;
  organizations?: { name: string } | null;
}

interface CreditLot {
  id: string;
  credit_issuance_id: string;
  aggregator_id: string;
  quantity_tco2e: number;
  vintage_year: number;
  commercial_status: string;
  void_cause: string | null;
  void_reason: string | null;
  created_at: string;
  aggregators?: { name: string } | null;
}

interface ActiveMembership {
  id: string; // aggregator_membership_id
  organization_id: string;
  aggregator_id: string;
  organization_name: string;
  aggregator_name: string;
}

interface ActiveMandate {
  id: string; // commercialization_mandate_id
  aggregator_membership_id: string;
  operator_organization_id: string;
  scope: string[];
}

interface DocumentOption {
  id: string;
  title: string;
  category: string | null;
}

// ----------------------------------------------------------------------------
// Libellés / badges
// ----------------------------------------------------------------------------

const ISSUANCE_STATUS_CONFIG: Record<string, { label: string; color: string; icon: string }> = {
  internal:              { label: 'Interne',            color: 'text-slate-700 bg-slate-50 border-slate-200',   icon: 'DocumentIcon' },
  eligible:              { label: 'Admissible',         color: 'text-blue-700 bg-blue-50 border-blue-200',      icon: 'CheckCircleIcon' },
  submitted:             { label: 'Soumise au registre', color: 'text-amber-700 bg-amber-50 border-amber-200',  icon: 'PaperAirplaneIcon' },
  issued:                { label: 'Émise (registre)',    color: 'text-green-700 bg-green-50 border-green-200',  icon: 'CheckBadgeIcon' },
  externally_cancelled:  { label: 'Annulée (externe)',   color: 'text-red-700 bg-red-50 border-red-200',        icon: 'XCircleIcon' },
  externally_rejected:   { label: 'Rejetée (externe)',   color: 'text-red-700 bg-red-50 border-red-200',        icon: 'NoSymbolIcon' },
  voided:                { label: 'Annulée',             color: 'text-gray-700 bg-gray-100 border-gray-300',    icon: 'TrashIcon' },
};

const LOT_STATUS_CONFIG: Record<string, { label: string; color: string; icon: string }> = {
  available: { label: 'Disponible', color: 'text-green-700 bg-green-50 border-green-200',  icon: 'CheckCircleIcon' },
  reserved:  { label: 'Réservé',    color: 'text-amber-700 bg-amber-50 border-amber-200',   icon: 'ClockIcon' },
  sold:      { label: 'Vendu',      color: 'text-blue-700 bg-blue-50 border-blue-200',      icon: 'BanknotesIcon' },
  retired:   { label: 'Retiré',     color: 'text-purple-700 bg-purple-50 border-purple-200', icon: 'ArchiveBoxIcon' },
  voided:    { label: 'Annulé',     color: 'text-gray-700 bg-gray-100 border-gray-300',     icon: 'TrashIcon' },
};

function Badge({ config, value }: { config: Record<string, { label: string; color: string; icon: string }>; value: string }) {
  const cfg = config[value] ?? { label: value, color: 'text-gray-700 bg-gray-100 border-gray-300', icon: 'QuestionMarkCircleIcon' };
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
// Modale : nouvelle émission (create_credit_issuance)
// ----------------------------------------------------------------------------

interface SourceRow {
  organization_id: string;
  organization_name: string;
  aggregator_id: string;
  aggregator_membership_id: string;
  commercialization_mandate_id: string;
  contributed_tco2e: string;
}

function NewIssuanceModal({
  outcome,
  onClose,
  onCreated,
}: {
  outcome: VerificationOutcome;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [memberships, setMemberships] = useState<ActiveMembership[]>([]);
  const [mandates, setMandates] = useState<ActiveMandate[]>([]);
  const [activeOperatorId, setActiveOperatorId] = useState<string | null>(null);
  const [loadingOptions, setLoadingOptions] = useState(true);
  const [optionsError, setOptionsError] = useState('');
  const [selectedMembershipId, setSelectedMembershipId] = useState('');
  const [amount, setAmount] = useState('');
  const [sources, setSources] = useState<SourceRow[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      setLoadingOptions(true);
      setOptionsError('');
      const supabase = createClient();
      // Fenêtre temporelle alignée sur le contrôle serveur exact de
      // create_credit_issuance() : started_at <= clock_timestamp() AND
      // (ended_at IS NULL OR ended_at > clock_timestamp()). Un simple
      // `.is('ended_at', null)` exclurait à tort une adhésion active dont
      // ended_at est déjà connu mais futur, et inclurait à tort une adhésion
      // dont started_at est encore dans le futur.
      const nowIso = new Date().toISOString();
      const [opRes, memRes, mndRes] = await Promise.all([
        supabase.from('platform_operators').select('organization_id').is('revoked_at', null).maybeSingle(),
        supabase
          .from('aggregator_memberships')
          .select('id, organization_id, aggregator_id, started_at, ended_at, organizations(name), aggregators(name)')
          .lte('started_at', nowIso)
          .or(`ended_at.is.null,ended_at.gt.${nowIso}`),
        supabase
          .from('carbon_commercialization_mandates')
          .select('id, aggregator_membership_id, operator_organization_id, scope')
          .is('revoked_at', null),
      ]);
      const errors = [opRes.error, memRes.error, mndRes.error].filter(Boolean);
      if (errors.length > 0) {
        setOptionsError(errors.map((e) => getErrorMessage(e)).join(' · '));
        setLoadingOptions(false);
        return;
      }
      setActiveOperatorId(opRes.data?.organization_id ?? null);
      const mems: ActiveMembership[] = (memRes.data ?? []).map((m: any) => ({
        id: m.id,
        organization_id: m.organization_id,
        aggregator_id: m.aggregator_id,
        organization_name: m.organizations?.name ?? m.organization_id,
        aggregator_name: m.aggregators?.name ?? m.aggregator_id,
      }));
      setMemberships(mems);
      setMandates((mndRes.data ?? []) as ActiveMandate[]);
      setLoadingOptions(false);
    })();
  }, []);

  // Filtrage cohérent : n'apparaissent que les adhésions actives (fenêtre
  // temporelle ci-dessus) qui possèdent un mandat actif, rattaché à CETTE
  // adhésion, autorisant request_issuance, ET désignant l'opérateur
  // METALTRACE actuellement actif. Une fois une première source ajoutée, la
  // liste est en outre restreinte au même regroupement (aggregator_id).
  // Ce filtrage n'est PAS exhaustif : create_credit_issuance() vérifie en
  // outre (sous verrou, au moment de la confirmation) que chaque
  // organisation participe réellement au projet CCF/MRV associé au résultat
  // de vérification (carbon_lock_and_validate_source_organization()) —
  // cette jointure métier n'est délibérément pas reproduite ici ; le serveur
  // reste seul autorité sur ce point, et son message d'erreur est affiché
  // tel quel si la source est rejetée pour cette raison.
  const firstAggregatorId = sources[0]?.aggregator_id ?? null;
  const eligibleMemberships = memberships.filter((m) => {
    if (sources.some((s) => s.aggregator_membership_id === m.id)) return false;
    if (firstAggregatorId && m.aggregator_id !== firstAggregatorId) return false;
    const mandate = mandates.find((mn) => mn.aggregator_membership_id === m.id);
    if (!mandate) return false;
    if (mandate.operator_organization_id !== activeOperatorId) return false;
    if (!mandate.scope?.includes('request_issuance')) return false;
    return true;
  });

  const mandateForSelected = mandates.find((m) => m.aggregator_membership_id === selectedMembershipId);

  const handleAddSource = () => {
    setError('');
    const membership = memberships.find((m) => m.id === selectedMembershipId);
    if (!membership || !mandateForSelected) { setError('Sélectionner une organisation source éligible.'); return; }
    const n = parseFloat(amount);
    if (!amount || Number.isNaN(n) || n <= 0) { setError('Quantité contribuée invalide (doit être > 0).'); return; }
    setSources((prev) => [
      ...prev,
      {
        organization_id: membership.organization_id,
        organization_name: membership.organization_name,
        aggregator_id: membership.aggregator_id,
        aggregator_membership_id: membership.id,
        commercialization_mandate_id: mandateForSelected.id,
        contributed_tco2e: amount,
      },
    ]);
    setSelectedMembershipId('');
    setAmount('');
  };

  const handleRemoveSource = (membershipId: string) => {
    setSources((prev) => prev.filter((s) => s.aggregator_membership_id !== membershipId));
  };

  const totalRequested = sources.reduce((sum, s) => sum + (parseFloat(s.contributed_tco2e) || 0), 0);

  const handleSubmit = async () => {
    setError('');
    if (sources.length === 0) { setError('Au moins une source est requise.'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('create_credit_issuance', {
      p_verification_outcome_id: outcome.id,
      p_sources: sources.map((s) => ({
        organization_id: s.organization_id,
        aggregator_membership_id: s.aggregator_membership_id,
        commercialization_mandate_id: s.commercialization_mandate_id,
        contributed_tco2e: parseFloat(s.contributed_tco2e),
      })),
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onCreated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card">
          <h2 className="text-lg font-700 text-foreground">Nouvelle émission</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-5">
          <div className="bg-muted rounded-lg p-3 text-sm">
            <p className="text-foreground font-600">Résultat de vérification source</p>
            <p className="text-muted-foreground mt-1">
              Admissible : <span className="text-foreground font-600">{fmtNum(outcome.eligible_tco2e)} tCO2e</span>
              {' · '}Vérifié le {fmtDate(outcome.verified_at)}
            </p>
            <p className="text-xs text-muted-foreground mt-1">
              Le serveur revalide la capacité restante réelle (déjà consommée par d&apos;autres émissions, sur l&apos;ensemble de la chaîne de supersession) au moment de la confirmation.
            </p>
          </div>

          <ErrorBanner message={optionsError} />

          {!loadingOptions && !optionsError && !activeOperatorId && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700">
              Aucun opérateur METALTRACE actif désigné — impossible de créer une émission.
            </div>
          )}

          {(loadingOptions || (!optionsError && activeOperatorId)) && (
            <div>
              <p className="text-sm font-600 text-foreground mb-2">Sources (organisation, adhésion et mandat actifs pour l&apos;opérateur en poste)</p>
              {loadingOptions ? (
                <p className="text-sm text-muted-foreground">Chargement des adhésions et mandats actifs…</p>
              ) : (
                <>
                  <div className="flex items-end gap-2 flex-wrap">
                    <div className="flex-1 min-w-[180px]">
                      <label className="block text-xs font-600 text-muted-foreground mb-1">Organisation source</label>
                      <select className="input w-full" value={selectedMembershipId} onChange={(e) => setSelectedMembershipId(e.target.value)}>
                        <option value="">— Choisir —</option>
                        {eligibleMemberships.map((m) => (
                          <option key={m.id} value={m.id}>{m.organization_name} ({m.aggregator_name})</option>
                        ))}
                      </select>
                    </div>
                    <div className="w-36">
                      <label className="block text-xs font-600 text-muted-foreground mb-1">tCO2e contribuées</label>
                      <input className="input w-full" type="number" min="0" step="0.0001" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.0000" />
                    </div>
                    <button type="button" disabled={eligibleMemberships.length === 0} onClick={handleAddSource} className="btn-primary px-3 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
                      Ajouter
                    </button>
                  </div>
                  {eligibleMemberships.length === 0 && (
                    <p className="text-xs text-muted-foreground mt-1">
                      {firstAggregatorId
                        ? 'Aucune autre adhésion éligible dans ce même regroupement (mandat actif, scope request_issuance, opérateur en poste).'
                        : 'Aucune adhésion éligible (mandat actif, scope request_issuance, opérateur en poste) trouvée.'}
                    </p>
                  )}
                </>
              )}
            </div>
          )}

          {sources.length > 0 && (
            <div className="border border-border rounded-lg divide-y divide-border">
              {sources.map((s) => (
                <div key={s.aggregator_membership_id} className="flex items-center justify-between px-3 py-2 text-sm">
                  <span className="text-foreground font-500">{s.organization_name}</span>
                  <span className="text-muted-foreground">{fmtNum(parseFloat(s.contributed_tco2e))} tCO2e</span>
                  <button onClick={() => handleRemoveSource(s.aggregator_membership_id)} className="btn-ghost p-1 rounded">
                    <Icon name="XMarkIcon" size={14} />
                  </button>
                </div>
              ))}
              <div className="flex items-center justify-between px-3 py-2 text-sm bg-muted">
                <span className="font-600 text-foreground">Total demandé</span>
                <span className="font-700 text-foreground">{fmtNum(totalRequested)} tCO2e</span>
              </div>
            </div>
          )}

          {error && <p className="text-sm text-red-600">{error}</p>}

          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving || sources.length === 0 || !activeOperatorId} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Création…' : 'Créer l’émission'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale : nouveau lot (issue_credit_lot)
// ----------------------------------------------------------------------------

function NewLotModal({
  issuance,
  remaining,
  onClose,
  onCreated,
}: {
  issuance: CreditIssuance;
  remaining: number;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [quantity, setQuantity] = useState(remaining > 0 ? String(remaining) : '');
  const [vintageYear, setVintageYear] = useState(String(new Date().getFullYear()));
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    setError('');
    const q = parseFloat(quantity);
    const y = parseInt(vintageYear, 10);
    if (!quantity || Number.isNaN(q) || q <= 0) { setError('Quantité invalide.'); return; }
    if (!vintageYear || Number.isNaN(y)) { setError('Année de millésime invalide.'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('issue_credit_lot', {
      p_credit_issuance_id: issuance.id,
      p_quantity_tco2e: q,
      p_vintage_year: y,
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
          <h2 className="text-lg font-700 text-foreground">Créer un lot commercialisable</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <p className="text-sm text-muted-foreground">
            Reliquat non loti sur cette émission : <span className="text-foreground font-600">{fmtNum(remaining)} tCO2e</span>
          </p>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Quantité (tCO2e) *</label>
            <input className="input w-full" type="number" min="0" step="0.0001" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Année de millésime *</label>
            <input className="input w-full" type="number" value={vintageYear} onChange={(e) => setVintageYear(e.target.value)} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Création…' : 'Créer le lot'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale générique d'action (RPC à un seul objet, champs simples)
// ----------------------------------------------------------------------------

type ActionKind =
  | 'mark_eligible'
  | 'submit'
  | 'record_registry'
  | 'external_cancel'
  | 'external_reject'
  | 'void_issuance'
  | 'void_lot';

interface ActionField {
  key: string;
  label: string;
  type: 'text' | 'date' | 'datetime-local' | 'document-picker';
  placeholder?: string;
  required?: boolean;
}

interface ActionSpec {
  kind: ActionKind;
  title: string;
  confirmLabel: string;
  fields: ActionField[];
  danger?: boolean;
}

const ACTION_SPECS: Record<ActionKind, ActionSpec> = {
  mark_eligible: { kind: 'mark_eligible', title: 'Marquer admissible', confirmLabel: 'Confirmer', fields: [] },
  submit: {
    kind: 'submit', title: 'Soumettre au registre', confirmLabel: 'Soumettre',
    fields: [{ key: 'registry_name', label: 'Nom du registre', type: 'text', placeholder: 'Ex: Verra, Gold Standard…', required: true }],
  },
  record_registry: {
    kind: 'record_registry', title: 'Enregistrer l’émission registre', confirmLabel: 'Enregistrer',
    fields: [
      { key: 'registry_reference', label: 'Référence registre', type: 'text', required: true },
      { key: 'registry_issued_at', label: 'Date et heure d’émission registre', type: 'datetime-local', required: true },
    ],
  },
  external_cancel: {
    kind: 'external_cancel', title: 'Annulation externe', confirmLabel: 'Enregistrer l’annulation', danger: true,
    fields: [
      { key: 'date', label: 'Date d’annulation', type: 'date', required: true },
      { key: 'reference', label: 'Référence', type: 'text', required: true },
      { key: 'document_id', label: 'Document de preuve', type: 'document-picker', required: true },
    ],
  },
  external_reject: {
    kind: 'external_reject', title: 'Rejet externe', confirmLabel: 'Enregistrer le rejet', danger: true,
    fields: [
      { key: 'date', label: 'Date de rejet', type: 'date', required: true },
      { key: 'reference', label: 'Référence', type: 'text', required: true },
      { key: 'document_id', label: 'Document de preuve', type: 'document-picker', required: true },
    ],
  },
  void_issuance: {
    kind: 'void_issuance', title: 'Annuler l’émission', confirmLabel: 'Annuler l’émission', danger: true,
    fields: [{ key: 'reason', label: 'Motif', type: 'text', required: true }],
  },
  void_lot: {
    kind: 'void_lot', title: 'Annuler le lot (correction interne)', confirmLabel: 'Annuler le lot', danger: true,
    fields: [{ key: 'reason', label: 'Motif', type: 'text', required: true }],
  },
};

function ActionModal({
  spec,
  documentPickerOwnerOrgId,
  onClose,
  onConfirm,
}: {
  spec: ActionSpec;
  documentPickerOwnerOrgId?: string;
  onClose: () => void;
  onConfirm: (values: Record<string, string>) => Promise<string | null>; // renvoie un message d'erreur, ou null si succès
}) {
  const [values, setValues] = useState<Record<string, string>>(
    Object.fromEntries(spec.fields.map((f) => [
      f.key,
      // Les champs date/datetime-local restants (date d'annulation externe,
      // date de rejet externe) désignent tous un événement réglementaire
      // externe : new Date().toISOString() renvoie la date/heure UTC, que le
      // navigateur réinterpréterait en heure LOCALE pour ces types de champ —
      // au Québec en soirée, cela peut préremplir la date du lendemain. Pour
      // une donnée externe faisant foi, tous ces champs restent volontairement
      // vides : l'utilisateur saisit la date/l'instant officiellement fourni
      // par le registre ou l'organisme externe, jamais une valeur par défaut.
      '',
    ]))
  );
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const hasDocumentPicker = spec.fields.some((f) => f.type === 'document-picker');
  const [documents, setDocuments] = useState<DocumentOption[]>([]);
  const [documentsLoading, setDocumentsLoading] = useState(hasDocumentPicker);
  const [documentsError, setDocumentsError] = useState('');

  useEffect(() => {
    if (!hasDocumentPicker) return;
    if (!documentPickerOwnerOrgId) {
      setDocumentsError('Organisation opératrice inconnue — impossible de charger les documents.');
      setDocumentsLoading(false);
      return;
    }
    (async () => {
      setDocumentsLoading(true);
      setDocumentsError('');
      const supabase = createClient();
      const { data, error: err } = await supabase
        .from('documents')
        .select('id, title, category')
        .eq('owner_org_id', documentPickerOwnerOrgId)
        .order('created_at', { ascending: false });
      if (err) { setDocumentsError(getErrorMessage(err)); setDocumentsLoading(false); return; }
      setDocuments((data ?? []) as DocumentOption[]);
      setDocumentsLoading(false);
    })();
  }, [hasDocumentPicker, documentPickerOwnerOrgId]);

  const handleSubmit = async () => {
    setError('');
    for (const f of spec.fields) {
      if (f.required && !values[f.key]?.trim()) { setError(`${f.label} est requis.`); return; }
    }
    setSaving(true);
    const err = await onConfirm(values);
    setSaving(false);
    if (err) { setError(err); return; }
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">{spec.title}</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          {spec.fields.length === 0 && <p className="text-sm text-muted-foreground">Confirmer cette action ?</p>}
          {spec.fields.map((f) => (
            <div key={f.key}>
              <label className="block text-sm font-600 text-foreground mb-1">{f.label}{f.required ? ' *' : ''}</label>
              {f.type === 'document-picker' ? (
                documentsLoading ? (
                  <p className="text-sm text-muted-foreground">Chargement des documents…</p>
                ) : documentsError ? (
                  <ErrorBanner message={documentsError} />
                ) : documents.length === 0 ? (
                  <p className="text-sm text-red-600">Aucun document disponible pour l&apos;organisation opératrice — téléverser d&apos;abord la preuve dans le module Documents.</p>
                ) : (
                  <select
                    className="input w-full"
                    value={values[f.key] ?? ''}
                    onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value }))}
                  >
                    <option value="">— Choisir —</option>
                    {documents.map((d) => (
                      <option key={d.id} value={d.id}>{d.title}{d.category ? ` (${d.category})` : ''}</option>
                    ))}
                  </select>
                )
              ) : (
                <input
                  className="input w-full"
                  type={f.type}
                  value={values[f.key] ?? ''}
                  placeholder={f.placeholder}
                  onChange={(e) => setValues((v) => ({ ...v, [f.key]: e.target.value }))}
                />
              )}
            </div>
          ))}
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button
              type="button"
              disabled={saving}
              onClick={handleSubmit}
              className={`flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50 ${spec.danger ? 'bg-red-600 text-white hover:bg-red-700' : 'btn-primary'}`}
            >
              {saving ? 'Traitement…' : spec.confirmLabel}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Panneau détail d'une émission
// ----------------------------------------------------------------------------

const ISSUANCE_SELECT = '*, aggregators(name), operator:organizations!operator_organization_id(name)';

function IssuanceDetailPanel({
  issuance: initialIssuance,
  onClose,
  onChanged,
}: {
  issuance: CreditIssuance;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [issuance, setIssuance] = useState<CreditIssuance>(initialIssuance);
  const [sources, setSources] = useState<CreditIssuanceSource[]>([]);
  const [lots, setLots] = useState<CreditLot[]>([]);
  const [loading, setLoading] = useState(true);
  const [listError, setListError] = useState('');
  const [showNewLot, setShowNewLot] = useState(false);
  const [activeAction, setActiveAction] = useState<ActionKind | null>(null);
  const [banner, setBanner] = useState('');

  const fetchDetail = useCallback(async () => {
    setLoading(true);
    setListError('');
    const supabase = createClient();
    const [issRes, srcRes, lotRes] = await Promise.all([
      supabase.from('credit_issuances').select(ISSUANCE_SELECT).eq('id', issuance.id).single(),
      supabase.from('credit_issuance_sources').select('*, organizations(name)').eq('credit_issuance_id', issuance.id),
      supabase.from('credit_lots').select('*').eq('credit_issuance_id', issuance.id).order('created_at', { ascending: false }),
    ]);
    const errors = [issRes.error, srcRes.error, lotRes.error].filter(Boolean);
    if (errors.length > 0) {
      setListError(errors.map((e) => getErrorMessage(e)).join(' · '));
      setLoading(false);
      return;
    }
    if (issRes.data) setIssuance(issRes.data as unknown as CreditIssuance);
    setSources((srcRes.data ?? []) as CreditIssuanceSource[]);
    setLots((lotRes.data ?? []) as CreditLot[]);
    setLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [issuance.id]);

  useEffect(() => { fetchDetail(); }, [fetchDetail]);

  const lottedQuantity = lots.filter((l) => l.commercial_status !== 'voided').reduce((sum, l) => sum + Number(l.quantity_tco2e), 0);
  const remaining = Number(issuance.quantity_tco2e) - lottedQuantity;

  const refreshAll = () => { fetchDetail(); onChanged(); };

  const runRpc = async (name: string, params: Record<string, unknown>): Promise<string | null> => {
    const supabase = createClient();
    const { error } = await supabase.rpc(name, params);
    if (error) return getErrorMessage(error);
    setBanner('Action effectuée.');
    refreshAll();
    return null;
  };

  const handleAction = async (kind: ActionKind, values: Record<string, string>): Promise<string | null> => {
    switch (kind) {
      case 'mark_eligible':
        return runRpc('mark_credit_issuance_eligible', { p_credit_issuance_id: issuance.id });
      case 'submit':
        return runRpc('submit_credit_issuance', { p_credit_issuance_id: issuance.id, p_registry_name: values.registry_name });
      case 'record_registry': {
        // Le champ HTML datetime-local ne porte pas de fuseau horaire —
        // interprété ici en heure locale du navigateur, puis converti en
        // instant absolu ISO (UTC) attendu par la colonne TIMESTAMPTZ.
        const parsed = new Date(values.registry_issued_at);
        if (Number.isNaN(parsed.getTime())) return 'Date et heure d’émission registre invalides.';
        return runRpc('record_registry_issuance', {
          p_credit_issuance_id: issuance.id,
          p_registry_reference: values.registry_reference,
          p_registry_issued_at: parsed.toISOString(),
        });
      }
      case 'external_cancel':
        return runRpc('record_external_cancellation', {
          p_credit_issuance_id: issuance.id, p_date: values.date, p_reference: values.reference, p_document_id: values.document_id,
        });
      case 'external_reject':
        return runRpc('record_externally_rejected', {
          p_credit_issuance_id: issuance.id, p_date: values.date, p_reference: values.reference, p_document_id: values.document_id,
        });
      case 'void_issuance':
        return runRpc('void_credit_issuance', { p_credit_issuance_id: issuance.id, p_reason: values.reason });
      default:
        return 'Action non supportée ici.';
    }
  };

  const handleVoidLot = async (lotId: string, values: Record<string, string>): Promise<string | null> => {
    return runRpc('void_credit_lot', { p_credit_lot_id: lotId, p_reason: values.reason });
  };

  const [voidLotTarget, setVoidLotTarget] = useState<string | null>(null);

  // Matrice d'actions stricte, alignée sur carbon_credit_issuances_before_update
  // (migration 07) — void_credit_issuance() n'est légal que depuis
  // internal/eligible ; externally_rejected/externally_cancelled passent
  // exclusivement par record_externally_rejected()/record_external_cancellation().
  const status = issuance.issuance_status;
  const canMarkEligible = status === 'internal';
  const canSubmit = status === 'eligible';
  const canRecordRegistry = status === 'submitted';
  const canExternalReject = status === 'submitted';
  const canExternalCancel = status === 'issued';
  const canCreateLot = status === 'issued' && remaining > 0;
  const canVoidIssuance = status === 'internal' || status === 'eligible';

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative w-full max-w-lg h-full bg-card border-l border-border shadow-2xl overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <div>
            <h2 className="text-lg font-700 text-foreground">Émission</h2>
            <p className="text-xs text-muted-foreground font-mono">{issuance.id}</p>
          </div>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>

        <div className="p-5 space-y-5">
          <ErrorBanner message={listError} />

          <div className="flex items-center gap-2">
            <Badge config={ISSUANCE_STATUS_CONFIG} value={issuance.issuance_status} />
            <span className="text-sm text-muted-foreground">Créée le {fmtDateTime(issuance.created_at)}</span>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm">
            <div><p className="text-muted-foreground text-xs">Regroupement</p><p className="font-600 text-foreground">{issuance.aggregators?.name ?? issuance.aggregator_id}</p></div>
            <div><p className="text-muted-foreground text-xs">Opérateur</p><p className="font-600 text-foreground">{issuance.operator?.name ?? issuance.operator_organization_id}</p></div>
            <div><p className="text-muted-foreground text-xs">Quantité totale</p><p className="font-600 text-foreground">{fmtNum(issuance.quantity_tco2e)} tCO2e</p></div>
            <div><p className="text-muted-foreground text-xs">Reliquat non loti</p><p className="font-600 text-foreground">{fmtNum(remaining)} tCO2e</p></div>
          </div>

          {(issuance.registry_name || issuance.registry_reference) && (
            <div className="bg-muted rounded-lg p-3 text-sm">
              <p className="font-600 text-foreground mb-1">Registre</p>
              {issuance.registry_name && <p className="text-muted-foreground">Nom : {issuance.registry_name}</p>}
              {issuance.registry_reference && <p className="text-muted-foreground">Référence : {issuance.registry_reference}</p>}
              {issuance.registry_issued_at && <p className="text-muted-foreground">Émise le : {fmtDateTime(issuance.registry_issued_at)}</p>}
            </div>
          )}

          {issuance.void_reason && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700">Motif d&apos;annulation : {issuance.void_reason}</div>
          )}

          {banner && <div className="bg-green-50 border border-green-200 rounded-lg p-2 text-sm text-green-700">{banner}</div>}

          {/* Actions selon statut — matrice stricte (voir en-tête de fichier) */}
          <div className="flex flex-wrap gap-2">
            {canMarkEligible && (
              <button onClick={() => setActiveAction('mark_eligible')} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Marquer admissible</button>
            )}
            {canSubmit && (
              <button onClick={() => setActiveAction('submit')} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Soumettre au registre</button>
            )}
            {canRecordRegistry && (
              <button onClick={() => setActiveAction('record_registry')} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Enregistrer l&apos;émission registre</button>
            )}
            {canCreateLot && (
              <button onClick={() => setShowNewLot(true)} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Créer un lot</button>
            )}
            {canExternalReject && (
              <button onClick={() => setActiveAction('external_reject')} className="btn-ghost px-3 py-2 rounded-lg text-sm font-600 text-red-700">Rejet externe</button>
            )}
            {canExternalCancel && (
              <button onClick={() => setActiveAction('external_cancel')} className="btn-ghost px-3 py-2 rounded-lg text-sm font-600 text-red-700">Annulation externe</button>
            )}
            {canVoidIssuance && (
              <button onClick={() => setActiveAction('void_issuance')} className="btn-ghost px-3 py-2 rounded-lg text-sm font-600 text-red-700">Annuler l&apos;émission</button>
            )}
          </div>

          {/* Sources */}
          <div>
            <p className="text-sm font-600 text-foreground mb-2">Sources</p>
            {loading ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : sources.length === 0 ? (
              <p className="text-sm text-muted-foreground">Aucune source.</p>
            ) : (
              <div className="border border-border rounded-lg divide-y divide-border">
                {sources.map((s) => (
                  <div key={s.id} className="flex items-center justify-between px-3 py-2 text-sm">
                    <span className="text-foreground">{s.organizations?.name ?? s.organization_id}</span>
                    <span className="text-muted-foreground">{fmtNum(s.contributed_tco2e)} tCO2e</span>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Lots */}
          <div>
            <p className="text-sm font-600 text-foreground mb-2">Lots issus de cette émission</p>
            {loading ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : lots.length === 0 ? (
              <p className="text-sm text-muted-foreground">Aucun lot créé.</p>
            ) : (
              <div className="border border-border rounded-lg divide-y divide-border">
                {lots.map((l) => (
                  <div key={l.id} className="flex items-center justify-between px-3 py-2 text-sm gap-2">
                    <div>
                      <p className="text-foreground font-500">{fmtNum(l.quantity_tco2e)} tCO2e · millésime {l.vintage_year}</p>
                      <p className="text-xs text-muted-foreground font-mono">{l.id.slice(0, 8)}…</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge config={LOT_STATUS_CONFIG} value={l.commercial_status} />
                      {l.commercial_status === 'available' ? (
                        <button onClick={() => setVoidLotTarget(l.id)} className="btn-ghost p-1.5 rounded text-red-700" title="Annuler (correction interne)">
                          <Icon name="TrashIcon" size={14} />
                        </button>
                      ) : ['reserved', 'sold', 'retired'].includes(l.commercial_status) ? (
                        <span className="text-xs text-muted-foreground">module Ventes</span>
                      ) : null}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {showNewLot && (
        <NewLotModal issuance={issuance} remaining={remaining} onClose={() => setShowNewLot(false)} onCreated={refreshAll} />
      )}
      {activeAction && (
        <ActionModal
          spec={ACTION_SPECS[activeAction]}
          documentPickerOwnerOrgId={issuance.operator_organization_id}
          onClose={() => setActiveAction(null)}
          onConfirm={(values) => handleAction(activeAction, values)}
        />
      )}
      {voidLotTarget && (
        <ActionModal
          spec={ACTION_SPECS.void_lot}
          onClose={() => setVoidLotTarget(null)}
          onConfirm={(values) => handleVoidLot(voidLotTarget, values)}
        />
      )}
    </div>
  );
}

// ----------------------------------------------------------------------------
// Page principale
// ----------------------------------------------------------------------------

export default function AdminCarbonInventoryPage() {
  const [tab, setTab] = useState<TabId>('outcomes');
  const [outcomes, setOutcomes] = useState<VerificationOutcome[]>([]);
  const [issuances, setIssuances] = useState<CreditIssuance[]>([]);
  const [lots, setLots] = useState<CreditLot[]>([]);
  const [loading, setLoading] = useState(true);
  const [listError, setListError] = useState('');
  const [selectedOutcome, setSelectedOutcome] = useState<VerificationOutcome | null>(null);
  const [selectedIssuance, setSelectedIssuance] = useState<CreditIssuance | null>(null);
  const [issuanceFilter, setIssuanceFilter] = useState<string>('all');
  const [lotFilter, setLotFilter] = useState<string>('all');

  const fetchAll = useCallback(async () => {
    setLoading(true);
    setListError('');
    const supabase = createClient();
    const [outRes, issRes, lotRes] = await Promise.all([
      supabase
        .from('verification_outcomes')
        .select('*, verification_sessions(project_id, reporting_period_start, reporting_period_end, projects(name))')
        .eq('status', 'active')
        .order('verified_at', { ascending: false }),
      supabase
        .from('credit_issuances')
        .select(ISSUANCE_SELECT)
        .order('created_at', { ascending: false }),
      supabase
        .from('credit_lots')
        .select('*, aggregators(name)')
        .order('created_at', { ascending: false }),
    ]);
    const errors = [outRes.error, issRes.error, lotRes.error].filter(Boolean);
    if (errors.length > 0) {
      setListError(errors.map((e) => getErrorMessage(e)).join(' · '));
      setLoading(false);
      return;
    }
    setOutcomes((outRes.data ?? []) as VerificationOutcome[]);
    setIssuances((issRes.data ?? []) as unknown as CreditIssuance[]);
    setLots((lotRes.data ?? []) as CreditLot[]);
    setLoading(false);
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  const filteredIssuances = issuanceFilter === 'all' ? issuances : issuances.filter((i) => i.issuance_status === issuanceFilter);
  const filteredLots = lotFilter === 'all' ? lots : lots.filter((l) => l.commercial_status === lotFilter);

  const totalEligible = outcomes.reduce((s, o) => s + Number(o.eligible_tco2e), 0);
  const totalIssued = issuances.filter((i) => i.issuance_status === 'issued').reduce((s, i) => s + Number(i.quantity_tco2e), 0);
  const totalAvailableLots = lots.filter((l) => l.commercial_status === 'available').reduce((s, l) => s + Number(l.quantity_tco2e), 0);

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Inventaire carbone</h1>
            <p className="text-sm text-muted-foreground mt-1">Résultats de vérification → émissions → lots commercialisables</p>
          </div>
        </div>

        <ErrorBanner message={listError} />

        {/* KPI row */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          <div className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center text-blue-600"><Icon name="CheckCircleIcon" size={20} /></div>
            <div><p className="text-2xl font-700 text-foreground">{fmtNum(totalEligible, 2)}</p><p className="text-xs text-muted-foreground">tCO2e admissibles (résultats actifs)</p></div>
          </div>
          <div className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center text-green-600"><Icon name="CheckBadgeIcon" size={20} /></div>
            <div><p className="text-2xl font-700 text-foreground">{fmtNum(totalIssued, 2)}</p><p className="text-xs text-muted-foreground">tCO2e émises (registre)</p></div>
          </div>
          <div className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center text-purple-600"><Icon name="ArchiveBoxIcon" size={20} /></div>
            <div><p className="text-2xl font-700 text-foreground">{fmtNum(totalAvailableLots, 2)}</p><p className="text-xs text-muted-foreground">tCO2e disponibles en lots</p></div>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-2 mb-4 border-b border-border">
          {([
            { id: 'outcomes', label: 'Résultats de vérification' },
            { id: 'issuances', label: 'Émissions' },
            { id: 'lots', label: 'Lots' },
          ] as { id: TabId; label: string }[]).map((t) => (
            <button
              key={t.id}
              onClick={() => setTab(t.id)}
              className={`px-4 py-2 text-sm font-600 border-b-2 -mb-px transition-all ${tab === t.id ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'}`}
            >
              {t.label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="space-y-3">{[1, 2, 3].map((i) => <div key={i} className="h-20 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : tab === 'outcomes' ? (
          outcomes.length === 0 ? (
            <div className="bg-card border border-border rounded-xl p-12 text-center">
              <Icon name="CheckCircleIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
              <p className="text-muted-foreground font-500">Aucun résultat de vérification actif</p>
              <p className="text-xs text-muted-foreground mt-1">Les résultats apparaissent ici une fois une session de vérification complétée.</p>
            </div>
          ) : (
            <div className="space-y-3">
              {outcomes.map((o) => (
                <div key={o.id} className="bg-card border border-border rounded-xl p-5">
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex-1 min-w-0">
                      <p className="font-700 text-foreground">{o.verification_sessions?.projects?.name ?? 'Projet MRV'}</p>
                      <p className="text-sm text-muted-foreground mt-1">
                        Admissible : <span className="text-foreground font-600">{fmtNum(o.eligible_tco2e)} tCO2e</span>
                      </p>
                      <p className="text-xs text-muted-foreground mt-1">
                        Le reliquat réel (déjà consommé par d&apos;autres émissions sur cette session) n&apos;est calculable que côté serveur — il est revalidé automatiquement à la création d&apos;une émission.
                      </p>
                      {o.verification_sessions?.reporting_period_start && (
                        <p className="text-xs text-muted-foreground mt-1">
                          Période : {fmtDate(o.verification_sessions.reporting_period_start)} → {fmtDate(o.verification_sessions.reporting_period_end)}
                        </p>
                      )}
                      <p className="text-xs text-muted-foreground mt-0.5">Vérifié le {fmtDate(o.verified_at)}</p>
                    </div>
                    <button onClick={() => setSelectedOutcome(o)} className="btn-primary px-3 py-2 rounded-lg text-sm font-600 flex-shrink-0">
                      Créer une émission
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )
        ) : tab === 'issuances' ? (
          <>
            <div className="flex gap-2 mb-4 flex-wrap">
              {['all', ...Object.keys(ISSUANCE_STATUS_CONFIG)].map((s) => (
                <button key={s} onClick={() => setIssuanceFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${issuanceFilter === s ? 'bg-primary text-primary-foreground border-primary' : 'bg-card text-muted-foreground border-border hover:border-primary/50'}`}>
                  {s === 'all' ? 'Toutes' : ISSUANCE_STATUS_CONFIG[s]?.label ?? s}
                </button>
              ))}
            </div>
            {filteredIssuances.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-12 text-center">
                <Icon name="DocumentIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
                <p className="text-muted-foreground font-500">Aucune émission</p>
              </div>
            ) : (
              <div className="space-y-3">
                {filteredIssuances.map((i) => (
                  <button key={i.id} onClick={() => setSelectedIssuance(i)} className="w-full text-left bg-card border border-border rounded-xl p-5 hover:border-primary/50 transition-all group">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-3 mb-1">
                          <p className="font-700 text-foreground group-hover:text-primary transition-colors">{fmtNum(i.quantity_tco2e)} tCO2e</p>
                          <Badge config={ISSUANCE_STATUS_CONFIG} value={i.issuance_status} />
                        </div>
                        <p className="text-sm text-muted-foreground">
                          {i.aggregators?.name ?? i.aggregator_id} · Opérateur : {i.operator?.name ?? i.operator_organization_id}
                        </p>
                        <p className="text-xs text-muted-foreground mt-1">Créée le {fmtDateTime(i.created_at)}</p>
                      </div>
                      <Icon name="ChevronRightIcon" size={18} className="text-muted-foreground group-hover:text-primary transition-colors flex-shrink-0 mt-1" />
                    </div>
                  </button>
                ))}
              </div>
            )}
          </>
        ) : (
          <>
            <div className="flex gap-2 mb-4 flex-wrap">
              {['all', ...Object.keys(LOT_STATUS_CONFIG)].map((s) => (
                <button key={s} onClick={() => setLotFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${lotFilter === s ? 'bg-primary text-primary-foreground border-primary' : 'bg-card text-muted-foreground border-border hover:border-primary/50'}`}>
                  {s === 'all' ? 'Tous' : LOT_STATUS_CONFIG[s]?.label ?? s}
                </button>
              ))}
            </div>
            {filteredLots.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-12 text-center">
                <Icon name="ArchiveBoxIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
                <p className="text-muted-foreground font-500">Aucun lot</p>
              </div>
            ) : (
              <div className="space-y-3">
                {filteredLots.map((l) => (
                  <div key={l.id} className="bg-card border border-border rounded-xl p-5">
                    <div className="flex items-start justify-between gap-4">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-3 mb-1">
                          <p className="font-700 text-foreground">{fmtNum(l.quantity_tco2e)} tCO2e · millésime {l.vintage_year}</p>
                          <Badge config={LOT_STATUS_CONFIG} value={l.commercial_status} />
                        </div>
                        <p className="text-sm text-muted-foreground">{l.aggregators?.name ?? l.aggregator_id}</p>
                        <p className="text-xs text-muted-foreground mt-1 font-mono">{l.id}</p>
                        {l.void_reason && <p className="text-xs text-red-600 mt-1">Motif : {l.void_reason}</p>}
                        {['reserved', 'sold', 'retired'].includes(l.commercial_status) && (
                          <p className="text-xs text-muted-foreground mt-1">Géré par le module Ventes (hors périmètre de cette page).</p>
                        )}
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>

      {selectedOutcome && (
        <NewIssuanceModal outcome={selectedOutcome} onClose={() => setSelectedOutcome(null)} onCreated={fetchAll} />
      )}
      {selectedIssuance && (
        <IssuanceDetailPanel issuance={selectedIssuance} onClose={() => setSelectedIssuance(null)} onChanged={fetchAll} />
      )}
    </div>
  );
}
