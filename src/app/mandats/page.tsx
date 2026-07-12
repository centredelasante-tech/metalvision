'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

type MandateStatus = 'draft' | 'pending_acceptance' | 'active' | 'expired' | 'revoked';
type MandateScope = 'gouvernance' | 'operationnel' | 'financier' | 'technique' | 'verification' | 'ia';

interface Organization {
  id: string;
  name: string;
}

interface Mandate {
  id: string;
  issuer_org_id: string;
  receiver_org_id: string;
  mandate_scope: MandateScope;
  permissions: { actions: string[] };
  start_date: string | null;
  end_date: string | null;
  status: MandateStatus;
  created_at: string;
  updated_at: string;
  issuer_org?: { name: string } | null;
  receiver_org?: { name: string } | null;
}

interface MandateAction {
  code: string;
  label: string;
}

interface OrgMembership {
  organization_id: string;
  org_role: string;
  status: string;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const STATUS_CONFIG: Record<MandateStatus, { label: string; cls: string; icon: string }> = {
  draft:              { label: 'Brouillon',         cls: 'text-gray-600 bg-gray-100 border-gray-200',      icon: 'DocumentIcon' },
  pending_acceptance: { label: 'En attente',        cls: 'text-amber-700 bg-amber-50 border-amber-200',    icon: 'ClockIcon' },
  active:             { label: 'Actif',             cls: 'text-green-700 bg-green-50 border-green-200',    icon: 'CheckCircleIcon' },
  expired:            { label: 'Expiré',            cls: 'text-slate-500 bg-slate-100 border-slate-200',   icon: 'XCircleIcon' },
  revoked:            { label: 'Révoqué',           cls: 'text-red-600 bg-red-50 border-red-200',          icon: 'XMarkIcon' },
};

const SCOPE_LABELS: Record<MandateScope, string> = {
  gouvernance:  'Gouvernance',
  operationnel: 'Opérationnel',
  financier:    'Financier',
  technique:    'Technique',
  verification: 'Vérification',
  ia:           'IA',
};

const SCOPE_OPTIONS: MandateScope[] = ['gouvernance', 'operationnel', 'financier', 'technique', 'verification', 'ia'];

// ─── Sub-components ───────────────────────────────────────────────────────────

function MandateStatusBadge({ status }: { status: MandateStatus }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.draft;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2.5 py-1 border ${cfg.cls}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {cfg.label}
    </span>
  );
}

