'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

type OppStatus = 'draft' | 'qualified' | 'converted' | 'closed' | 'archived';
type OppCapStatus = 'active' | 'removed' | 'withdrawn' | 'pending_reacceptance';

interface Organization {
  id: string;
  name: string;
}

interface Opportunity {
  id: string;
  title: string;
  description: string | null;
  coordinator_org_id: string;
  region: string | null;
  target_volume: number | null;
  priority: string | null;
  status: OppStatus;
  created_at: string;
  updated_at: string;
}

interface OppCapability {
  id: string;
  opportunity_id: string;
  capability_id: string;
  fit_score: number | null;
  status: OppCapStatus;
  created_at: string;
  capabilities: {
    id: string;
    material_type: string | null;
    monthly_volume: number | null;
    location: string | null;
    status: string;
    organization_id: string;
    organizations: { name: string } | null;
  } | null;
}

interface OrgMembership {
  organization_id: string;
  org_role: 'admin' | 'membre';
  status: string;
}

// ─── Status config ────────────────────────────────────────────────────────────

const OPP_STATUS_CONFIG: Record<OppStatus, { label: string; cls: string; description: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200',    description: 'Créée, non qualifiée' },
  qualified: { label: 'Qualifiée',  cls: 'text-green-700 bg-green-50 border-green-200',  description: 'Validée, prête pour un projet' },
  converted: { label: 'Convertie',  cls: 'text-blue-700 bg-blue-50 border-blue-200',     description: 'Liée à un projet actif' },
  closed:    { label: 'Fermée',     cls: 'text-slate-500 bg-slate-100 border-slate-200', description: 'Clôturée sans conversion' },
  archived:  { label: 'Archivée',   cls: 'text-slate-400 bg-slate-50 border-slate-100',  description: 'Retirée définitivement' },
};

