'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';
import AppLayout from '@/components/AppLayout';

// ============================================================================
// /admin/carbon-sales
// ----------------------------------------------------------------------------
// Vertical slice « Cockpit de ventes — Lot 3 ».
// Périmètre : credit_sales / credit_sale_lots / credit_sale_costs /
// credit_sale_allocations (migration 09). Toute l'autorité métier reste côté
// PostgreSQL (RPC SECURITY DEFINER) : cette page ne fait que lire l'état et
// déclencher les RPC. Aucun calcul de statut, de montant ou de répartition
// n'est recalculé côté client (compute_credit_sale_allocations() reste seule
// autorité sur les allocations — jamais reproduit ici).
//
// Décision d'architecture confirmée par lecture directe des RPC réelles avant
// construction (add_credit_sale_lot, add_credit_sale_cost, confirm_credit_sale,
// release_credit_sale_lot, cancel_credit_sale vérifient tous explicitement
// is_platform_operator(seller_organization_id)) : le vendeur d'une vente de
// crédits carbone est TOUJOURS l'organisation opératrice METALTRACE active
// (MINOVIA en environnement de test) — jamais une organisation membre
// individuelle. create_credit_sale() seul ne le vérifie pas à la création
// (seulement is_org_admin) ; une vente créée avec un autre vendeur resterait
// bloquée en draft, rejetée dès le premier add_credit_sale_lot(). Cette page
// ne propose donc que l'opérateur actif comme organisation vendeuse.
//
// Machine à états reflétée ici (source : CHECK constraints réelles + RPC de
// production, migration 09) :
//   credit_sales.status : draft -> confirmed -> settled
//                          draft -> cancelled
//   Aucune autre transition n'existe. confirm_credit_sale() exige au moins un
//   lot actif (released_at IS NULL) et gèle gross_amount/net_distributable_amount
//   + déclenche compute_credit_sale_allocations() + passe les lots à 'sold'.
//   cancel_credit_sale()/release_credit_sale_lot() ne sont légaux que draft.
//   settle_credit_sale() n'est légal que confirmed, exige une référence de
//   règlement non vide.
// ============================================================================

interface CreditSale {
  id: string;
  seller_organization_id: string;
  status: string;
  currency: string;
  price_per_tco2e: number;
  total_tco2e: number;
  gross_amount: number | null;
  net_distributable_amount: number | null;
  buyer_reference: string | null;
  sale_date: string;
  confirmed_at: string | null;
  confirmed_by: string | null;
  settled_at: string | null;
  settlement_reference: string | null;
  cancelled_at: string | null;
  cancel_reason: string | null;
  created_at: string;
  created_by: string;
  seller?: { name: string } | null;
}

interface CreditSaleLotRow {
  id: string;
  credit_sale_id: string;
  credit_lot_id: string;
  quantity_tco2e: number;
  released_at: string | null;
  released_by: string | null;
  release_reason: string | null;
  created_at: string;
  credit_lots?: { vintage_year: number; aggregator_id: string; aggregators?: { name: string } | null } | null;
}

interface CreditSaleCost {
  id: string;
  cost_type: string;
  description: string | null;
  amount: number;
  beneficiary: string | null;
  created_at: string;
}

interface CreditSaleAllocation {
  id: string;
  organization_id: string;
  aggregator_id: string;
  allocation_type: string;
  allocated_tco2e: number | null;
  gross_amount: number;
  fee_applied_pct: number;
  reserve_applied_pct: number;
  weight_applied: number;
  fee_amount: number;
  reserve_amount: number;
  net_amount: number;
  distribution_rule_id: string | null;
  organizations?: { name: string } | null;
}

interface AvailableLot {
  id: string;
  quantity_tco2e: number;
  vintage_year: number;
  aggregator_id: string;
  aggregators?: { name: string } | null;
}

// ----------------------------------------------------------------------------
// Libellés / badges
// ----------------------------------------------------------------------------