function ActionPicker({
  available,
  selected,
  onChange,
  disabled = false,
}: {
  available: MandateAction[];
  selected: string[];
  onChange: (codes: string[]) => void;
  disabled?: boolean;
}) {
  const toggle = (code: string) => {
    if (disabled) return;
    onChange(selected.includes(code) ? selected.filter((c) => c !== code) : [...selected, code]);
  };
  return (
    <div className="grid grid-cols-1 gap-1.5">
      {available.map((a) => (
        <label
          key={a.code}
          className={`flex items-center gap-2.5 px-3 py-2 rounded-lg border text-sm transition-colors ${
            disabled ? 'opacity-60 cursor-not-allowed' : 'cursor-pointer'
          } ${
            selected.includes(a.code)
              ? 'border-primary bg-primary/5 text-primary font-medium' :'border-border bg-card text-foreground hover:bg-muted'
          }`}
        >
          <input
            type="checkbox"
            className="sr-only"
            checked={selected.includes(a.code)}
            onChange={() => toggle(a.code)}
            disabled={disabled}
          />
          <span
            className={`w-4 h-4 rounded border flex items-center justify-center flex-shrink-0 ${
              selected.includes(a.code) ? 'bg-primary border-primary' : 'border-border'
            }`}
          >
            {selected.includes(a.code) && (
              <Icon name="CheckIcon" size={10} className="text-primary-foreground" />
            )}
          </span>
          <span className="truncate">{a.label}</span>
        </label>
      ))}
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function MandatsPage() {
  const supabase = createClient();
  const router = useRouter();

  // State
  const [mandates, setMandates] = useState<Mandate[]>([]);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [mandateActions, setMandateActions] = useState<MandateAction[]>([]);
  const [myOrgMemberships, setMyOrgMemberships] = useState<OrgMembership[]>([]);
  const [myOrgIds, setMyOrgIds] = useState<string[]>([]);
  const [myAdminOrgIds, setMyAdminOrgIds] = useState<string[]>([]);

  // MVP-DA-019: map of mandate_id → project_id (null = standalone, string = project-linked)
  const [mandateProjectMap, setMandateProjectMap] = useState<Record<string, string | null>>({});

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Filter
  const [filterStatus, setFilterStatus] = useState<MandateStatus | 'all'>('all');
  const [filterRole, setFilterRole] = useState<'all' | 'issuer' | 'receiver'>('all');

  // Selected mandate for detail
  const [selectedMandate, setSelectedMandate] = useState<Mandate | null>(null);

  // Create form
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [form, setForm] = useState({
    receiver_org_id: '',
    mandate_scope: 'operationnel' as MandateScope,
    actions: [] as string[],
    start_date: '',
    end_date: '',
    issuer_org_id: '',
  });
  const [formError, setFormError] = useState<string | null>(null);
  const [formLoading, setFormLoading] = useState(false);

  // ─── Data loading ──────────────────────────────────────────────────────────

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setError('Non authentifié'); setLoading(false); return; }

      // Load memberships
      const { data: memberships } = await supabase
        .from('organization_members')
        .select('organization_id, org_role, status')
        .eq('user_id', user.id)
        .eq('status', 'active');

      const mems: OrgMembership[] = memberships ?? [];
      setMyOrgMemberships(mems);
      const orgIds = mems.map((m) => m.organization_id);
      const adminIds = mems.filter((m) => m.org_role === 'admin' || m.org_role === 'owner').map((m) => m.organization_id);
      setMyOrgIds(orgIds);
      setMyAdminOrgIds(adminIds);

      // Load mandates (RLS already filters to orgs the user belongs to)
      const { data: mandatesData, error: mandatesErr } = await supabase
        .from('mandates')
        .select(`
          *,
          issuer_org:organizations!mandates_issuer_org_id_fkey(name),
          receiver_org:organizations!mandates_receiver_org_id_fkey(name)
        `)
        .order('created_at', { ascending: false });

      if (mandatesErr) throw mandatesErr;
      const loadedMandates = (mandatesData ?? []) as Mandate[];
      setMandates(loadedMandates);

      // MVP-DA-019: For all pending_acceptance mandates, resolve project linkage
      // Query project_participants to determine if mandate is project-linked or standalone
      const pendingIds = loadedMandates
        .filter((m) => m.status === 'pending_acceptance')
        .map((m) => m.id);

      const projectMap: Record<string, string | null> = {};
      if (pendingIds.length > 0) {
        const { data: ppRows } = await supabase
          .from('project_participants')
          .select('mandate_id, project_id')
          .in('mandate_id', pendingIds);

        // Build map: mandate_id → project_id (first match)
        for (const row of ppRows ?? []) {
          if (row.mandate_id && row.project_id) {
            projectMap[row.mandate_id] = row.project_id;
          }
        }
        // Mandates not found in project_participants are standalone (null)
        for (const id of pendingIds) {
          if (!(id in projectMap)) {
            projectMap[id] = null;
          }
        }
      }
      setMandateProjectMap(projectMap);

      // Load organizations (for create form)
      const { data: orgsData } = await supabase
        .from('organizations')
        .select('id, name')
        .order('name');
      setOrganizations(orgsData ?? []);

      // Load mandate actions catalogue
      const { data: actionsData } = await supabase
        .from('mandate_actions')
        .select('code, label')
        .order('code');
      setMandateActions(actionsData ?? []);

    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur de chargement');
    } finally {
      setLoading(false);
    }
  }, [supabase]);

  useEffect(() => { loadData(); }, [loadData]);

  // ─── Helpers ───────────────────────────────────────────────────────────────

  // MVP-DA-017: is_mandate_effective — active AND not past end_date
  const isEffective = (m: Mandate) =>
    m.status === 'active' && (!m.end_date || new Date(m.end_date) >= new Date());

  const canIssue = (m: Mandate) => myAdminOrgIds.includes(m.issuer_org_id);
  const canReceive = (m: Mandate) => myAdminOrgIds.includes(m.receiver_org_id);

  // MVP-DA-019: resolve accept button type for a pending mandate
  // Returns 'project' if linked to a project, 'standalone' if generic, 'loading' if not yet resolved
  const getAcceptType = (mandateId: string): 'project' | 'standalone' | 'loading' => {
    if (!(mandateId in mandateProjectMap)) return 'loading';
    return mandateProjectMap[mandateId] !== null ? 'project' : 'standalone';
  };

  // ─── Actions ───────────────────────────────────────────────────────────────

  const handleSend = async (mandate: Mandate) => {
    setActionLoading(mandate.id);
    try {
      const { error: err } = await supabase
        .from('mandates')
        .update({ status: 'pending_acceptance', updated_at: new Date().toISOString() })
        .eq('id', mandate.id);
      if (err) throw err;

      const { data: { user } } = await supabase.auth.getUser();
      await supabase.from('business_events').insert({
        event_type: 'mandate_issued',
        object_type: 'mandate',
        object_id: mandate.id,
        actor_id: user?.id,
        organization_id: mandate.issuer_org_id,
        payload: { mandate_id: mandate.id, scope: mandate.mandate_scope },
      });

      await loadData();
      setSelectedMandate(null);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur lors de l\'envoi');
    } finally {
      setActionLoading(null);
    }
  };

  // MVP-DA-019: Navigate to project screen for project-linked mandates
  const handleNavigateToProject = (mandateId: string) => {
    const projectId = mandateProjectMap[mandateId];
    if (projectId) {
      router.push(`/projets/${projectId}`);
    }
  };

  // MVP-DA-019: Accept standalone mandate (no project linkage) via accept_mandate RPC
  const handleAcceptStandalone = async (mandate: Mandate) => {
    setActionLoading(mandate.id);
    try {
      const { error: err } = await supabase.rpc('accept_mandate', {
        p_mandate_id: mandate.id,
      });
      if (err) throw err;

      // INC-S06-06 : accept_mandate() insere deja l'evenement business_events
      // cote serveur (voir supabase/migrations/20260712075446_accept_mandate_rpc.sql,
      // ligne 35). L'insertion manuelle ici causait un doublon en base -- retiree.

      await loadData();
      setSelectedMandate(null);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur lors de l\'acceptation');
    } finally {
      setActionLoading(null);
    }
  };

  const handleDecline = async (mandate: Mandate) => {
    setActionLoading(mandate.id);
    try {
      const { error: err } = await supabase.rpc('decline_project_invitation', {
        p_mandate_id: mandate.id,
      });
      if (err) throw err;

      await loadData();
      setSelectedMandate(null);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur lors du refus');
    } finally {
      setActionLoading(null);
    }
  };

  const handleRevoke = async (mandate: Mandate) => {
    if (!confirm('Révoquer ce mandat ? Cette action est irréversible.')) return;
    setActionLoading(mandate.id);
    try {
      const { error: err } = await supabase
        .from('mandates')
        .update({ status: 'revoked', updated_at: new Date().toISOString() })
        .eq('id', mandate.id);
      if (err) throw err;

      const { data: { user } } = await supabase.auth.getUser();
      await supabase.from('business_events').insert({
        event_type: 'mandate_revoked',
        object_type: 'mandate',
        object_id: mandate.id,
        actor_id: user?.id,
        organization_id: mandate.issuer_org_id,
        payload: { mandate_id: mandate.id, reason: 'revoked_by_issuer' },
      });

      await loadData();
      setSelectedMandate(null);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Erreur lors de la révocation');
    } finally {
      setActionLoading(null);
    }
  };

  // ─── Create form ───────────────────────────────────────────────────────────

  const handleCreate = async (e: React.FormEvent) => {
    e.preventDefault();
    setFormError(null);

    if (!form.issuer_org_id) { setFormError('Sélectionnez l\'organisation émettrice'); return; }
    if (!form.receiver_org_id) { setFormError('Sélectionnez l\'organisation réceptrice'); return; }
    if (form.issuer_org_id === form.receiver_org_id) { setFormError('L\'émetteur et le récepteur doivent être différents (MVP-RA-028)'); return; }
    if (form.actions.length === 0) { setFormError('Sélectionnez au moins une action autorisée — le mandat ne peut pas avoir un tableau d\'actions vide'); return; }

    setFormLoading(true);
    try {
      const { error: err } = await supabase.from('mandates').insert({
        issuer_org_id: form.issuer_org_id,
        receiver_org_id: form.receiver_org_id,
        mandate_scope: form.mandate_scope,
        permissions: { actions: form.actions },
        start_date: form.start_date || null,
        end_date: form.end_date || null,
        // status intentionally omitted — server forces 'draft' (never sent by client)
      });
      if (err) throw err;

      setShowCreateForm(false);
      setForm({ receiver_org_id: '', mandate_scope: 'operationnel', actions: [], start_date: '', end_date: '', issuer_org_id: '' });
      await loadData();
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : 'Erreur lors de la création';
      // Surface readable error instead of raw SQL
      if (msg.includes('mandate_actions') || msg.includes('permissions')) {
        setFormError('Actions invalides — utilisez uniquement les actions du catalogue autorisé');
      } else {
        setFormError(msg);
      }
    } finally {
      setFormLoading(false);
    }
  };

  // ─── Filtered mandates ─────────────────────────────────────────────────────

  const filtered = mandates.filter((m) => {
    if (filterStatus !== 'all' && m.status !== filterStatus) return false;
    if (filterRole === 'issuer' && !myOrgIds.includes(m.issuer_org_id)) return false;
    if (filterRole === 'receiver' && !myOrgIds.includes(m.receiver_org_id)) return false;
    return true;
  });

  // ─── Accept/Decline buttons (MVP-DA-019) ──────────────────────────────────

  function AcceptDeclineButtons({
    mandate,
    size = 'sm',
  }: {
    mandate: Mandate;
    size?: 'sm' | 'lg';
  }) {
    if (!canReceive(mandate)) return null;
    const acceptType = getAcceptType(mandate.id);
    const isLoading = actionLoading === mandate.id;
    const px = size === 'lg' ? 'px-4 py-2.5' : 'px-2.5 py-1.5';
    const textSize = size === 'lg' ? 'text-sm' : 'text-xs';
    const iconSize = size === 'lg' ? 16 : 12;

    return (
      <div className={`flex ${size === 'lg' ? 'gap-2' : 'gap-1.5'}`}>
        {/* Branch A (MVP-DA-019): project-linked → navigate to project screen */}
        {acceptType === 'project' && (
          <button
            onClick={() => handleNavigateToProject(mandate.id)}
            disabled={isLoading}
            className={`flex items-center gap-1 ${px} bg-blue-600 text-white rounded-${size === 'lg' ? 'lg' : 'md'} ${textSize} font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors ${size === 'lg' ? 'flex-1 justify-center' : ''}`}
            title="Ce mandat est lié à une invitation de projet — accepter depuis l'écran projet"
          >
            <Icon name="FolderOpenIcon" size={iconSize} />
            {size === 'lg' ? 'Voir le projet' : 'Voir projet'}
          </button>
        )}

        {/* Branch B (MVP-DA-019): standalone mandate → call accept_mandate RPC */}
        {acceptType === 'standalone' && (
          <button
            onClick={() => handleAcceptStandalone(mandate)}
            disabled={isLoading}
            className={`flex items-center gap-1 ${px} bg-green-600 text-white rounded-${size === 'lg' ? 'lg' : 'md'} ${textSize} font-medium hover:bg-green-700 disabled:opacity-50 transition-colors ${size === 'lg' ? 'flex-1 justify-center' : ''}`}
          >
            {isLoading ? (
              <div className={`${size === 'lg' ? 'w-4 h-4 border-2' : 'w-3 h-3 border'} border-white border-t-transparent rounded-full animate-spin`} />
            ) : (
              <Icon name="CheckIcon" size={iconSize} />
            )}
            Accepter
          </button>
        )}

        {/* Loading state while resolving project linkage */}
        {acceptType === 'loading' && (
          <div className={`flex items-center gap-1 ${px} bg-muted rounded-${size === 'lg' ? 'lg' : 'md'} ${textSize} text-muted-foreground`}>
            <div className="w-3 h-3 border border-muted-foreground border-t-transparent rounded-full animate-spin" />
            <span>…</span>
          </div>
        )}

        {/* Decline button — shown in both branches */}
        <button
          onClick={() => handleDecline(mandate)}
          disabled={isLoading}
          className={`flex items-center gap-1 ${px} bg-red-100 text-red-700 rounded-${size === 'lg' ? 'lg' : 'md'} ${textSize} font-medium hover:bg-red-200 disabled:opacity-50 transition-colors ${size === 'lg' ? 'flex-1 justify-center' : ''}`}
        >
          <Icon name="XMarkIcon" size={iconSize} />
          Refuser
        </button>
      </div>
    );
  }

  // ─── Render ────────────────────────────────────────────────────────────────

  return (
    <AppLayout>
      <div className="flex flex-col h-full min-h-0">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border bg-card flex-shrink-0">
          <div>
            <h1 className="text-xl font-bold text-foreground">Mandats</h1>
            <p className="text-sm text-muted-foreground mt-0.5">
              Délégations d'autorité entre organisations
            </p>
          </div>
          {/* Hide create button for non-admins (UI guard — RLS is the real gate) */}
          {myAdminOrgIds.length > 0 && (
            <button
              onClick={() => setShowCreateForm(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
            >
              <Icon name="PlusIcon" size={16} />
              Nouveau mandat
            </button>
          )}
        </div>

        {/* Error banner */}
        {error && (
          <div className="mx-6 mt-4 flex items-center gap-2 px-4 py-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm flex-shrink-0">
            <Icon name="ExclamationCircleIcon" size={16} />
            <span>{error}</span>
            <button onClick={() => setError(null)} className="ml-auto">
              <Icon name="XMarkIcon" size={14} />
            </button>
          </div>
        )}

        {/* Filters */}
        <div className="flex items-center gap-3 px-6 py-3 border-b border-border bg-muted/30 flex-shrink-0 flex-wrap">
          <div className="flex items-center gap-1.5">
            <span className="text-xs text-muted-foreground font-medium">Statut :</span>
            {(['all', 'draft', 'pending_acceptance', 'active', 'expired', 'revoked'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setFilterStatus(s)}
                className={`px-2.5 py-1 rounded-full text-xs font-medium transition-colors ${
                  filterStatus === s
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-card border border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                {s === 'all' ? 'Tous' : STATUS_CONFIG[s as MandateStatus]?.label ?? s}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-1.5 ml-auto">
            <span className="text-xs text-muted-foreground font-medium">Rôle :</span>
            {(['all', 'issuer', 'receiver'] as const).map((r) => (
              <button
                key={r}
                onClick={() => setFilterRole(r)}
                className={`px-2.5 py-1 rounded-full text-xs font-medium transition-colors ${
                  filterRole === r
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-card border border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                {r === 'all' ? 'Tous' : r === 'issuer' ? 'Émis' : 'Reçus'}
              </button>
            ))}
          </div>
        </div>

        {/* Content */}
        <div className="flex flex-1 min-h-0 overflow-hidden">
          {/* List */}
          <div className={`flex flex-col overflow-y-auto ${selectedMandate ? 'w-1/2 border-r border-border' : 'w-full'}`}>
            {loading ? (
              <div className="flex items-center justify-center py-16">
                <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 text-center px-6">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mb-3">
                  <Icon name="DocumentTextIcon" size={24} className="text-muted-foreground" />
                </div>
                <p className="text-sm font-medium text-foreground">Aucun mandat</p>
                <p className="text-xs text-muted-foreground mt-1">
                  {filterStatus !== 'all' || filterRole !== 'all' ?'Aucun mandat ne correspond aux filtres sélectionnés.' :'Créez votre premier mandat pour déléguer des autorisations.'}
                </p>
              </div>
            ) : (
              <div className="divide-y divide-border">
                {filtered.map((m) => {
                  const isIssuer = myOrgIds.includes(m.issuer_org_id);
                  const isReceiver = myOrgIds.includes(m.receiver_org_id);
                  const effective = isEffective(m);
                  const isSelected = selectedMandate?.id === m.id;
                  const acceptType = getAcceptType(m.id);

                  return (
                    <div
                      key={m.id}
                      onClick={() => setSelectedMandate(isSelected ? null : m)}
                      className={`px-6 py-4 cursor-pointer transition-colors ${
                        isSelected ? 'bg-primary/5 border-l-2 border-l-primary' : 'hover:bg-muted/50'
                      }`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2 flex-wrap">
                            <MandateStatusBadge status={m.status} />
                            {/* MVP-DA-017: show visual expiry indicator when status=active but date passed */}
                            {m.status === 'active' && !effective && (
                              <span className="inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border border-orange-200 bg-orange-50 text-orange-700">
                                Expiré (date dépassée)
                              </span>
                            )}
                            <span className="inline-flex items-center rounded-full text-xs font-medium px-2 py-0.5 border border-border bg-muted text-muted-foreground">
                              {SCOPE_LABELS[m.mandate_scope]}
                            </span>
                            {/* MVP-DA-019: badge indicating project-linked pending mandate */}
                            {m.status === 'pending_acceptance' && acceptType === 'project' && (
                              <span className="inline-flex items-center rounded-full text-xs font-medium px-2 py-0.5 border border-blue-200 bg-blue-50 text-blue-700">
                                <Icon name="FolderIcon" size={10} className="mr-1" />
                                Invitation projet
                              </span>
                            )}
                          </div>
                          <div className="mt-2 flex items-center gap-2 text-sm">
                            <span className="font-medium text-foreground truncate">
                              {m.issuer_org?.name ?? m.issuer_org_id.slice(0, 8)}
                            </span>
                            <Icon name="ArrowRightIcon" size={14} className="text-muted-foreground flex-shrink-0" />
                            <span className="font-medium text-foreground truncate">
                              {m.receiver_org?.name ?? m.receiver_org_id.slice(0, 8)}
                            </span>
                          </div>
                          <div className="mt-1 flex items-center gap-3 text-xs text-muted-foreground">
                            <span>{m.permissions.actions.length} action{m.permissions.actions.length > 1 ? 's' : ''}</span>
                            {m.end_date && (
                              <span>Expire le {new Date(m.end_date).toLocaleDateString('fr-CA')}</span>
                            )}
                            <span className={isIssuer ? 'text-blue-600' : isReceiver ? 'text-purple-600' : ''}>
                              {isIssuer && isReceiver ? 'Émis & Reçu' : isIssuer ? 'Émis' : isReceiver ? 'Reçu' : ''}
                            </span>
                          </div>
                        </div>

                        {/* Quick actions */}
                        <div className="flex items-center gap-1.5 flex-shrink-0" onClick={(e) => e.stopPropagation()}>
                          {/* Émettre: draft → pending_acceptance (issuer admin only) */}
                          {m.status === 'draft' && canIssue(m) && (
                            <button
                              onClick={() => handleSend(m)}
                              disabled={actionLoading === m.id}
                              className="flex items-center gap-1 px-2.5 py-1.5 bg-primary text-primary-foreground rounded-md text-xs font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
                            >
                              {actionLoading === m.id ? (
                                <div className="w-3 h-3 border border-primary-foreground border-t-transparent rounded-full animate-spin" />
                              ) : (
                                <Icon name="PaperAirplaneIcon" size={12} />
                              )}
                              Envoyer
                            </button>
                          )}

                          {/* Accept/Decline: pending_acceptance (receiver admin only) — MVP-DA-019 */}
                          {m.status === 'pending_acceptance' && (
                            <AcceptDeclineButtons mandate={m} size="sm" />
                          )}

                          {/* Révoquer: draft/pending/active (issuer admin only) */}
                          {(m.status === 'draft' || m.status === 'pending_acceptance' || m.status === 'active') && canIssue(m) && (
                            <button
                              onClick={() => handleRevoke(m)}
                              disabled={actionLoading === m.id}
                              className="flex items-center gap-1 px-2.5 py-1.5 bg-muted text-muted-foreground rounded-md text-xs font-medium hover:bg-red-50 hover:text-red-600 disabled:opacity-50 transition-colors"
                              title="Révoquer"
                            >
                              <Icon name="TrashIcon" size={12} />
                            </button>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {/* Detail panel */}
          {selectedMandate && (
            <div className="w-1/2 flex flex-col overflow-y-auto bg-card">
              <div className="flex items-center justify-between px-6 py-4 border-b border-border">
                <h2 className="text-base font-semibold text-foreground">Détail du mandat</h2>
                <button
                  onClick={() => setSelectedMandate(null)}
                  className="p-1 rounded-md hover:bg-muted text-muted-foreground"
                >
                  <Icon name="XMarkIcon" size={18} />
                </button>
              </div>

              <div className="px-6 py-4 space-y-5">
                {/* Status */}
                <div>
                  <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-1.5">Statut</p>
                  <div className="flex items-center gap-2 flex-wrap">
                    <MandateStatusBadge status={selectedMandate.status} />
                    {selectedMandate.status === 'active' && !isEffective(selectedMandate) && (
                      <span className="text-xs text-orange-600 font-medium">⚠ Expiré (date dépassée)</span>
                    )}
                    {/* MVP-DA-019: project-linked badge in detail panel */}
                    {selectedMandate.status === 'pending_acceptance' && getAcceptType(selectedMandate.id) === 'project' && (
                      <span className="inline-flex items-center rounded-full text-xs font-medium px-2 py-0.5 border border-blue-200 bg-blue-50 text-blue-700">
                        <Icon name="FolderIcon" size={10} className="mr-1" />
                        Invitation de projet
                      </span>
                    )}
                  </div>
                </div>

                {/* Parties */}
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-1">Émetteur</p>
                    <p className="text-sm font-semibold text-foreground">
                      {selectedMandate.issuer_org?.name ?? selectedMandate.issuer_org_id.slice(0, 8)}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-1">Récepteur</p>
                    <p className="text-sm font-semibold text-foreground">
                      {selectedMandate.receiver_org?.name ?? selectedMandate.receiver_org_id.slice(0, 8)}
                    </p>
                  </div>
                </div>

                {/* Scope — read-only if active (MVP-RA-029) */}
                <div>
                  <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-1">
                    Portée
                    {selectedMandate.status === 'active' && (
                      <span className="ml-2 text-[10px] text-orange-600 normal-case">(gelé — mandat actif)</span>
                    )}
                  </p>
                  <span className="inline-flex items-center rounded-md text-sm font-medium px-2.5 py-1 border border-border bg-muted text-foreground">
                    {SCOPE_LABELS[selectedMandate.mandate_scope]}
                  </span>
                </div>

                {/* Dates */}
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-1">Début</p>
                    <p className="text-sm text-foreground">
                      {selectedMandate.start_date
                        ? new Date(selectedMandate.start_date).toLocaleDateString('fr-CA')
                        : '—'}
                    </p>
                  </div>
                  <div>
                    <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-1">Fin</p>
                    <p className="text-sm text-foreground">
                      {selectedMandate.end_date
                        ? new Date(selectedMandate.end_date).toLocaleDateString('fr-CA')
                        : 'Indéfinie'}
                    </p>
                  </div>
                </div>

                {/* Actions — read-only if active (MVP-RA-029) */}
                <div>
                  <p className="text-xs font-medium text-muted-foreground uppercase tracking-wide mb-2">
                    Actions autorisées ({selectedMandate.permissions.actions.length})
                    {selectedMandate.status === 'active' && (
                      <span className="ml-2 text-[10px] text-orange-600 normal-case">(gelées — mandat actif)</span>
                    )}
                  </p>
                  <div className="space-y-1.5">
                    {selectedMandate.permissions.actions.map((code) => {
                      const action = mandateActions.find((a) => a.code === code);
                      return (
                        <div
                          key={code}
                          className="flex items-center gap-2 px-3 py-2 rounded-lg bg-muted border border-border text-sm"
                        >
                          <Icon name="CheckCircleIcon" size={14} className="text-green-600 flex-shrink-0" />
                          <span className="text-foreground">{action?.label ?? code}</span>
                        </div>
                      );
                    })}
                  </div>
                </div>

                {/* MVP-DA-019: project linkage info in detail panel */}
                {selectedMandate.status === 'pending_acceptance' && getAcceptType(selectedMandate.id) === 'project' && (
                  <div className="px-3 py-2.5 rounded-lg bg-blue-50 border border-blue-200 text-sm text-blue-800">
                    <div className="flex items-start gap-2">
                      <Icon name="InformationCircleIcon" size={16} className="flex-shrink-0 mt-0.5" />
                      <p>
                        Ce mandat est lié à une invitation de projet. Pour l'accepter, ouvrez l'écran projet
                        afin de voir le contexte complet avant de confirmer votre participation.
                      </p>
                    </div>
                  </div>
                )}

                {/* Metadata */}
                <div className="pt-2 border-t border-border">
                  <p className="text-xs text-muted-foreground">
                    Créé le {new Date(selectedMandate.created_at).toLocaleDateString('fr-CA')} ·{' '}
                    Mis à jour le {new Date(selectedMandate.updated_at).toLocaleDateString('fr-CA')}
                  </p>
                  <p className="text-xs text-muted-foreground font-mono mt-0.5 truncate">
                    ID: {selectedMandate.id}
                  </p>
                </div>

                {/* Action buttons panel */}
                <div className="pt-2 space-y-2">
                  {/* Émettre */}
                  {selectedMandate.status === 'draft' && canIssue(selectedMandate) && (
                    <button
                      onClick={() => handleSend(selectedMandate)}
                      disabled={actionLoading === selectedMandate.id}
                      className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
                    >
                      <Icon name="PaperAirplaneIcon" size={16} />
                      Envoyer pour acceptation
                    </button>
                  )}

                  {/* Accept/Decline — MVP-DA-019 two-branch logic */}
                  {selectedMandate.status === 'pending_acceptance' && (
                    <AcceptDeclineButtons mandate={selectedMandate} size="lg" />
                  )}

                  {/* Révoquer */}
                  {(selectedMandate.status === 'draft' || selectedMandate.status === 'pending_acceptance' || selectedMandate.status === 'active') && canIssue(selectedMandate) && (
                    <button
                      onClick={() => handleRevoke(selectedMandate)}
                      disabled={actionLoading === selectedMandate.id}
                      className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-muted text-muted-foreground rounded-lg text-sm font-medium hover:bg-red-50 hover:text-red-600 disabled:opacity-50 transition-colors border border-border"
                    >
                      <Icon name="TrashIcon" size={16} />
                      Révoquer ce mandat
                    </button>
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Create form modal */}
      {showCreateForm && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="bg-card rounded-xl shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
            <div className="flex items-center justify-between px-6 py-4 border-b border-border">
              <h2 className="text-base font-semibold text-foreground">Nouveau mandat</h2>
              <button
                onClick={() => { setShowCreateForm(false); setFormError(null); }}
                className="p-1 rounded-md hover:bg-muted text-muted-foreground"
              >
                <Icon name="XMarkIcon" size={18} />
              </button>
            </div>

            <form onSubmit={handleCreate} className="px-6 py-4 space-y-4">
              {formError && (
                <div className="flex items-center gap-2 px-3 py-2.5 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
                  <Icon name="ExclamationCircleIcon" size={14} />
                  {formError}
                </div>
              )}

              {/* Issuer org — only orgs where user is admin */}
              <div>
                <label className="block text-sm font-medium text-foreground mb-1.5">
                  Organisation émettrice <span className="text-red-500">*</span>
                </label>
                <select
                  value={form.issuer_org_id}
                  onChange={(e) => setForm({ ...form, issuer_org_id: e.target.value })}
                  className="w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  required
                >
                  <option value="">Sélectionner…</option>
                  {organizations
                    .filter((o) => myAdminOrgIds.includes(o.id))
                    .map((o) => (
                      <option key={o.id} value={o.id}>{o.name}</option>
                    ))}
                </select>
                <p className="text-xs text-muted-foreground mt-1">Seules vos organisations (admin) sont listées</p>
              </div>

              {/* Receiver org — exclude own org (MVP-RA-028: no self-mandate) */}
              <div>
                <label className="block text-sm font-medium text-foreground mb-1.5">
                  Organisation réceptrice <span className="text-red-500">*</span>
                </label>
                <select
                  value={form.receiver_org_id}
                  onChange={(e) => setForm({ ...form, receiver_org_id: e.target.value })}
                  className="w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  required
                >
                  <option value="">Sélectionner…</option>
                  {organizations
                    .filter((o) => o.id !== form.issuer_org_id)
                    .map((o) => (
                      <option key={o.id} value={o.id}>{o.name}</option>
                    ))}
                </select>
              </div>

              {/* Scope */}
              <div>
                <label className="block text-sm font-medium text-foreground mb-1.5">
                  Portée du mandat <span className="text-red-500">*</span>
                </label>
                <div className="grid grid-cols-3 gap-2">
                  {SCOPE_OPTIONS.map((s) => (
                    <button
                      key={s}
                      type="button"
                      onClick={() => setForm({ ...form, mandate_scope: s })}
                      className={`px-3 py-2 rounded-lg border text-sm font-medium transition-colors ${
                        form.mandate_scope === s
                          ? 'border-primary bg-primary/5 text-primary' :'border-border bg-card text-muted-foreground hover:bg-muted'
                      }`}
                    >
                      {SCOPE_LABELS[s]}
                    </button>
                  ))}
                </div>
              </div>

              {/* Actions — MandateActionPicker, at least one required */}
              <div>
                <label className="block text-sm font-medium text-foreground mb-1.5">
                  Actions autorisées <span className="text-red-500">*</span>
                </label>
                <p className="text-xs text-muted-foreground mb-2">Au moins une action est obligatoire</p>
                {mandateActions.length > 0 ? (
                  <ActionPicker
                    available={mandateActions}
                    selected={form.actions}
                    onChange={(codes) => setForm({ ...form, actions: codes })}
                  />
                ) : (
                  <p className="text-sm text-muted-foreground">Chargement du catalogue…</p>
                )}
              </div>

              {/* Dates (optional) */}
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1.5">Date de début</label>
                  <input
                    type="date"
                    value={form.start_date}
                    onChange={(e) => setForm({ ...form, start_date: e.target.value })}
                    className="w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-foreground mb-1.5">Date de fin</label>
                  <input
                    type="date"
                    value={form.end_date}
                    onChange={(e) => setForm({ ...form, end_date: e.target.value })}
                    className="w-full px-3 py-2 border border-border rounded-lg bg-background text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </div>
              </div>

              <div className="flex gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => { setShowCreateForm(false); setFormError(null); }}
                  className="flex-1 px-4 py-2.5 border border-border rounded-lg text-sm font-medium text-muted-foreground hover:bg-muted transition-colors"
                >
                  Annuler
                </button>
                <button
                  type="submit"
                  disabled={formLoading}
                  className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
                >
                  {formLoading ? (
                    <div className="w-4 h-4 border-2 border-primary-foreground border-t-transparent rounded-full animate-spin" />
                  ) : (
                    <Icon name="PlusIcon" size={16} />
                  )}
                  Créer le mandat
                </button>
              </div>
            </form>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