const OPP_CAP_STATUS_CONFIG: Record<OppCapStatus, { label: string; cls: string }> = {
  active:                { label: 'Active',             cls: 'text-green-700 bg-green-50 border-green-200' },
  removed:               { label: 'Retirée',            cls: 'text-red-600 bg-red-50 border-red-200' },
  withdrawn:             { label: 'Retrait candidat',   cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  pending_reacceptance:  { label: 'Relance en attente', cls: 'text-purple-700 bg-purple-50 border-purple-200' },
};

function OppStatusBadge({ status }: { status: OppStatus }) {
  const cfg = OPP_STATUS_CONFIG[status] ?? OPP_STATUS_CONFIG.draft;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2.5 py-1 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

function OppCapStatusBadge({ status }: { status: OppCapStatus }) {
  const cfg = OPP_CAP_STATUS_CONFIG[status] ?? OPP_CAP_STATUS_CONFIG.active;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

// ─── Create Opportunity Modal ─────────────────────────────────────────────────

interface CreateModalProps {
  coordOrgs: Organization[];
  actorId: string;
  onClose: () => void;
  onCreated: (id: string) => void;
}

function CreateOpportunityModal({ coordOrgs, actorId, onClose, onCreated }: CreateModalProps) {
  const [form, setForm] = useState({
    coordinator_org_id: coordOrgs[0]?.id ?? '',
    title: '',
    description: '',
    region: '',
    target_volume: '',
    priority: '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const set = (field: string, value: string) =>
    setForm(prev => ({ ...prev, [field]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.title.trim()) { setError('Le titre est obligatoire.'); return; }
    if (!form.coordinator_org_id) { setError('Sélectionnez une organisation coordinatrice.'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();

    const { data: opp, error: insertError } = await supabase
      .from('opportunities')
      .insert({
        title: form.title.trim(),
        description: form.description.trim() || null,
        coordinator_org_id: form.coordinator_org_id,
        region: form.region.trim() || null,
        target_volume: form.target_volume ? parseFloat(form.target_volume) : null,
        priority: form.priority.trim() || null,
        status: 'draft',
      })
      .select('id')
      .single();

    if (insertError) { setError(insertError.message); setSaving(false); return; }

    // Emit business event opportunity_created
    // actor_id = auth.uid() = profiles.id directly (no user_id column on profiles)
    if (opp) {
      await supabase.from('business_events').insert({
        event_type: 'opportunity_created',
        object_type: 'opportunity',
        object_id: opp.id,
        actor_id: actorId,
        organization_id: form.coordinator_org_id,
        payload: { title: form.title.trim(), status: 'draft' },
      });
    }

    setSaving(false);
    onCreated(opp?.id ?? '');
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <div>
            <h2 className="text-base font-bold text-foreground">Nouvelle opportunité</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Statut initial : Brouillon (draft)</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {coordOrgs.length > 1 && (
            <div>
              <label className="block text-sm font-semibold text-foreground mb-1">
                Organisation coordinatrice <span className="text-red-500">*</span>
              </label>
              <select
                className="input w-full"
                value={form.coordinator_org_id}
                onChange={e => set('coordinator_org_id', e.target.value)}
                required
              >
                {coordOrgs.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
          )}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">
              Titre <span className="text-red-500">*</span>
            </label>
            <input
              className="input w-full"
              placeholder="ex. Consolidation acier inoxydable région Montréal"
              value={form.title}
              onChange={e => set('title', e.target.value)}
              required
            />
          </div>
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">Description</label>
            <textarea
              className="input w-full min-h-[80px] resize-y"
              placeholder="Contexte, objectifs, contraintes…"
              value={form.description}
              onChange={e => set('description', e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-semibold text-foreground mb-1">Région</label>
              <input
                className="input w-full"
                placeholder="ex. Montréal, QC"
                value={form.region}
                onChange={e => set('region', e.target.value)}
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-foreground mb-1">Volume cible (t)</label>
              <input
                type="number"
                min="0"
                step="0.01"
                className="input w-full"
                placeholder="ex. 200"
                value={form.target_volume}
                onChange={e => set('target_volume', e.target.value)}
              />
            </div>
          </div>
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">Priorité</label>
            <select
              className="input w-full"
              value={form.priority}
              onChange={e => set('priority', e.target.value)}
            >
              <option value="">— Sélectionner —</option>
              <option value="haute">Haute</option>
              <option value="normale">Normale</option>
              <option value="basse">Basse</option>
            </select>
          </div>
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-1">
            <button type="button" onClick={onClose} className="px-4 py-2 rounded-lg text-sm font-semibold hover:bg-muted transition-colors">
              Annuler
            </button>
            <button
              type="submit"
              disabled={saving}
              className="btn-primary px-4 py-2 rounded-lg text-sm font-semibold disabled:opacity-50"
            >
              {saving ? 'Création…' : 'Créer l\'opportunité'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Qualify Modal ────────────────────────────────────────────────────────────

interface QualifyModalProps {
  opportunity: Opportunity;
  actorId: string;
  onClose: () => void;
  onQualified: () => void;
}

function QualifyModal({ opportunity, actorId, onClose, onQualified }: QualifyModalProps) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleQualify = async () => {
    setSaving(true);
    setError('');
    const supabase = createClient();

    const { error: updateError } = await supabase
      .from('opportunities')
      .update({ status: 'qualified', updated_at: new Date().toISOString() })
      .eq('id', opportunity.id);

    if (updateError) { setError(updateError.message); setSaving(false); return; }

    // Emit business event opportunity_qualified
    // actor_id = auth.uid() = profiles.id directly (no user_id column on profiles)
    await supabase.from('business_events').insert({
      event_type: 'opportunity_qualified',
      object_type: 'opportunity',
      object_id: opportunity.id,
      actor_id: actorId,
      organization_id: opportunity.coordinator_org_id,
      payload: { title: opportunity.title, previous_status: 'draft', new_status: 'qualified' },
    });

    setSaving(false);
    onQualified();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <div>
            <h2 className="text-base font-bold text-foreground">Qualifier l'opportunité</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Transition : Brouillon → Qualifiée</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <div className="p-5 space-y-4">
          <div className="rounded-lg bg-amber-50 border border-amber-200 px-4 py-3 flex items-start gap-3">
            <Icon name="ExclamationTriangleIcon" size={16} className="text-amber-600 mt-0.5 flex-shrink-0" />
            <div>
              <p className="text-sm font-semibold text-amber-800">Confirmer la qualification</p>
              <p className="text-xs text-amber-700 mt-0.5">
                L'opportunité <strong>«&nbsp;{opportunity.title}&nbsp;»</strong> passera au statut{' '}
                <strong>Qualifiée</strong>. Cette action émet un événement métier{' '}
                <code className="text-xs bg-amber-100 px-1 rounded">opportunity_qualified</code>.
              </p>
            </div>
          </div>
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}
          <div className="flex justify-end gap-3">
            <button type="button" onClick={onClose} className="px-4 py-2 rounded-lg text-sm font-semibold hover:bg-muted transition-colors">
              Annuler
            </button>
            <button
              onClick={handleQualify}
              disabled={saving}
              className="btn-primary px-4 py-2 rounded-lg text-sm font-semibold disabled:opacity-50 flex items-center gap-2"
            >
              <Icon name="CheckCircleIcon" size={16} />
              {saving ? 'Qualification…' : 'Qualifier'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ─── Opportunity Detail Panel ─────────────────────────────────────────────────

interface DetailPanelProps {
  opportunity: Opportunity;
  coordOrgName: string;
  isCoordinator: boolean;
  actorId: string;
  onQualified: () => void;
  onClose: () => void;
}

function OpportunityDetailPanel({
  opportunity,
  coordOrgName,
  isCoordinator,
  actorId,
  onQualified,
  onClose,
}: DetailPanelProps) {
  const [capabilities, setCapabilities] = useState<OppCapability[]>([]);
  const [loadingCaps, setLoadingCaps] = useState(true);
  const [showQualifyModal, setShowQualifyModal] = useState(false);

  const loadCapabilities = useCallback(async () => {
    setLoadingCaps(true);
    const supabase = createClient();
    const { data } = await supabase
      .from('opportunity_capabilities')
      .select(`
        id, opportunity_id, capability_id, fit_score, status, created_at,
        capabilities (
          id, material_type, monthly_volume, location, status, organization_id,
          organizations ( name )
        )
      `)
      .eq('opportunity_id', opportunity.id)
      .order('created_at', { ascending: false });
    setCapabilities((data as OppCapability[]) ?? []);
    setLoadingCaps(false);
  }, [opportunity.id]);

  useEffect(() => { loadCapabilities(); }, [loadCapabilities]);

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex items-start justify-between p-5 border-b border-border">
        <div className="flex-1 min-w-0 pr-4">
          <div className="flex items-center gap-2 flex-wrap">
            <h2 className="text-base font-bold text-foreground truncate">{opportunity.title}</h2>
            <OppStatusBadge status={opportunity.status} />
          </div>
          <p className="text-xs text-muted-foreground mt-1">{coordOrgName}</p>
        </div>
        <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors flex-shrink-0">
          <Icon name="XMarkIcon" size={18} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto p-5 space-y-5">
        {/* Meta */}
        <div className="grid grid-cols-2 gap-3">
          {opportunity.region && (
            <div className="rounded-lg bg-muted p-3">
              <p className="text-xs text-muted-foreground mb-0.5">Région</p>
              <p className="text-sm font-semibold text-foreground">{opportunity.region}</p>
            </div>
          )}
          {opportunity.target_volume != null && (
            <div className="rounded-lg bg-muted p-3">
              <p className="text-xs text-muted-foreground mb-0.5">Volume cible</p>
              <p className="text-sm font-semibold text-foreground">{opportunity.target_volume} t</p>
            </div>
          )}
          {opportunity.priority && (
            <div className="rounded-lg bg-muted p-3">
              <p className="text-xs text-muted-foreground mb-0.5">Priorité</p>
              <p className="text-sm font-semibold text-foreground capitalize">{opportunity.priority}</p>
            </div>
          )}
        </div>

        {/* Description */}
        {opportunity.description && (
          <div>
            <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-2">Description</p>
            <p className="text-sm text-foreground leading-relaxed">{opportunity.description}</p>
          </div>
        )}

        {/* Qualification action */}
        {isCoordinator && opportunity.status === 'draft' && (
          <div className="rounded-lg border border-border p-4 flex items-center justify-between gap-4">
            <div>
              <p className="text-sm font-semibold text-foreground">Qualifier cette opportunité</p>
              <p className="text-xs text-muted-foreground mt-0.5">
                Transition draft → qualified. Réservée au coordonnateur.
              </p>
            </div>
            <button
              onClick={() => setShowQualifyModal(true)}
              className="btn-primary px-3 py-2 rounded-lg text-sm font-semibold flex items-center gap-2 flex-shrink-0"
            >
              <Icon name="CheckCircleIcon" size={16} />
              Qualifier
            </button>
          </div>
        )}

        {/* Candidate capabilities */}
        <div>
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wider mb-3">
            Capacités candidates ({capabilities.length})
          </p>
          {loadingCaps ? (
            <div className="space-y-2">
              {[1, 2].map(i => (
                <div key={i} className="h-16 rounded-lg bg-muted animate-pulse" />
              ))}
            </div>
          ) : capabilities.length === 0 ? (
            <div className="rounded-lg border border-dashed border-border p-6 text-center">
              <Icon name="CubeIcon" size={24} className="text-muted-foreground mx-auto mb-2" />
              <p className="text-sm text-muted-foreground">Aucune capacité candidate associée.</p>
            </div>
          ) : (
            <div className="space-y-2">
              {capabilities.map(oc => (
                <div
                  key={oc.id}
                  className="rounded-lg border border-border p-3 flex items-start justify-between gap-3"
                >
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <p className="text-sm font-semibold text-foreground truncate">
                        {oc.capabilities?.material_type ?? 'Matériau non précisé'}
                      </p>
                      <OppCapStatusBadge status={oc.status} />
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {oc.capabilities?.organizations?.name ?? '—'}
                      {oc.capabilities?.location ? ` · ${oc.capabilities.location}` : ''}
                      {oc.capabilities?.monthly_volume != null
                        ? ` · ${oc.capabilities.monthly_volume} t/mois`
                        : ''}
                    </p>
                  </div>
                  {oc.fit_score != null && (
                    <div className="flex-shrink-0 text-right">
                      <p className="text-xs text-muted-foreground">Score</p>
                      <p className={`text-sm font-bold ${
                        oc.fit_score >= 70 ? 'text-green-600' :
                        oc.fit_score >= 40 ? 'text-amber-600' : 'text-red-500'
                      }`}>
                        {oc.fit_score}%
                      </p>
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {showQualifyModal && (
        <QualifyModal
          opportunity={opportunity}
          actorId={actorId}
          onClose={() => setShowQualifyModal(false)}
          onQualified={() => { onQualified(); loadCapabilities(); }}
        />
      )}
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function OpportunitiesPage() {
  const [opportunities, setOpportunities] = useState<Opportunity[]>([]);
  const [coordOrgs, setCoordOrgs] = useState<Organization[]>([]);
  const [orgMap, setOrgMap] = useState<Record<string, string>>({});
  // actorId = auth.uid() = profiles.id directly (profiles has no user_id column)
  const [actorId, setActorId] = useState<string>('');
  const [coordOrgIds, setCoordOrgIds] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedOpp, setSelectedOpp] = useState<Opportunity | null>(null);
  const [filterStatus, setFilterStatus] = useState<OppStatus | 'all'>('all');

  const loadData = useCallback(async () => {
    setLoading(true);
    setError('');
    const supabase = createClient();

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) { setError('Non authentifié.'); setLoading(false); return; }

    // profiles.id = auth.uid() directly — no user_id column on profiles
    setActorId(user.id);

    // Get org memberships (admin/owner can coordinate)
    // organization_members.user_id references profiles.id = auth.uid()
    const { data: memberships } = await supabase
      .from('organization_members')
      .select('organization_id, org_role, status')
      .eq('user_id', user.id)
      .eq('status', 'active');

    const adminOrgIds = (memberships as OrgMembership[] ?? [])
      .filter(m => m.org_role === 'admin')
      .map(m => m.organization_id);

    const allOrgIds = (memberships as OrgMembership[] ?? []).map(m => m.organization_id);
    setCoordOrgIds(adminOrgIds);

    // Get organizations for those memberships
    if (allOrgIds.length > 0) {
      const { data: orgs } = await supabase
        .from('organizations')
        .select('id, name')
        .in('id', allOrgIds);
      const map: Record<string, string> = {};
      (orgs ?? []).forEach((o: Organization) => { map[o.id] = o.name; });
      setOrgMap(map);
      const adminOrgs = (orgs ?? []).filter((o: Organization) => adminOrgIds.includes(o.id));
      setCoordOrgs(adminOrgs as Organization[]);
    }

    // Load opportunities coordinated by user's orgs
    if (allOrgIds.length > 0) {
      const { data: opps, error: oppsError } = await supabase
        .from('opportunities')
        .select('*')
        .in('coordinator_org_id', allOrgIds)
        .order('created_at', { ascending: false });

      if (oppsError) { setError(oppsError.message); }
      else { setOpportunities((opps as Opportunity[]) ?? []); }
    }

    setLoading(false);
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  const filtered = filterStatus === 'all'
    ? opportunities
    : opportunities.filter(o => o.status === filterStatus);

  const isCoordinator = (opp: Opportunity) => coordOrgIds.includes(opp.coordinator_org_id);

  return (
    <AppLayout activeRoute="/opportunities">
      <div className="flex h-full">
        {/* Main list */}
        <div className={`flex flex-col flex-1 min-w-0 ${selectedOpp ? 'hidden lg:flex' : 'flex'}`}>
          {/* Header */}
          <div className="flex items-center justify-between px-6 py-4 border-b border-border bg-card">
            <div>
              <h1 className="text-lg font-bold text-foreground">Opportunités</h1>
              <p className="text-xs text-muted-foreground mt-0.5">
                Opportunités coordonnées par votre organisation
              </p>
            </div>
            {coordOrgs.length > 0 && (
              <button
                onClick={() => setShowCreateModal(true)}
                className="btn-primary px-4 py-2 rounded-lg text-sm font-semibold flex items-center gap-2"
              >
                <Icon name="PlusIcon" size={16} />
                Nouvelle opportunité
              </button>
            )}
          </div>

          {/* Filters */}
          <div className="flex items-center gap-2 px-6 py-3 border-b border-border bg-card overflow-x-auto">
            {(['all', 'draft', 'qualified', 'converted', 'closed', 'archived'] as const).map(s => (
              <button
                key={s}
                onClick={() => setFilterStatus(s)}
                className={`px-3 py-1.5 rounded-lg text-xs font-semibold whitespace-nowrap transition-all ${
                  filterStatus === s
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-muted text-muted-foreground hover:text-foreground'
                }`}
              >
                {s === 'all' ? 'Toutes' : OPP_STATUS_CONFIG[s]?.label ?? s}
                {s !== 'all' && (
                  <span className="ml-1.5 opacity-70">
                    ({opportunities.filter(o => o.status === s).length})
                  </span>
                )}
              </button>
            ))}
          </div>

          {/* Content */}
          <div className="flex-1 overflow-y-auto p-6">
            {loading ? (
              <div className="space-y-3">
                {[1, 2, 3].map(i => (
                  <div key={i} className="h-20 rounded-xl bg-muted animate-pulse" />
                ))}
              </div>
            ) : error ? (
              <div className="rounded-xl bg-red-50 border border-red-200 p-4 flex items-start gap-3">
                <Icon name="ExclamationTriangleIcon" size={18} className="text-red-500 flex-shrink-0 mt-0.5" />
                <div>
                  <p className="text-sm font-semibold text-red-800">Erreur de chargement</p>
                  <p className="text-xs text-red-700 mt-0.5">{error}</p>
                </div>
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 text-center">
                <div className="w-14 h-14 rounded-full bg-muted flex items-center justify-center mb-4">
                  <Icon name="LightBulbIcon" size={28} className="text-muted-foreground" />
                </div>
                <p className="text-base font-semibold text-foreground mb-1">
                  {filterStatus === 'all' ? 'Aucune opportunité' : `Aucune opportunité « ${OPP_STATUS_CONFIG[filterStatus as OppStatus]?.label} »`}
                </p>
                <p className="text-sm text-muted-foreground max-w-xs">
                  {coordOrgs.length > 0
                    ? 'Créez votre première opportunité en cliquant sur « Nouvelle opportunité ».' :'Vous n\'avez pas de rôle coordinateur (admin) dans une organisation.'}
                </p>
              </div>
            ) : (
              <div className="space-y-3">
                {filtered.map(opp => (
                  <button
                    key={opp.id}
                    onClick={() => setSelectedOpp(opp)}
                    className={`w-full text-left rounded-xl border p-4 transition-all hover:shadow-sm ${
                      selectedOpp?.id === opp.id
                        ? 'border-primary bg-primary/5' :'border-border bg-card hover:border-muted-foreground/30'
                    }`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <p className="text-sm font-semibold text-foreground truncate">{opp.title}</p>
                          <OppStatusBadge status={opp.status} />
                          {isCoordinator(opp) && (
                            <span className="inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border border-primary/30 text-primary bg-primary/5">
                              Coordinateur
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-muted-foreground mt-1">
                          {orgMap[opp.coordinator_org_id] ?? '—'}
                          {opp.region ? ` · ${opp.region}` : ''}
                          {opp.target_volume != null ? ` · ${opp.target_volume} t` : ''}
                          {opp.priority ? ` · Priorité ${opp.priority}` : ''}
                        </p>
                      </div>
                      <Icon name="ChevronRightIcon" size={16} className="text-muted-foreground flex-shrink-0 mt-0.5" />
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Detail panel */}
        {selectedOpp && (
          <div className="w-full lg:w-[420px] xl:w-[480px] flex-shrink-0 border-l border-border bg-card flex flex-col">
            <OpportunityDetailPanel
              key={selectedOpp.id}
              opportunity={selectedOpp}
              coordOrgName={orgMap[selectedOpp.coordinator_org_id] ?? '—'}
              isCoordinator={isCoordinator(selectedOpp)}
              actorId={actorId}
              onQualified={() => {
                loadData();
                setSelectedOpp(prev => prev ? { ...prev, status: 'qualified' } : null);
              }}
              onClose={() => setSelectedOpp(null)}
            />
          </div>
        )}
      </div>

      {/* Create modal */}
      {showCreateModal && (
        <CreateOpportunityModal
          coordOrgs={coordOrgs}
          actorId={actorId}
          onClose={() => setShowCreateModal(false)}
          onCreated={() => loadData()}
        />
      )}
    </AppLayout>
  );
}
