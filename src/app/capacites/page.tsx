'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

type CapabilityStatus = 'draft' | 'declared' | 'qualified' | 'suspended' | 'archived';

interface Capability {
  id: string;
  organization_id: string;
  material_type: string | null;
  monthly_volume: number | null;
  location: string | null;
  availability: string | null;
  maturity: string | null;
  status: CapabilityStatus;
  created_at: string;
  updated_at: string;
}

interface Organization {
  id: string;
  name: string;
}

interface Opportunity {
  id: string;
  title: string;
  coordinator_org_id: string;
}

interface OrgMembership {
  organization_id: string;
  org_role: 'admin' | 'membre';
  status: string;
}

// ─── Status config ────────────────────────────────────────────────────────────

const STATUS_CONFIG: Record<CapabilityStatus, { label: string; cls: string; description: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200',   description: 'Créée, non soumise' },
  declared:  { label: 'Déclarée',   cls: 'text-blue-700 bg-blue-50 border-blue-200',    description: 'Soumise pour qualification' },
  qualified: { label: 'Qualifiée',  cls: 'text-green-700 bg-green-50 border-green-200', description: 'Validée et éligible aux opportunités' },
  suspended: { label: 'Suspendue',  cls: 'text-amber-700 bg-amber-50 border-amber-200', description: 'Temporairement inactive' },
  archived:  { label: 'Archivée',   cls: 'text-slate-500 bg-slate-100 border-slate-200', description: 'Retirée définitivement' },
};