const SALE_STATUS_CONFIG: Record<string, { label: string; color: string; icon: string }> = {
  draft:     { label: 'Brouillon',  color: 'text-slate-700 bg-slate-50 border-slate-200',  icon: 'DocumentIcon' },
  confirmed: { label: 'Confirmée',  color: 'text-blue-700 bg-blue-50 border-blue-200',      icon: 'CheckCircleIcon' },
  settled:   { label: 'Réglée',     color: 'text-green-700 bg-green-50 border-green-200',   icon: 'CheckBadgeIcon' },
  cancelled: { label: 'Annulée',    color: 'text-gray-700 bg-gray-100 border-gray-300',     icon: 'XCircleIcon' },
};

const COST_TYPE_LABELS: Record<string, string> = {
  platform_fee: 'Frais de plateforme', registry_fee: 'Frais de registre', verification_fee: 'Frais de vérification',
  brokerage: 'Courtage', legal_fee: 'Frais juridiques', risk_reserve: 'Réserve de risque',
  administrative_fee: 'Frais administratifs', tax: 'Taxe', other: 'Autre',
};

const ALLOCATION_TYPE_LABELS: Record<string, string> = {
  carbon_revenue: 'Revenu carbone (membre)', reserve: 'Réserve', platform_fee: 'Frais de plateforme',
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

function fmtMoney(n: number | null | undefined): string {
  if (n === null || n === undefined) return '—';
  return Number(n).toLocaleString('fr-CA', { style: 'currency', currency: 'CAD' });
}

function fmtDate(s: string | null | undefined): string {
  if (!s) return '—';
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
// Modale : nouvelle vente (create_credit_sale)
// ----------------------------------------------------------------------------

function NewSaleModal({
  operatorOrgId,
  operatorOrgName,
  onClose,
  onCreated,
}: {
  operatorOrgId: string;
  operatorOrgName: string;
  onClose: () => void;
  onCreated: () => void;
}) {
  const [price, setPrice] = useState('');
  const [buyerRef, setBuyerRef] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    setError('');
    const p = parseFloat(price);
    if (!price || Number.isNaN(p) || p <= 0) { setError('Prix par tCO2e invalide (doit être > 0).'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('create_credit_sale', {
      p_seller_organization_id: operatorOrgId,
      p_price_per_tco2e: p,
      p_buyer_reference: buyerRef.trim() || null,
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
          <h2 className="text-lg font-700 text-foreground">Nouvelle vente</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div className="bg-muted rounded-lg p-3 text-sm">
            <p className="text-foreground font-600">Organisation vendeuse</p>
            <p className="text-muted-foreground mt-1">{operatorOrgName} (opérateur METALTRACE actif — fixé, non modifiable ici)</p>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Prix par tCO2e (CAD) *</label>
            <input className="input w-full" type="number" min="0" step="0.01" value={price} onChange={(e) => setPrice(e.target.value)} placeholder="0.00" />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Référence acheteur</label>
            <input className="input w-full" type="text" value={buyerRef} onChange={(e) => setBuyerRef(e.target.value)} placeholder="Optionnel" />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Création…' : 'Créer la vente (brouillon)'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale : ajouter un lot (add_credit_sale_lot)
// ----------------------------------------------------------------------------

function AddLotModal({
  saleId,
  onClose,
  onAdded,
}: {
  saleId: string;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [lots, setLots] = useState<AvailableLot[]>([]);
  const [loadingLots, setLoadingLots] = useState(true);
  const [lotsError, setLotsError] = useState('');
  const [selectedLotId, setSelectedLotId] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      setLoadingLots(true);
      setLotsError('');
      const supabase = createClient();
      const { data, error: err } = await supabase
        .from('credit_lots')
        .select('id, quantity_tco2e, vintage_year, aggregator_id, aggregators(name)')
        .eq('commercial_status', 'available')
        .order('created_at', { ascending: false });
      if (err) { setLotsError(getErrorMessage(err)); setLoadingLots(false); return; }
      setLots((data ?? []) as unknown as AvailableLot[]);
      setLoadingLots(false);
    })();
  }, []);

  const handleSubmit = async () => {
    setError('');
    if (!selectedLotId) { setError('Sélectionner un lot.'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('add_credit_sale_lot', {
      p_credit_sale_id: saleId,
      p_credit_lot_id: selectedLotId,
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onAdded();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">Ajouter un lot</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <ErrorBanner message={lotsError} />
          {loadingLots ? (
            <p className="text-sm text-muted-foreground">Chargement des lots disponibles…</p>
          ) : lots.length === 0 ? (
            <p className="text-sm text-muted-foreground">Aucun lot disponible (statut &laquo; available &raquo;). Créer un lot via /admin/carbon-inventory d&apos;abord.</p>
          ) : (
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Lot disponible *</label>
              <select className="input w-full" value={selectedLotId} onChange={(e) => setSelectedLotId(e.target.value)}>
                <option value="">— Choisir —</option>
                {lots.map((l) => (
                  <option key={l.id} value={l.id}>
                    {fmtNum(l.quantity_tco2e)} tCO2e · millésime {l.vintage_year} · {l.aggregators?.name ?? l.aggregator_id}
                  </option>
                ))}
              </select>
              <p className="text-xs text-muted-foreground mt-2">
                Le serveur revalide que ce lot appartient bien à une émission dont au moins une source a un mandat rattaché à l&apos;opérateur vendeur, sous verrou, au moment de l&apos;ajout.
              </p>
            </div>
          )}
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving || !selectedLotId} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Ajout…' : 'Ajouter à la vente'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale : ajouter un coût (add_credit_sale_cost)
// ----------------------------------------------------------------------------

function AddCostModal({
  saleId,
  onClose,
  onAdded,
}: {
  saleId: string;
  onClose: () => void;
  onAdded: () => void;
}) {
  const [costType, setCostType] = useState('platform_fee');
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [beneficiary, setBeneficiary] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async () => {
    setError('');
    const a = parseFloat(amount);
    if (!amount || Number.isNaN(a) || a < 0) { setError('Montant invalide.'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('add_credit_sale_cost', {
      p_credit_sale_id: saleId,
      p_cost_type: costType,
      p_amount: a,
      p_description: description.trim() || null,
      p_beneficiary: beneficiary.trim() || null,
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onAdded();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">Ajouter un coût</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Type de coût *</label>
            <select className="input w-full" value={costType} onChange={(e) => setCostType(e.target.value)}>
              {Object.entries(COST_TYPE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Montant (CAD) *</label>
            <input className="input w-full" type="number" min="0" step="0.01" value={amount} onChange={(e) => setAmount(e.target.value)} placeholder="0.00" />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Description</label>
            <input className="input w-full" type="text" value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Optionnel" />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Bénéficiaire</label>
            <input className="input w-full" type="text" value={beneficiary} onChange={(e) => setBeneficiary(e.target.value)} placeholder="Optionnel" />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Ajout…' : 'Ajouter le coût'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale générique d'action (settle / cancel)
// ----------------------------------------------------------------------------

type ActionKind = 'settle' | 'cancel';

function ActionModal({
  kind,
  onClose,
  onConfirm,
}: {
  kind: ActionKind;
  onClose: () => void;
  onConfirm: (value: string) => Promise<string | null>;
}) {
  const [value, setValue] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const spec = kind === 'settle'
    ? { title: 'Régler la vente', label: 'Référence de règlement *', confirmLabel: 'Régler', danger: false }
    : { title: 'Annuler la vente', label: 'Motif d’annulation *', confirmLabel: 'Annuler la vente', danger: true };

  const handleSubmit = async () => {
    setError('');
    if (!value.trim()) { setError(`${spec.label.replace(' *', '')} est requis.`); return; }
    setSaving(true);
    const err = await onConfirm(value.trim());
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
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">{spec.label}</label>
            <input className="input w-full" type="text" value={value} onChange={(e) => setValue(e.target.value)} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Fermer</button>
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
// Panneau détail d'une vente
// ----------------------------------------------------------------------------

const SALE_SELECT = '*, seller:organizations!seller_organization_id(name)';

function SaleDetailPanel({
  sale: initialSale,
  onClose,
  onChanged,
}: {
  sale: CreditSale;
  onClose: () => void;
  onChanged: () => void;
}) {
  const [sale, setSale] = useState<CreditSale>(initialSale);
  const [lots, setLots] = useState<CreditSaleLotRow[]>([]);
  const [costs, setCosts] = useState<CreditSaleCost[]>([]);
  const [allocations, setAllocations] = useState<CreditSaleAllocation[]>([]);
  const [loading, setLoading] = useState(true);
  const [listError, setListError] = useState('');
  const [showAddLot, setShowAddLot] = useState(false);
  const [showAddCost, setShowAddCost] = useState(false);
  const [activeAction, setActiveAction] = useState<ActionKind | null>(null);
  const [releaseTarget, setReleaseTarget] = useState<CreditSaleLotRow | null>(null);
  const [releaseReason, setReleaseReason] = useState('');
  const [releaseError, setReleaseError] = useState('');
  const [releaseSaving, setReleaseSaving] = useState(false);
  const [banner, setBanner] = useState('');

  const fetchDetail = useCallback(async () => {
    setLoading(true);
    setListError('');
    const supabase = createClient();
    const [saleRes, lotRes, costRes, allocRes] = await Promise.all([
      supabase.from('credit_sales').select(SALE_SELECT).eq('id', sale.id).single(),
      supabase.from('credit_sale_lots').select('*, credit_lots(vintage_year, aggregator_id, aggregators(name))').eq('credit_sale_id', sale.id).order('created_at', { ascending: false }),
      supabase.from('credit_sale_costs').select('*').eq('credit_sale_id', sale.id).order('created_at', { ascending: false }),
      supabase.from('credit_sale_allocations').select('*, organizations(name)').eq('credit_sale_id', sale.id).order('created_at', { ascending: true }),
    ]);
    const errors = [saleRes.error, lotRes.error, costRes.error, allocRes.error].filter(Boolean);
    if (errors.length > 0) {
      setListError(errors.map((e) => getErrorMessage(e)).join(' · '));
      setLoading(false);
      return;
    }
    if (saleRes.data) setSale(saleRes.data as unknown as CreditSale);
    setLots((lotRes.data ?? []) as unknown as CreditSaleLotRow[]);
    setCosts((costRes.data ?? []) as CreditSaleCost[]);
    setAllocations((allocRes.data ?? []) as unknown as CreditSaleAllocation[]);
    setLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sale.id]);

  useEffect(() => { fetchDetail(); }, [fetchDetail]);

  const refreshAll = () => { fetchDetail(); onChanged(); };

  const runRpc = async (name: string, params: Record<string, unknown>): Promise<string | null> => {
    const supabase = createClient();
    const { error } = await supabase.rpc(name, params);
    if (error) return getErrorMessage(error);
    setBanner('Action effectuée.');
    refreshAll();
    return null;
  };

  const handleAction = async (kind: ActionKind, value: string): Promise<string | null> => {
    if (kind === 'settle') return runRpc('settle_credit_sale', { p_credit_sale_id: sale.id, p_settlement_reference: value });
    return runRpc('cancel_credit_sale', { p_credit_sale_id: sale.id, p_reason: value });
  };

  const handleConfirm = async () => {
    setBanner('');
    const supabase = createClient();
    const { error } = await supabase.rpc('confirm_credit_sale', { p_credit_sale_id: sale.id });
    if (error) { setListError(getErrorMessage(error)); return; }
    setBanner('Vente confirmée.');
    refreshAll();
  };

  const handleReleaseLot = async () => {
    setReleaseError('');
    if (!releaseReason.trim()) { setReleaseError('Motif requis.'); return; }
    if (!releaseTarget) return;
    setReleaseSaving(true);
    const supabase = createClient();
    const { error } = await supabase.rpc('release_credit_sale_lot', {
      p_credit_sale_lot_id: releaseTarget.id,
      p_reason: releaseReason.trim(),
    });
    setReleaseSaving(false);
    if (error) { setReleaseError(getErrorMessage(error)); return; }
    setReleaseTarget(null);
    setReleaseReason('');
    refreshAll();
  };

  const activeLots = lots.filter((l) => !l.released_at);
  const status = sale.status;
  const canAddLot = status === 'draft';
  const canReleaseLot = status === 'draft';
  const canAddCost = status === 'draft';
  const canConfirm = status === 'draft' && activeLots.length > 0;
  const canCancel = status === 'draft';
  const canSettle = status === 'confirmed';

  const totalCosts = costs.reduce((s, c) => s + Number(c.amount), 0);

  return (
    <div className="fixed inset-0 z-40 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative w-full max-w-lg h-full bg-card border-l border-border shadow-2xl overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <div>
            <h2 className="text-lg font-700 text-foreground">Vente</h2>
            <p className="text-xs text-muted-foreground font-mono">{sale.id}</p>
          </div>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>

        <div className="p-5 space-y-5">
          <ErrorBanner message={listError} />

          <div className="flex items-center gap-2">
            <Badge config={SALE_STATUS_CONFIG} value={sale.status} />
            <span className="text-sm text-muted-foreground">Créée le {fmtDateTime(sale.created_at)}</span>
          </div>

          <div className="grid grid-cols-2 gap-3 text-sm">
            <div><p className="text-muted-foreground text-xs">Vendeur</p><p className="font-600 text-foreground">{sale.seller?.name ?? sale.seller_organization_id}</p></div>
            <div><p className="text-muted-foreground text-xs">Référence acheteur</p><p className="font-600 text-foreground">{sale.buyer_reference ?? '—'}</p></div>
            <div><p className="text-muted-foreground text-xs">Prix / tCO2e</p><p className="font-600 text-foreground">{fmtMoney(sale.price_per_tco2e)}</p></div>
            <div><p className="text-muted-foreground text-xs">Total tCO2e (lots actifs)</p><p className="font-600 text-foreground">{fmtNum(sale.total_tco2e)}</p></div>
            <div><p className="text-muted-foreground text-xs">Montant brut</p><p className="font-600 text-foreground">{fmtMoney(sale.gross_amount)}</p></div>
            <div><p className="text-muted-foreground text-xs">Net distribuable</p><p className="font-600 text-foreground">{fmtMoney(sale.net_distributable_amount)}</p></div>
          </div>

          {sale.settlement_reference && (
            <div className="bg-muted rounded-lg p-3 text-sm">
              <p className="font-600 text-foreground">Réglée</p>
              <p className="text-muted-foreground">Référence : {sale.settlement_reference} · le {fmtDateTime(sale.settled_at)}</p>
            </div>
          )}
          {sale.cancel_reason && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700">Motif d&apos;annulation : {sale.cancel_reason}</div>
          )}

          {banner && <div className="bg-green-50 border border-green-200 rounded-lg p-2 text-sm text-green-700">{banner}</div>}

          {/* Actions selon statut */}
          <div className="flex flex-wrap gap-2">
            {canAddLot && <button onClick={() => setShowAddLot(true)} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Ajouter un lot</button>}
            {canAddCost && <button onClick={() => setShowAddCost(true)} className="btn-ghost px-3 py-2 rounded-lg text-sm font-600">Ajouter un coût</button>}
            {canConfirm && <button onClick={handleConfirm} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Confirmer la vente</button>}
            {canSettle && <button onClick={() => setActiveAction('settle')} className="btn-primary px-3 py-2 rounded-lg text-sm font-600">Régler</button>}
            {canCancel && <button onClick={() => setActiveAction('cancel')} className="btn-ghost px-3 py-2 rounded-lg text-sm font-600 text-red-700">Annuler la vente</button>}
          </div>
          {status === 'draft' && activeLots.length === 0 && (
            <p className="text-xs text-muted-foreground">Ajouter au moins un lot actif pour pouvoir confirmer.</p>
          )}

          {/* Lots */}
          <div>
            <p className="text-sm font-600 text-foreground mb-2">Lots</p>
            {loading ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : lots.length === 0 ? (
              <p className="text-sm text-muted-foreground">Aucun lot rattaché.</p>
            ) : (
              <div className="border border-border rounded-lg divide-y divide-border">
                {lots.map((l) => (
                  <div key={l.id} className="flex items-center justify-between px-3 py-2 text-sm gap-2">
                    <div>
                      <p className="text-foreground font-500">
                        {fmtNum(l.quantity_tco2e)} tCO2e · millésime {l.credit_lots?.vintage_year ?? '—'} · {l.credit_lots?.aggregators?.name ?? l.credit_lots?.aggregator_id ?? '—'}
                      </p>
                      {l.released_at ? (
                        <p className="text-xs text-muted-foreground">Libéré le {fmtDateTime(l.released_at)} — {l.release_reason}</p>
                      ) : (
                        <p className="text-xs text-muted-foreground font-mono">{l.credit_lot_id.slice(0, 8)}…</p>
                      )}
                    </div>
                    {!l.released_at && canReleaseLot && (
                      <button onClick={() => setReleaseTarget(l)} className="btn-ghost p-1.5 rounded text-red-700" title="Libérer ce lot">
                        <Icon name="ArrowUturnLeftIcon" size={14} />
                      </button>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Coûts */}
          <div>
            <p className="text-sm font-600 text-foreground mb-2">Coûts</p>
            {loading ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : costs.length === 0 ? (
              <p className="text-sm text-muted-foreground">Aucun coût déclaré.</p>
            ) : (
              <div className="border border-border rounded-lg divide-y divide-border">
                {costs.map((c) => (
                  <div key={c.id} className="flex items-center justify-between px-3 py-2 text-sm">
                    <div>
                      <p className="text-foreground font-500">{COST_TYPE_LABELS[c.cost_type] ?? c.cost_type}</p>
                      {c.description && <p className="text-xs text-muted-foreground">{c.description}</p>}
                      {c.beneficiary && <p className="text-xs text-muted-foreground">Bénéficiaire : {c.beneficiary}</p>}
                    </div>
                    <span className="text-muted-foreground">{fmtMoney(c.amount)}</span>
                  </div>
                ))}
                <div className="flex items-center justify-between px-3 py-2 text-sm bg-muted">
                  <span className="font-600 text-foreground">Total coûts</span>
                  <span className="font-700 text-foreground">{fmtMoney(totalCosts)}</span>
                </div>
              </div>
            )}
          </div>

          {/* Allocations (calculées serveur, lecture seule) */}
          <div>
            <p className="text-sm font-600 text-foreground mb-2">Répartition (calculée à la confirmation)</p>
            {loading ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : allocations.length === 0 ? (
              <p className="text-sm text-muted-foreground">Aucune répartition — générée automatiquement par le serveur à la confirmation.</p>
            ) : (
              <div className="border border-border rounded-lg divide-y divide-border">
                {allocations.map((a) => (
                  <div key={a.id} className="px-3 py-2 text-sm">
                    <div className="flex items-center justify-between">
                      <span className="text-foreground font-500">
                        {a.allocation_type === 'carbon_revenue' ? (a.organizations?.name ?? a.organization_id) : ALLOCATION_TYPE_LABELS[a.allocation_type]}
                      </span>
                      <span className="text-foreground font-600">{fmtMoney(a.net_amount)}</span>
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {ALLOCATION_TYPE_LABELS[a.allocation_type] ?? a.allocation_type}
                      {a.allocated_tco2e !== null ? ` · ${fmtNum(a.allocated_tco2e)} tCO2e` : ''}
                      {' · brut '}{fmtMoney(a.gross_amount)}
                      {' · frais '}{fmtMoney(a.fee_amount)}
                      {' · réserve '}{fmtMoney(a.reserve_amount)}
                    </p>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
      </div>

      {showAddLot && <AddLotModal saleId={sale.id} onClose={() => setShowAddLot(false)} onAdded={refreshAll} />}
      {showAddCost && <AddCostModal saleId={sale.id} onClose={() => setShowAddCost(false)} onAdded={refreshAll} />}
      {activeAction && (
        <ActionModal kind={activeAction} onClose={() => setActiveAction(null)} onConfirm={(v) => handleAction(activeAction, v)} />
      )}
      {releaseTarget && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
          <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
            <div className="flex items-center justify-between p-5 border-b border-border">
              <h2 className="text-lg font-700 text-foreground">Libérer le lot</h2>
              <button onClick={() => setReleaseTarget(null)} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
            </div>
            <div className="p-5 space-y-4">
              <div>
                <label className="block text-sm font-600 text-foreground mb-1">Motif *</label>
                <input className="input w-full" type="text" value={releaseReason} onChange={(e) => setReleaseReason(e.target.value)} />
              </div>
              {releaseError && <p className="text-sm text-red-600">{releaseError}</p>}
              <div className="flex gap-3 pt-2">
                <button type="button" onClick={() => setReleaseTarget(null)} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Fermer</button>
                <button type="button" disabled={releaseSaving} onClick={handleReleaseLot} className="flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50 bg-red-600 text-white hover:bg-red-700">
                  {releaseSaving ? 'Traitement…' : 'Libérer'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ----------------------------------------------------------------------------
// Page principale
// ----------------------------------------------------------------------------

export default function AdminCarbonSalesPage() {
  const [operatorOrgId, setOperatorOrgId] = useState<string | null>(null);
  const [operatorOrgName, setOperatorOrgName] = useState<string>('');
  const [sales, setSales] = useState<CreditSale[]>([]);
  const [loading, setLoading] = useState(true);
  const [listError, setListError] = useState('');
  const [selectedSale, setSelectedSale] = useState<CreditSale | null>(null);
  const [statusFilter, setStatusFilter] = useState<string>('all');
  const [showNewSale, setShowNewSale] = useState(false);
  // UX guard uniquement — create_credit_sale() reste seule autorité réelle
  // (is_org_admin(seller_organization_id)) ; ce flag évite simplement
  // d'afficher un bouton qui échouerait pour un rôle non-admin de
  // l'organisation opératrice (ex. vérificateur).
  const [isOperatorAdmin, setIsOperatorAdmin] = useState(false);

  const fetchAll = useCallback(async () => {
    setLoading(true);
    setListError('');
    const supabase = createClient();
    const [opRes, salesRes, sessionRes] = await Promise.all([
      supabase.from('platform_operators').select('organization_id, organizations(name)').is('revoked_at', null).maybeSingle(),
      supabase.from('credit_sales').select(SALE_SELECT).order('created_at', { ascending: false }),
      supabase.auth.getSession(),
    ]);
    const errors = [opRes.error, salesRes.error].filter(Boolean);
    if (errors.length > 0) {
      setListError(errors.map((e) => getErrorMessage(e)).join(' · '));
      setLoading(false);
      return;
    }
    const opOrgId = opRes.data?.organization_id ?? null;
    setOperatorOrgId(opOrgId);
    setOperatorOrgName((opRes.data as any)?.organizations?.name ?? opRes.data?.organization_id ?? '');
    setSales((salesRes.data ?? []) as unknown as CreditSale[]);

    const uid = sessionRes.data.session?.user?.id ?? null;
    const superadmin = sessionRes.data.session?.user?.app_metadata?.role === 'admin';
    if (opOrgId && uid) {
      const { data: opAdmin } = await supabase
        .from('organization_members')
        .select('id')
        .eq('organization_id', opOrgId)
        .eq('user_id', uid)
        .eq('org_role', 'admin')
        .eq('status', 'active')
        .maybeSingle();
      setIsOperatorAdmin(!!opAdmin || superadmin);
    } else {
      setIsOperatorAdmin(superadmin);
    }

    setLoading(false);
  }, []);

  useEffect(() => { fetchAll(); }, [fetchAll]);

  const filteredSales = statusFilter === 'all' ? sales : sales.filter((s) => s.status === statusFilter);
  const totalGrossConfirmed = sales.filter((s) => s.status === 'confirmed' || s.status === 'settled').reduce((s, x) => s + Number(x.gross_amount ?? 0), 0);
  const totalNetSettled = sales.filter((s) => s.status === 'settled').reduce((s, x) => s + Number(x.net_distributable_amount ?? 0), 0);
  const draftCount = sales.filter((s) => s.status === 'draft').length;

  return (
    <AppLayout activeRoute="/admin">
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Cockpit de ventes</h1>
            <p className="text-sm text-muted-foreground mt-1">Ventes de crédits carbone → coûts → confirmation → répartition → règlement</p>
          </div>
          {operatorOrgId && isOperatorAdmin && (
            <button onClick={() => setShowNewSale(true)} className="btn-primary px-4 py-2 rounded-lg text-sm font-600 flex items-center gap-2">
              <Icon name="PlusIcon" size={16} />
              Nouvelle vente
            </button>
          )}
        </div>

        <ErrorBanner message={listError} />

        {!loading && !listError && !operatorOrgId && (
          <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700 mb-6">
            Aucun opérateur METALTRACE actif désigné — impossible de créer une vente.
          </div>
        )}

        {/* KPI row */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          <div className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center text-slate-600"><Icon name="DocumentIcon" size={20} /></div>
            <div><p className="text-2xl font-700 text-foreground">{draftCount}</p><p className="text-xs text-muted-foreground">ventes en brouillon</p></div>
          </div>
          <div className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center text-blue-600"><Icon name="BanknotesIcon" size={20} /></div>
            <div><p className="text-2xl font-700 text-foreground">{fmtMoney(totalGrossConfirmed)}</p><p className="text-xs text-muted-foreground">brut confirmé (confirmed + settled)</p></div>
          </div>
          <div className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center text-green-600"><Icon name="CheckBadgeIcon" size={20} /></div>
            <div><p className="text-2xl font-700 text-foreground">{fmtMoney(totalNetSettled)}</p><p className="text-xs text-muted-foreground">net distribuable réglé</p></div>
          </div>
        </div>

        <div className="flex gap-2 mb-4 flex-wrap">
          {['all', ...Object.keys(SALE_STATUS_CONFIG)].map((s) => (
            <button key={s} onClick={() => setStatusFilter(s)} className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${statusFilter === s ? 'bg-primary text-primary-foreground border-primary' : 'bg-card text-muted-foreground border-border hover:border-primary/50'}`}>
              {s === 'all' ? 'Toutes' : SALE_STATUS_CONFIG[s]?.label ?? s}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="space-y-3">{[1, 2, 3].map((i) => <div key={i} className="h-20 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : filteredSales.length === 0 ? (
          <div className="bg-card border border-border rounded-xl p-12 text-center">
            <Icon name="BanknotesIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground font-500">Aucune vente</p>
          </div>
        ) : (
          <div className="space-y-3">
            {filteredSales.map((s) => (
              <button key={s.id} onClick={() => setSelectedSale(s)} className="w-full text-left bg-card border border-border rounded-xl p-5 hover:border-primary/50 transition-all group">
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-3 mb-1">
                      <p className="font-700 text-foreground group-hover:text-primary transition-colors">{fmtNum(s.total_tco2e)} tCO2e · {fmtMoney(s.price_per_tco2e)}/tCO2e</p>
                      <Badge config={SALE_STATUS_CONFIG} value={s.status} />
                    </div>
                    <p className="text-sm text-muted-foreground">
                      {s.seller?.name ?? s.seller_organization_id}{s.buyer_reference ? ` · Acheteur : ${s.buyer_reference}` : ''}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1">Créée le {fmtDateTime(s.created_at)} · Date de vente : {fmtDate(s.sale_date)}</p>
                  </div>
                  <Icon name="ChevronRightIcon" size={18} className="text-muted-foreground group-hover:text-primary transition-colors flex-shrink-0 mt-1" />
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {showNewSale && operatorOrgId && isOperatorAdmin && (
        <NewSaleModal operatorOrgId={operatorOrgId} operatorOrgName={operatorOrgName} onClose={() => setShowNewSale(false)} onCreated={fetchAll} />
      )}
      {selectedSale && (
        <SaleDetailPanel sale={selectedSale} onClose={() => setSelectedSale(null)} onChanged={fetchAll} />
      )}
    </div>
    </AppLayout>
  );
}