function CapabilityStatusBadge({ status }: { status: CapabilityStatus }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.draft;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-600 px-2.5 py-1 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

// ─── Workflow transitions ─────────────────────────────────────────────────────

const ADMIN_TRANSITIONS: Record<CapabilityStatus, CapabilityStatus[]> = {
  draft:     ['declared', 'suspended', 'archived'],
  declared:  ['qualified', 'suspended', 'archived'],
  qualified: ['suspended', 'archived'],
  suspended: ['declared', 'archived'],
  archived:  [],
};

const TRANSITION_LABELS: Record<CapabilityStatus, string> = {
  draft:     'Remettre en brouillon',
  declared:  'Déclarer',
  qualified: 'Qualifier',
  suspended: 'Suspendre',
  archived:  'Archiver',
};

// ─── Create Capability Modal ──────────────────────────────────────────────────

interface CreateModalProps {
  organizations: Organization[];
  onClose: () => void;
  onCreated: () => void;
}

function CreateCapabilityModal({ organizations, onClose, onCreated }: CreateModalProps) {
  const [form, setForm] = useState({
    organization_id: organizations[0]?.id ?? '',
    material_type: '',
    monthly_volume: '',
    location: '',
    availability: '',
    maturity: '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleChange = (field: string, value: string) => {
    setForm(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.organization_id) { setError('Sélectionnez une organisation.'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const { error: insertError } = await supabase.from('capabilities').insert({
      organization_id: form.organization_id,
      material_type: form.material_type || null,
      monthly_volume: form.monthly_volume ? parseFloat(form.monthly_volume) : null,
      location: form.location || null,
      availability: form.availability || null,
      maturity: form.maturity || null,
      status: 'draft', // forced by RLS policy capabilities_member_insert
    });
    setSaving(false);
    if (insertError) { setError(insertError.message); return; }
    onCreated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <div>
            <h2 className="text-base font-700 text-foreground">Nouvelle capacité</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Statut initial : Brouillon (draft)</p>
          </div>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {organizations.length > 1 && (
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Organisation <span className="text-red-500">*</span></label>
              <select className="input w-full" value={form.organization_id} onChange={e => handleChange('organization_id', e.target.value)} required>
                {organizations.map(o => <option key={o.id} value={o.id}>{o.name}</option>)}
              </select>
            </div>
          )}
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Type de matériau</label>
            <input className="input w-full" placeholder="ex. Acier inoxydable, Aluminium…" value={form.material_type} onChange={e => handleChange('material_type', e.target.value)} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Volume mensuel (t)</label>
              <input type="number" min="0" step="0.01" className="input w-full" placeholder="ex. 50" value={form.monthly_volume} onChange={e => handleChange('monthly_volume', e.target.value)} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Localisation</label>
              <input className="input w-full" placeholder="ex. Montréal, QC" value={form.location} onChange={e => handleChange('location', e.target.value)} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Disponibilité</label>
            <input className="input w-full" placeholder="ex. Immédiate, Q3 2026…" value={form.availability} onChange={e => handleChange('availability', e.target.value)} />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Maturité</label>
            <input className="input w-full" placeholder="ex. Opérationnelle, En développement…" value={form.maturity} onChange={e => handleChange('maturity', e.target.value)} />
          </div>
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-1">
            <button type="button" onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Création…' : 'Créer la capacité'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Qualify Modal (admin/owner only) ────────────────────────────────────────

interface QualifyModalProps {
  capability: Capability;
  onClose: () => void;
  onUpdated: () => void;
}

function QualifyModal({ capability, onClose, onUpdated }: QualifyModalProps) {
  const transitions = ADMIN_TRANSITIONS[capability.status] ?? [];
  const [targetStatus, setTargetStatus] = useState<CapabilityStatus>(transitions[0] ?? 'draft');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    const supabase = createClient();
    const { error: updateError } = await supabase
      .from('capabilities')
      .update({ status: targetStatus, updated_at: new Date().toISOString() })
      .eq('id', capability.id);
    setSaving(false);
    if (updateError) { setError(updateError.message); return; }
    onUpdated();
    onClose();
  };

  if (transitions.length === 0) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
        <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-sm p-6 text-center">
          <Icon name="CheckCircleIcon" size={32} className="text-muted-foreground mx-auto mb-3" />
          <p className="text-sm text-muted-foreground">Aucune transition disponible depuis le statut <strong>{STATUS_CONFIG[capability.status]?.label}</strong>.</p>
          <button onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600 mt-4">Fermer</button>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <div>
            <h2 className="text-base font-700 text-foreground">Changer le statut</h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              Statut actuel : <span className="font-600">{STATUS_CONFIG[capability.status]?.label}</span>
            </p>
          </div>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-2">Nouveau statut</label>
            <div className="space-y-2">
              {transitions.map(s => (
                <label key={s} className={`flex items-start gap-3 p-3 rounded-lg border cursor-pointer transition-all ${targetStatus === s ? 'border-primary bg-primary/5' : 'border-border hover:border-muted-foreground/40'}`}>
                  <input type="radio" name="status" value={s} checked={targetStatus === s} onChange={() => setTargetStatus(s)} className="mt-0.5" />
                  <div>
                    <div className="flex items-center gap-2">
                      <CapabilityStatusBadge status={s} />
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">{STATUS_CONFIG[s]?.description}</p>
                  </div>
                </label>
              ))}
            </div>
          </div>
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-1">
            <button type="button" onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Mise à jour…' : 'Confirmer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Associate Opportunity Modal (coordinator only) ───────────────────────────

interface AssociateModalProps {
  capability: Capability;
  coordinatedOpportunities: Opportunity[];
  onClose: () => void;
  onAssociated: () => void;
}

function AssociateOpportunityModal({ capability, coordinatedOpportunities, onClose, onAssociated }: AssociateModalProps) {
  const [opportunityId, setOpportunityId] = useState(coordinatedOpportunities[0]?.id ?? '');
  const [fitScore, setFitScore] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!opportunityId) { setError('Sélectionnez une opportunité.'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const { error: insertError } = await supabase.from('opportunity_capabilities').insert({
      opportunity_id: opportunityId,
      capability_id: capability.id,
      fit_score: fitScore ? parseFloat(fitScore) : null,
    });
    setSaving(false);
    if (insertError) {
      // Surface the trigger error message clearly
      const msg = insertError.message.includes('capability_not_eligible')
        ? 'Cette capacité n\'est pas éligible (statut draft). Seules les capacités déclarées ou qualifiées peuvent être associées.'
        : insertError.message;
      setError(msg);
      return;
    }
    onAssociated();
    onClose();
  };

  if (coordinatedOpportunities.length === 0) {
    return (
      <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
        <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-sm p-6 text-center">
          <Icon name="InformationCircleIcon" size={32} className="text-muted-foreground mx-auto mb-3" />
          <p className="text-sm text-muted-foreground">Aucune opportunité dont vous êtes coordinateur n'est disponible.</p>
          <button onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600 mt-4">Fermer</button>
        </div>
      </div>
    );
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <div>
            <h2 className="text-base font-700 text-foreground">Associer à une opportunité</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Capacité : {capability.material_type ?? capability.id.slice(0, 8)}</p>
          </div>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Opportunité <span className="text-red-500">*</span></label>
            <select className="input w-full" value={opportunityId} onChange={e => setOpportunityId(e.target.value)} required>
              {coordinatedOpportunities.map(o => <option key={o.id} value={o.id}>{o.title}</option>)}
            </select>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Score de correspondance (0–100)</label>
            <input type="number" min="0" max="100" step="1" className="input w-full" placeholder="ex. 85" value={fitScore} onChange={e => setFitScore(e.target.value)} />
            <p className="text-xs text-muted-foreground mt-1">Optionnel — évaluation de l'adéquation entre la capacité et l'opportunité.</p>
          </div>
          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}
          <div className="flex justify-end gap-3 pt-1">
            <button type="button" onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Association…' : 'Associer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Capability Card ──────────────────────────────────────────────────────────

interface CapabilityCardProps {
  capability: Capability;
  isAdmin: boolean;
  isCoordinator: boolean;
  coordinatedOpportunities: Opportunity[];
  onRefresh: () => void;
}

function CapabilityCard({ capability, isAdmin, isCoordinator, coordinatedOpportunities, onRefresh }: CapabilityCardProps) {
  const [showQualify, setShowQualify] = useState(false);
  const [showAssociate, setShowAssociate] = useState(false);

  const canAssociate = isCoordinator && (capability.status === 'declared' || capability.status === 'qualified');

  return (
    <div className="bg-card border border-border rounded-xl p-5 hover:border-muted-foreground/30 transition-colors">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <CapabilityStatusBadge status={capability.status} />
            {capability.material_type && (
              <span className="text-sm font-600 text-foreground truncate">{capability.material_type}</span>
            )}
          </div>
          <p className="text-xs text-muted-foreground mt-1">{STATUS_CONFIG[capability.status]?.description}</p>
        </div>
        <div className="flex items-center gap-1.5 flex-shrink-0">
          {isAdmin && ADMIN_TRANSITIONS[capability.status]?.length > 0 && (
            <button
              onClick={() => setShowQualify(true)}
              className="btn-ghost px-2.5 py-1.5 rounded-lg text-xs font-600 flex items-center gap-1.5"
              title="Changer le statut"
            >
              <Icon name="ArrowPathIcon" size={13} />
              Qualifier
            </button>
          )}
          {canAssociate && (
            <button
              onClick={() => setShowAssociate(true)}
              className="btn-ghost px-2.5 py-1.5 rounded-lg text-xs font-600 flex items-center gap-1.5"
              title="Associer à une opportunité"
            >
              <Icon name="LinkIcon" size={13} />
              Associer
            </button>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-x-4 gap-y-2 mt-3">
        {capability.monthly_volume != null && (
          <div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-600">Volume mensuel</p>
            <p className="text-sm text-foreground font-600">{capability.monthly_volume} t</p>
          </div>
        )}
        {capability.location && (
          <div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-600">Localisation</p>
            <p className="text-sm text-foreground">{capability.location}</p>
          </div>
        )}
        {capability.availability && (
          <div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-600">Disponibilité</p>
            <p className="text-sm text-foreground">{capability.availability}</p>
          </div>
        )}
        {capability.maturity && (
          <div>
            <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-600">Maturité</p>
            <p className="text-sm text-foreground">{capability.maturity}</p>
          </div>
        )}
      </div>

      <p className="text-[11px] text-muted-foreground mt-3">
        Créée le {new Date(capability.created_at).toLocaleDateString('fr-CA')}
      </p>

      {showQualify && (
        <QualifyModal
          capability={capability}
          onClose={() => setShowQualify(false)}
          onUpdated={onRefresh}
        />
      )}
      {showAssociate && (
        <AssociateOpportunityModal
          capability={capability}
          coordinatedOpportunities={coordinatedOpportunities}
          onClose={() => setShowAssociate(false)}
          onAssociated={onRefresh}
        />
      )}
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function CapacitesPage() {
  const [capabilities, setCapabilities] = useState<Capability[]>([]);
  const [userOrgs, setUserOrgs] = useState<Organization[]>([]);
  const [memberships, setMemberships] = useState<OrgMembership[]>([]);
  const [coordinatedOpportunities, setCoordinatedOpportunities] = useState<Opportunity[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [filterStatus, setFilterStatus] = useState<CapabilityStatus | 'all'>('all');

  const supabase = createClient();

  const loadData = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setError('Non authentifié.'); setLoading(false); return; }

      // 1. Get user's org memberships
      const { data: memberRows, error: memberErr } = await supabase
        .from('organization_members')
        .select('organization_id, org_role, status')
        .eq('user_id', user.id)
        .eq('status', 'active');

      if (memberErr) throw memberErr;
      const mships = (memberRows ?? []) as OrgMembership[];
      setMemberships(mships);

      const orgIds = mships.map(m => m.organization_id);
      if (orgIds.length === 0) {
        setCapabilities([]);
        setUserOrgs([]);
        setLoading(false);
        return;
      }

      // 2. Get organizations
      const { data: orgsData, error: orgsErr } = await supabase
        .from('organizations')
        .select('id, name')
        .in('id', orgIds);
      if (orgsErr) throw orgsErr;
      setUserOrgs((orgsData ?? []) as Organization[]);

      // 3. Get capabilities for those orgs
      const { data: capsData, error: capsErr } = await supabase
        .from('capabilities')
        .select('*')
        .in('organization_id', orgIds)
        .order('created_at', { ascending: false });
      if (capsErr) throw capsErr;
      setCapabilities((capsData ?? []) as Capability[]);

      // 4. Get opportunities coordinated by admin orgs (for association form)
      const adminOrgIds = mships.filter(m => m.org_role === 'admin').map(m => m.organization_id);
      if (adminOrgIds.length > 0) {
        const { data: oppsData } = await supabase
          .from('opportunities')
          .select('id, title, coordinator_org_id')
          .in('coordinator_org_id', adminOrgIds)
          .not('status', 'in', '(closed,archived)');
        setCoordinatedOpportunities((oppsData ?? []) as Opportunity[]);
      }
    } catch (err: any) {
      setError(err?.message ?? 'Erreur lors du chargement.');
    }
    setLoading(false);
  }, []);

  useEffect(() => { loadData(); }, [loadData]);

  const isAdminOfOrg = (orgId: string) =>
    memberships.some(m => m.organization_id === orgId && m.org_role === 'admin');

  const isCoordinatorOfAny = coordinatedOpportunities.length > 0;

  const filteredCaps = filterStatus === 'all'
    ? capabilities
    : capabilities.filter(c => c.status === filterStatus);

  const statusCounts = capabilities.reduce<Record<string, number>>((acc, c) => {
    acc[c.status] = (acc[c.status] ?? 0) + 1;
    return acc;
  }, {});

  return (
    <AppLayout activeRoute="/capacites">
      <div className="space-y-6">
        {/* Header */}
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Capacités</h1>
            <p className="text-sm text-muted-foreground mt-1">
              Capacités déclarées par votre organisation dans le réseau METALTRACE.
            </p>
          </div>
          {userOrgs.length > 0 && (
            <button
              onClick={() => setShowCreate(true)}
              className="btn-primary px-4 py-2.5 rounded-lg text-sm font-600 flex items-center gap-2 flex-shrink-0"
            >
              <Icon name="PlusIcon" size={16} />
              Nouvelle capacité
            </button>
          )}
        </div>

        {/* Status summary pills */}
        {capabilities.length > 0 && (
          <div className="flex flex-wrap gap-2">
            <button
              onClick={() => setFilterStatus('all')}
              className={`px-3 py-1.5 rounded-full text-xs font-600 border transition-all ${filterStatus === 'all' ? 'bg-foreground text-background border-foreground' : 'border-border text-muted-foreground hover:border-muted-foreground/50'}`}
            >
              Toutes ({capabilities.length})
            </button>
            {(Object.keys(STATUS_CONFIG) as CapabilityStatus[]).map(s => {
              const count = statusCounts[s] ?? 0;
              if (count === 0) return null;
              return (
                <button
                  key={s}
                  onClick={() => setFilterStatus(s)}
                  className={`px-3 py-1.5 rounded-full text-xs font-600 border transition-all ${filterStatus === s ? 'bg-foreground text-background border-foreground' : 'border-border text-muted-foreground hover:border-muted-foreground/50'}`}
                >
                  {STATUS_CONFIG[s].label} ({count})
                </button>
              );
            })}
          </div>
        )}

        {/* Admin notice */}
        {memberships.some(m => m.org_role === 'admin') && (
          <div className="rounded-lg bg-blue-50 border border-blue-200 px-4 py-3 flex items-start gap-2.5">
            <Icon name="ShieldCheckIcon" size={16} className="text-blue-600 mt-0.5 flex-shrink-0" />
            <p className="text-sm text-blue-700">
              En tant qu'administrateur, vous pouvez faire progresser le statut des capacités (draft → déclarée → qualifiée) et les suspendre ou archiver.
            </p>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="rounded-lg bg-red-50 border border-red-200 px-4 py-3 flex items-start gap-2">
            <Icon name="ExclamationTriangleIcon" size={16} className="text-red-500 mt-0.5 flex-shrink-0" />
            <p className="text-sm text-red-700">{error}</p>
          </div>
        )}

        {/* Loading */}
        {loading && (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {[1, 2, 3].map(i => (
              <div key={i} className="bg-card border border-border rounded-xl p-5 animate-pulse">
                <div className="h-5 bg-muted rounded w-24 mb-3" />
                <div className="h-4 bg-muted rounded w-40 mb-2" />
                <div className="h-4 bg-muted rounded w-32" />
              </div>
            ))}
          </div>
        )}

        {/* Empty state */}
        {!loading && !error && filteredCaps.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-14 h-14 rounded-full bg-muted flex items-center justify-center mb-4">
              <Icon name="CubeIcon" size={24} className="text-muted-foreground" />
            </div>
            <h3 className="text-base font-600 text-foreground mb-1">
              {filterStatus === 'all' ? 'Aucune capacité déclarée' : `Aucune capacité en statut « ${STATUS_CONFIG[filterStatus as CapabilityStatus]?.label} »`}
            </h3>
            <p className="text-sm text-muted-foreground max-w-sm">
              {filterStatus === 'all' ?'Créez votre première capacité pour la rendre visible dans le réseau.' :'Modifiez le filtre pour voir d\'autres capacités.'}
            </p>
            {filterStatus === 'all' && userOrgs.length > 0 && (
              <button onClick={() => setShowCreate(true)} className="btn-primary px-4 py-2.5 rounded-lg text-sm font-600 mt-4 flex items-center gap-2">
                <Icon name="PlusIcon" size={16} />
                Créer une capacité
              </button>
            )}
          </div>
        )}

        {/* Capabilities grid */}
        {!loading && filteredCaps.length > 0 && (
          <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            {filteredCaps.map(cap => (
              <CapabilityCard
                key={cap.id}
                capability={cap}
                isAdmin={isAdminOfOrg(cap.organization_id)}
                isCoordinator={isCoordinatorOfAny}
                coordinatedOpportunities={coordinatedOpportunities}
                onRefresh={loadData}
              />
            ))}
          </div>
        )}
      </div>

      {/* Create modal */}
      {showCreate && (
        <CreateCapabilityModal
          organizations={userOrgs}
          onClose={() => setShowCreate(false)}
          onCreated={loadData}
        />
      )}
    </AppLayout>
  );
}
