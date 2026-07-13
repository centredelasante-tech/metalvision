'use client';
import React, { useEffect, useState, useCallback, useRef, useMemo } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';
import ObjectTimeline from '@/components/ObjectTimeline';
import { computeProjectRisks } from '@/lib/projectRisks';
import { getErrorMessage } from '@/lib/getErrorMessage';

// ─── Types ────────────────────────────────────────────────────────────────────

type ProjectPhase = 'draft' | 'active' | 'execution' | 'review' | 'closed';
type ProjectStatus = 'draft' | 'active' | 'paused' | 'closed' | 'archived';
type ParticipantStatus = 'invited' | 'active' | 'declined' | 'removed';
type LogisticsStepType = 'ramassage' | 'chargement' | 'expedition' | 'transit' | 'livraison' | 'preuve_finale';
type LogisticsStepStatus = 'planned' | 'in_progress' | 'completed' | 'blocked' | 'cancelled';
type DocVisibility = 'organization_private' | 'project' | 'confidential';
type DocStatus = 'draft' | 'submitted' | 'approved' | 'rejected' | 'archived';
type ValueReportStatus = 'draft' | 'generated' | 'validated' | 'shared' | 'archived';

interface Organization {
  id: string;
  name: string;
}

interface CcfProject {
  id: string;
  opportunity_id: string;
  coordinator_org_id: string;
  phase: ProjectPhase;
  status: ProjectStatus;
  start_date: string | null;
  target_end_date: string | null;
  created_at: string;
  updated_at: string;
  coordinator_org?: { name: string } | null;
  opportunity?: { title: string } | null;
}

interface ProjectParticipant {
  id: string;
  project_id: string;
  organization_id: string;
  project_role: string;
  mandate_id: string | null;
  status: ParticipantStatus;
  created_at: string;
  organization?: { name: string } | null;
}

interface LogisticsStep {
  id: string;
  project_id: string;
  step_type: LogisticsStepType;
  responsible_org_id: string | null;
  planned_date: string | null;
  actual_date: string | null;
  proof_document_id: string | null;
  status: LogisticsStepStatus;
  notes: string | null;
  created_at: string;
  responsible_org?: { name: string } | null;
}

interface Document {
  id: string;
  owner_org_id: string;
  object_type: string;
  object_id: string;
  title: string;
  category: string | null;
  version: string;
  visibility: DocVisibility;
  storage_path: string | null;
  status: DocStatus;
  created_at: string;
}

interface ValueReport {
  id: string;
  project_id: string;
  volume: number | null;
  coordination_value: number | null;
  notes: string | null;
  status: ValueReportStatus;
  created_at: string;
  updated_at: string;
}

interface OrgMembership {
  organization_id: string;
  org_role: string;
  operational_profile: string | null;
  status: string;
}

interface MandateAction {
  code: string;
  label: string;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const PHASE_CONFIG: Record<ProjectPhase, { label: string; cls: string; icon: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200',    icon: 'DocumentIcon' },
  active:    { label: 'Actif',      cls: 'text-green-700 bg-green-50 border-green-200',  icon: 'PlayIcon' },
  execution: { label: 'Exécution',  cls: 'text-blue-700 bg-blue-50 border-blue-200',     icon: 'CogIcon' },
  review:    { label: 'Révision',   cls: 'text-amber-700 bg-amber-50 border-amber-200',  icon: 'MagnifyingGlassIcon' },
  closed:    { label: 'Clôturé',    cls: 'text-slate-500 bg-slate-100 border-slate-200', icon: 'CheckCircleIcon' },
};

const STATUS_CONFIG: Record<ProjectStatus, { label: string; cls: string }> = {
  draft:    { label: 'Brouillon', cls: 'text-gray-600 bg-gray-100 border-gray-200' },
  active:   { label: 'Actif',     cls: 'text-green-700 bg-green-50 border-green-200' },
  paused:   { label: 'En pause',  cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  closed:   { label: 'Clôturé',   cls: 'text-slate-500 bg-slate-100 border-slate-200' },
  archived: { label: 'Archivé',   cls: 'text-slate-400 bg-slate-50 border-slate-100' },
};

const PARTICIPANT_STATUS_CONFIG: Record<ParticipantStatus, { label: string; cls: string; icon: string }> = {
  invited:  { label: 'Invité',   cls: 'text-amber-700 bg-amber-50 border-amber-200',  icon: 'EnvelopeIcon' },
  active:   { label: 'Actif',    cls: 'text-green-700 bg-green-50 border-green-200',  icon: 'CheckCircleIcon' },
  declined: { label: 'Refusé',   cls: 'text-red-600 bg-red-50 border-red-200',        icon: 'XCircleIcon' },
  removed:  { label: 'Retiré',   cls: 'text-slate-400 bg-slate-50 border-slate-100',  icon: 'MinusCircleIcon' },
};

const LOGISTICS_STEP_TYPE_LABELS: Record<LogisticsStepType, string> = {
  ramassage:    'Ramassage',
  chargement:   'Chargement',
  expedition:   'Expédition',
  transit:      'Transit',
  livraison:    'Livraison',
  preuve_finale:'Preuve finale',
};

const LOGISTICS_STATUS_CONFIG: Record<LogisticsStepStatus, { label: string; cls: string; icon: string }> = {
  planned:     { label: 'Planifié',    cls: 'text-gray-600 bg-gray-100 border-gray-200',    icon: 'CalendarIcon' },
  in_progress: { label: 'En cours',   cls: 'text-blue-700 bg-blue-50 border-blue-200',     icon: 'ArrowPathIcon' },
  completed:   { label: 'Complété',   cls: 'text-green-700 bg-green-50 border-green-200',  icon: 'CheckCircleIcon' },
  blocked:     { label: 'Bloqué',     cls: 'text-red-600 bg-red-50 border-red-200',        icon: 'ExclamationTriangleIcon' },
  cancelled:   { label: 'Annulé',     cls: 'text-slate-400 bg-slate-50 border-slate-100',  icon: 'XMarkIcon' },
};

const VALUE_REPORT_STATUS_CONFIG: Record<ValueReportStatus, { label: string; cls: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200' },
  generated: { label: 'Généré',     cls: 'text-blue-700 bg-blue-50 border-blue-200' },
  validated: { label: 'Validé',     cls: 'text-green-700 bg-green-50 border-green-200' },
  shared:    { label: 'Partagé',    cls: 'text-purple-700 bg-purple-50 border-purple-200' },
  archived:  { label: 'Archivé',    cls: 'text-slate-400 bg-slate-50 border-slate-100' },
};

const DOC_STATUS_CONFIG: Record<DocStatus, { label: string; cls: string }> = {
  draft:     { label: 'Brouillon', cls: 'text-gray-600 bg-gray-100 border-gray-200' },
  submitted: { label: 'Soumis',    cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  approved:  { label: 'Approuvé',  cls: 'text-green-700 bg-green-50 border-green-200' },
  rejected:  { label: 'Refusé',    cls: 'text-red-600 bg-red-50 border-red-200' },
  archived:  { label: 'Archivé',   cls: 'text-slate-400 bg-slate-50 border-slate-100' },
};

const PHASES: ProjectPhase[] = ['draft', 'active', 'execution', 'review', 'closed'];
const STATUSES: ProjectStatus[] = ['draft', 'active', 'paused', 'closed', 'archived'];
const LOGISTICS_STATUSES: LogisticsStepStatus[] = ['planned', 'in_progress', 'completed', 'blocked', 'cancelled'];

// ─── Sub-components ───────────────────────────────────────────────────────────

function PhaseBadge({ phase }: { phase: ProjectPhase }) {
  const cfg = PHASE_CONFIG[phase] ?? PHASE_CONFIG.draft;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2.5 py-1 border ${cfg.cls}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {cfg.label}
    </span>
  );
}

function StatusBadge({ status }: { status: ProjectStatus }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.draft;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

function ParticipantBadge({ status }: { status: ParticipantStatus }) {
  const cfg = PARTICIPANT_STATUS_CONFIG[status] ?? PARTICIPANT_STATUS_CONFIG.invited;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2 py-0.5 border ${cfg.cls}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={10} />
      {cfg.label}
    </span>
  );
}

function LogisticsStatusBadge({ status }: { status: LogisticsStepStatus }) {
  const cfg = LOGISTICS_STATUS_CONFIG[status] ?? LOGISTICS_STATUS_CONFIG.planned;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2 py-0.5 border ${cfg.cls}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={10} />
      {cfg.label}
    </span>
  );
}

// ─── Invite Organization Modal (E08-T02) ──────────────────────────────────────

interface InviteOrganizationModalProps {
  project: CcfProject;
  actorId: string;
  allOrganizations: Organization[];
  existingParticipantOrgIds: string[];
  onClose: () => void;
  onInvited: () => void;
}

type MandateScope = 'gouvernance' | 'operationnel' | 'financier' | 'technique' | 'verification' | 'ia';

const SCOPE_OPTIONS: MandateScope[] = ['gouvernance', 'operationnel', 'financier', 'technique', 'verification', 'ia'];
const SCOPE_LABELS: Record<MandateScope, string> = {
  gouvernance:  'Gouvernance',
  operationnel: 'Opérationnel',
  financier:    'Financier',
  technique:    'Technique',
  verification: 'Vérification',
  ia:           'IA',
};

// accept_project_invitation is always pre-checked and non-removable
const LOCKED_ACTION = 'accept_project_invitation';

function InviteOrganizationModal({
  project,
  actorId,
  allOrganizations,
  existingParticipantOrgIds,
  onClose,
  onInvited,
}: InviteOrganizationModalProps) {
  const supabase = createClient();

  const [mandateActions, setMandateActions] = useState<MandateAction[]>([]);
  const [form, setForm] = useState({
    receiver_org_id: '',
    mandate_scope: 'operationnel' as MandateScope,
    actions: [LOCKED_ACTION] as string[],
    start_date: '',
    end_date: '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Load mandate_actions catalogue on mount
  useEffect(() => {
    const load = async () => {
      const { data } = await supabase
        .from('mandate_actions')
        .select('code, label')
        .order('code');
      setMandateActions(data ?? []);
    };
    load();
  }, [supabase]);

  // Orgs available to invite: all except the coordinator org AND organisations
  // already participantes (invited/active/declined/removed) -- sans ce filtre,
  // re-inviter une organisation deja liee provoque une erreur brute "duplicate
  // key value violates unique constraint project_participants_..._key" au lieu
  // d'un message clair (meme classe de bug observee en direct sur
  // opportunity_capabilities pendant le test end-to-end, revue PR 13 juillet).
  const invitableOrgs = allOrganizations.filter(
    o => o.id !== project.coordinator_org_id && !existingParticipantOrgIds.includes(o.id)
  );

  const toggleAction = (code: string) => {
    // accept_project_invitation is locked — cannot be removed
    if (code === LOCKED_ACTION) return;
    setForm(prev => ({
      ...prev,
      actions: prev.actions.includes(code)
        ? prev.actions.filter(c => c !== code)
        : [...prev.actions, code],
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!form.receiver_org_id) { setError('Sélectionnez une organisation à inviter.'); return; }
    if (form.receiver_org_id === project.coordinator_org_id) {
      setError('L\'organisation coordinatrice est déjà participante.');
      return;
    }
    if (form.actions.length === 0) {
      setError('Sélectionnez au moins une action autorisée — le mandat ne peut pas avoir un tableau d\'actions vide.');
      return;
    }

    setSaving(true);

    // Step 1a: INSERT mandates — status='draft' obligatoire à l'insertion.
    // La policy RLS réellement active (mandates_insert_issuer_admin, migration
    // ccf_012/S06) exige WITH CHECK (is_org_admin(issuer_org_id) AND status =
    // 'draft') — insérer directement en 'pending_acceptance' viole cette policy
    // (INC-E08-01, trouvé en test live le 13 juillet : "new row violates
    // row-level security policy for table mandates"). Le passage à
    // 'pending_acceptance' se fait donc en une 2e étape via UPDATE, couverte
    // par mandates_update_issuance_by_issuer (USING status='draft' WITH CHECK
    // status='pending_acceptance') — même schéma en deux temps que handleSend
    // dans /mandats, un seul clic côté utilisateur malgré les deux appels DB.
    const { data: mandate, error: mandateErr } = await supabase
      .from('mandates')
      .insert({
        issuer_org_id: project.coordinator_org_id,
        receiver_org_id: form.receiver_org_id,
        mandate_scope: form.mandate_scope,
        permissions: { actions: form.actions },
        status: 'draft',
        start_date: form.start_date || null,
        end_date: form.end_date || null,
      })
      .select('id')
      .single();

    if (mandateErr) {
      const msg = (mandateErr as { message?: string }).message ?? String(mandateErr);
      // Surface validate_mandate_permissions trigger error clearly
      if (msg.includes('actions') || msg.includes('permissions') || msg.includes('mandate_actions')) {
        setError('Actions invalides — utilisez uniquement les actions du catalogue autorisé.');
      } else {
        setError(`Erreur lors de la création du mandat : ${msg}`);
      }
      setSaving(false);
      return;
    }

    const mandateId = mandate.id;

    // Step 1b: UPDATE mandates SET status='pending_acceptance' — transition
    // couverte par mandates_update_issuance_by_issuer, voir commentaire ci-dessus.
    const { error: sendErr } = await supabase
      .from('mandates')
      .update({ status: 'pending_acceptance', updated_at: new Date().toISOString() })
      .eq('id', mandateId);

    if (sendErr) {
      const msg = (sendErr as { message?: string }).message ?? String(sendErr);
      setError(`Mandat créé (${mandateId.slice(0, 8)}…) mais erreur lors de l'envoi : ${msg}`);
      setSaving(false);
      return;
    }

    // Step 2: INSERT project_participants — status='invited', role='contributeur'
    const { error: participantErr } = await supabase
      .from('project_participants')
      .insert({
        project_id: project.id,
        organization_id: form.receiver_org_id,
        project_role: 'contributeur',
        status: 'invited',
        mandate_id: mandateId,
      });

    if (participantErr) {
      const msg = (participantErr as { message?: string }).message ?? String(participantErr);
      setError(`Mandat créé (${mandateId.slice(0, 8)}…) mais erreur lors de l'ajout du participant : ${msg}`);
      setSaving(false);
      return;
    }

    // Step 3: INSERT business_events — mandate_issued (same structure as handleSend in mandats/page.tsx)
    await supabase.from('business_events').insert({
      event_type: 'mandate_issued',
      object_type: 'mandate',
      object_id: mandateId,
      actor_id: actorId,
      organization_id: project.coordinator_org_id,
      payload: {
        receiver_org_id: form.receiver_org_id,
        project_id: project.id,
        scope: form.mandate_scope,
      },
    });

    setSaving(false);
    onInvited();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <div>
            <h2 className="text-base font-bold text-foreground">Inviter une organisation</h2>
            <p className="text-xs text-muted-foreground mt-0.5">
              Un mandat d'invitation sera créé et envoyé directement
            </p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Organisation to invite */}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">
              Organisation à inviter <span className="text-red-500">*</span>
            </label>
            {invitableOrgs.length === 0 ? (
              <p className="text-sm text-muted-foreground italic">
                Aucune organisation disponible — toutes les organisations existantes participent déjà à ce projet, ou aucune autre organisation n'existe.
              </p>
            ) : (
              <select
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                value={form.receiver_org_id}
                onChange={e => setForm(p => ({ ...p, receiver_org_id: e.target.value }))}
                required
              >
                <option value="">— Sélectionner une organisation —</option>
                {invitableOrgs.map(o => (
                  <option key={o.id} value={o.id}>{o.name}</option>
                ))}
              </select>
            )}
          </div>

          {/* Mandate scope */}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">
              Portée du mandat <span className="text-red-500">*</span>
            </label>
            <select
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              value={form.mandate_scope}
              onChange={e => setForm(p => ({ ...p, mandate_scope: e.target.value as MandateScope }))}
            >
              {SCOPE_OPTIONS.map(s => (
                <option key={s} value={s}>{SCOPE_LABELS[s]}</option>
              ))}
            </select>
          </div>

          {/* Actions — ActionPicker with accept_project_invitation locked */}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-2">
              Actions autorisées <span className="text-red-500">*</span>
            </label>
            {mandateActions.length === 0 ? (
              <div className="flex items-center gap-2 text-sm text-muted-foreground">
                <div className="w-4 h-4 border-2 border-primary border-t-transparent rounded-full animate-spin" />
                Chargement du catalogue…
              </div>
            ) : (
              <div className="grid grid-cols-1 gap-1.5 max-h-48 overflow-y-auto pr-1">
                {mandateActions.map(a => {
                  const isLocked = a.code === LOCKED_ACTION;
                  const isSelected = form.actions.includes(a.code);
                  return (
                    <label
                      key={a.code}
                      className={`flex items-center gap-2.5 px-3 py-2 rounded-lg border text-sm transition-colors ${
                        isLocked ? 'cursor-not-allowed opacity-80' : 'cursor-pointer'
                      } ${
                        isSelected
                          ? 'border-primary bg-primary/5 text-primary font-medium' :'border-border bg-card text-foreground hover:bg-muted'
                      }`}
                    >
                      <input
                        type="checkbox"
                        className="sr-only"
                        checked={isSelected}
                        onChange={() => toggleAction(a.code)}
                        disabled={isLocked}
                      />
                      <span
                        className={`w-4 h-4 rounded border flex items-center justify-center flex-shrink-0 ${
                          isSelected ? 'bg-primary border-primary' : 'border-border'
                        }`}
                      >
                        {isSelected && (
                          <Icon name="CheckIcon" size={10} className="text-primary-foreground" />
                        )}
                      </span>
                      <span className="truncate flex-1">{a.label}</span>
                      {isLocked && (
                        <span className="text-xs text-muted-foreground ml-auto flex-shrink-0 italic">requis</span>
                      )}
                    </label>
                  );
                })}
              </div>
            )}
          </div>

          {/* Optional dates */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-semibold text-foreground mb-1">Date de début</label>
              <input
                type="date"
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                value={form.start_date}
                onChange={e => setForm(p => ({ ...p, start_date: e.target.value }))}
              />
            </div>
            <div>
              <label className="block text-sm font-semibold text-foreground mb-1">Date de fin</label>
              <input
                type="date"
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                value={form.end_date}
                onChange={e => setForm(p => ({ ...p, end_date: e.target.value }))}
              />
            </div>
          </div>

          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}

          <div className="flex justify-end gap-3 pt-1">
            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              className="px-4 py-2 rounded-lg text-sm font-semibold hover:bg-muted transition-colors disabled:opacity-50"
            >
              Annuler
            </button>
            <button
              type="submit"
              disabled={saving || invitableOrgs.length === 0}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
            >
              {saving ? (
                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                <Icon name="EnvelopeIcon" size={16} />
              )}
              {saving ? 'Invitation en cours…' : 'Inviter'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Document Uploader (adapted from S07, pre-filled object_type/object_id) ──

interface ProjectDocUploaderProps {
  projectId: string;
  myAdminOrgIds: string[];
  organizations: Organization[];
  actorId: string;
  onClose: () => void;
  onUploaded: () => void;
}

function ProjectDocumentUploader({ projectId, myAdminOrgIds, organizations, actorId, onClose, onUploaded }: ProjectDocUploaderProps) {
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [form, setForm] = useState({
    owner_org_id: myAdminOrgIds[0] ?? '',
    title: '',
    category: '',
    version: '1.0',
    visibility: 'project' as DocVisibility, // default to 'project' since object_type is always 'project' here
  });
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (!form.owner_org_id) { setError('Sélectionnez l\'organisation propriétaire'); return; }
    if (!form.title.trim()) { setError('Le titre est obligatoire'); return; }
    if (!file) { setError('Sélectionnez un fichier à déposer'); return; }

    setUploading(true);
    try {
      const storagePath = `documents/${form.owner_org_id}/${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;
      const { error: storageErr } = await supabase.storage
        .from('documents')
        .upload(storagePath, file, { upsert: false });
      if (storageErr) throw new Error(`Erreur de stockage : ${storageErr.message}`);

      const { error: insertErr } = await supabase.from('documents').insert({
        owner_org_id: form.owner_org_id,
        object_type: 'project',
        object_id: projectId,
        title: form.title.trim(),
        category: form.category.trim() || null,
        version: form.version.trim() || '1.0',
        visibility: form.visibility,
        storage_path: storagePath,
        status: 'draft',
      });
      if (insertErr) throw insertErr;

      onUploaded();
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors du dépôt'));
    } finally {
      setUploading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl shadow-xl w-full max-w-md max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between px-6 py-4 border-b border-border">
          <div>
            <h2 className="text-base font-bold text-foreground">Déposer un document</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Rattaché à ce projet · Statut initial : Brouillon</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4">
          <div>
            <label className="block text-xs font-medium text-foreground mb-1.5">Organisation propriétaire *</label>
            <select
              value={form.owner_org_id}
              onChange={(e) => setForm((p) => ({ ...p, owner_org_id: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              required
            >
              <option value="">Sélectionner…</option>
              {organizations.filter((o) => myAdminOrgIds.includes(o.id)).map((o) => (
                <option key={o.id} value={o.id}>{o.name}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-foreground mb-1.5">Titre *</label>
            <input
              type="text"
              value={form.title}
              onChange={(e) => setForm((p) => ({ ...p, title: e.target.value }))}
              placeholder="Titre du document"
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              required
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-foreground mb-1.5">Catégorie</label>
              <input
                type="text"
                value={form.category}
                onChange={(e) => setForm((p) => ({ ...p, category: e.target.value }))}
                placeholder="ex. Contrat…"
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-foreground mb-1.5">Version</label>
              <input
                type="text"
                value={form.version}
                onChange={(e) => setForm((p) => ({ ...p, version: e.target.value }))}
                placeholder="1.0"
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              />
            </div>
          </div>
          <div>
            <label className="block text-xs font-medium text-foreground mb-1.5">Visibilité *</label>
            <select
              value={form.visibility}
              onChange={(e) => setForm((p) => ({ ...p, visibility: e.target.value as DocVisibility }))}
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
            >
              <option value="project">Projet (participants actifs)</option>
              <option value="organization_private">Privé (organisation)</option>
              <option value="confidential">Confidentiel</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-foreground mb-1.5">Fichier *</label>
            <div
              onClick={() => fileInputRef.current?.click()}
              className={`flex flex-col items-center justify-center gap-2 px-4 py-6 rounded-lg border-2 border-dashed cursor-pointer transition-colors ${
                file ? 'border-primary bg-primary/5' : 'border-border hover:border-primary/50 hover:bg-muted'
              }`}
            >
              <Icon name={file ? 'DocumentCheckIcon' : 'ArrowUpTrayIcon'} size={24} className={file ? 'text-primary' : 'text-muted-foreground'} />
              {file ? (
                <div className="text-center">
                  <p className="text-sm font-medium text-foreground">{file.name}</p>
                  <p className="text-xs text-muted-foreground">{(file.size / 1024).toFixed(1)} Ko</p>
                </div>
              ) : (
                <p className="text-sm text-muted-foreground">Cliquez pour sélectionner un fichier</p>
              )}
            </div>
            <input ref={fileInputRef} type="file" className="hidden" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
          </div>
          {error && (
            <div className="flex items-start gap-2 px-3 py-2.5 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
              <Icon name="ExclamationCircleIcon" size={16} className="flex-shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="flex-1 px-4 py-2.5 rounded-lg border border-border text-sm font-medium text-foreground hover:bg-muted transition-colors">
              Annuler
            </button>
            <button
              type="submit"
              disabled={uploading}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
            >
              {uploading ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> : <Icon name="ArrowUpTrayIcon" size={16} />}
              {uploading ? 'Dépôt en cours…' : 'Déposer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Logistics Step Card ──────────────────────────────────────────────────────

interface LogisticsStepCardProps {
  step: LogisticsStep;
  canEdit: boolean;
  actorId: string;
  coordinatorOrgId: string;
  onUpdated: () => void;
}

function LogisticsStepCard({ step, canEdit, actorId, coordinatorOrgId, onUpdated }: LogisticsStepCardProps) {
  const supabase = createClient();
  const [editing, setEditing] = useState(false);
  const [newStatus, setNewStatus] = useState<LogisticsStepStatus>(step.status);
  const [actualDate, setActualDate] = useState(step.actual_date ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSave = async () => {
    setSaving(true);
    setError(null);
    try {
      const { error: err } = await supabase
        .from('logistics_steps')
        .update({
          status: newStatus,
          actual_date: actualDate || null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', step.id);

      if (err) {
        // RLS may reject if user lacks terrain/admin permission on responsible org
        if (err.code === '42501' || err.message?.toLowerCase().includes('policy')) {
          setError('Mise à jour refusée : vous devez être admin ou avoir un profil terrain dans l\'organisation responsable.');
        } else {
          throw err;
        }
        setSaving(false);
        return;
      }

      // Manual business_event insert — no RPC handles this
      await supabase.from('business_events').insert({
        event_type: 'logistics_step_updated',
        object_type: 'logistics_step',
        object_id: step.id,
        actor_id: actorId,
        organization_id: coordinatorOrgId,
        payload: { step_type: step.step_type, old_status: step.status, new_status: newStatus },
      });

      setEditing(false);
      onUpdated();
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors de la mise à jour'));
    } finally {
      setSaving(false);
    }
  };

  const cfg = LOGISTICS_STATUS_CONFIG[step.status];

  return (
    <div className="bg-card border border-border rounded-xl p-4">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div>
          <p className="text-sm font-semibold text-foreground">{LOGISTICS_STEP_TYPE_LABELS[step.step_type] ?? step.step_type}</p>
          {step.responsible_org && (
            <p className="text-xs text-muted-foreground mt-0.5 flex items-center gap-1">
              <Icon name="BuildingOffice2Icon" size={12} />
              {step.responsible_org.name}
            </p>
          )}
        </div>
        <LogisticsStatusBadge status={step.status} />
      </div>

      <div className="grid grid-cols-2 gap-2 text-xs text-muted-foreground mb-3">
        {step.planned_date && (
          <div className="flex items-center gap-1">
            <Icon name="CalendarIcon" size={12} />
            <span>Prévu : {new Date(step.planned_date).toLocaleDateString('fr-CA')}</span>
          </div>
        )}
        {step.actual_date && (
          <div className="flex items-center gap-1">
            <Icon name="CheckCircleIcon" size={12} className="text-green-600" />
            <span>Réel : {new Date(step.actual_date).toLocaleDateString('fr-CA')}</span>
          </div>
        )}
      </div>

      {editing ? (
        <div className="space-y-3 pt-3 border-t border-border">
          <div>
            <label className="block text-xs font-medium text-foreground mb-1">Statut</label>
            <select
              value={newStatus}
              onChange={(e) => setNewStatus(e.target.value as LogisticsStepStatus)}
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
            >
              {LOGISTICS_STATUSES.map((s) => (
                <option key={s} value={s}>{LOGISTICS_STATUS_CONFIG[s].label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-foreground mb-1">Date réelle</label>
            <input
              type="date"
              value={actualDate}
              onChange={(e) => setActualDate(e.target.value)}
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
            />
          </div>
          {error && (
            <div className="flex items-start gap-2 px-3 py-2 bg-red-50 border border-red-200 rounded-lg text-red-700 text-xs">
              <Icon name="ExclamationCircleIcon" size={14} className="flex-shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}
          <div className="flex gap-2">
            <button
              onClick={() => { setEditing(false); setError(null); setNewStatus(step.status); setActualDate(step.actual_date ?? ''); }}
              className="flex-1 px-3 py-1.5 rounded-lg border border-border text-xs font-medium text-foreground hover:bg-muted transition-colors"
            >
              Annuler
            </button>
            <button
              onClick={handleSave}
              disabled={saving}
              className="flex-1 flex items-center justify-center gap-1 px-3 py-1.5 bg-primary text-primary-foreground rounded-lg text-xs font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
            >
              {saving ? <div className="w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin" /> : null}
              Enregistrer
            </button>
          </div>
        </div>
      ) : (
        canEdit && (
          <button
            onClick={() => setEditing(true)}
            className="flex items-center gap-1.5 text-xs text-primary hover:underline mt-1"
          >
            <Icon name="PencilSquareIcon" size={12} />
            Modifier
          </button>
        )
      )}
    </div>
  );
}

// ─── Add Logistics Step Modal ─────────────────────────────────────────────────

interface AddLogisticsStepModalProps {
  project: CcfProject;
  participants: ProjectParticipant[];
  onClose: () => void;
  onCreated: () => void;
}

function AddLogisticsStepModal({ project, participants, onClose, onCreated }: AddLogisticsStepModalProps) {
  const supabase = createClient();

  // Active participant organizations (including coordinator who is always active)
  const activeParticipantOrgs: Organization[] = participants
    .filter(p => p.status === 'active')
    .map(p => ({ id: p.organization_id, name: p.organization?.name ?? p.organization_id.slice(0, 8) }));

  const [form, setForm] = useState({
    step_type: '' as LogisticsStepType | '',
    responsible_org_id: '',
    planned_date: '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!form.step_type) { setError('Sélectionnez un type d\'étape.'); return; }
    if (!form.responsible_org_id) { setError('Sélectionnez une organisation responsable.'); return; }

    setSaving(true);

    const { error: insertErr } = await supabase
      .from('logistics_steps')
      .insert({
        project_id: project.id,
        step_type: form.step_type,
        responsible_org_id: form.responsible_org_id,
        planned_date: form.planned_date || null,
        status: 'planned',
      });

    if (insertErr) {
      const msg = (insertErr as { message?: string }).message ?? String(insertErr);
      setError(`Erreur lors de la création : ${msg}`);
      setSaving(false);
      return;
    }

    setSaving(false);
    onCreated();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-5 border-b border-border sticky top-0 bg-card z-10">
          <div>
            <h2 className="text-base font-bold text-foreground">Ajouter une étape logistique</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Statut initial : Planifié</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Step type */}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">
              Type d&apos;étape <span className="text-red-500">*</span>
            </label>
            <select
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              value={form.step_type}
              onChange={e => setForm(p => ({ ...p, step_type: e.target.value as LogisticsStepType }))}
              required
            >
              <option value="">— Sélectionner un type —</option>
              {(Object.entries(LOGISTICS_STEP_TYPE_LABELS) as [LogisticsStepType, string][]).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </div>

          {/* Responsible org — active participants only */}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">
              Organisation responsable <span className="text-red-500">*</span>
            </label>
            {activeParticipantOrgs.length === 0 ? (
              <p className="text-sm text-muted-foreground italic">Aucun participant actif disponible.</p>
            ) : (
              <select
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                value={form.responsible_org_id}
                onChange={e => setForm(p => ({ ...p, responsible_org_id: e.target.value }))}
                required
              >
                <option value="">— Sélectionner une organisation —</option>
                {activeParticipantOrgs.map(o => (
                  <option key={o.id} value={o.id}>{o.name}</option>
                ))}
              </select>
            )}
          </div>

          {/* Planned date (optional) */}
          <div>
            <label className="block text-sm font-semibold text-foreground mb-1">Date planifiée</label>
            <input
              type="date"
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              value={form.planned_date}
              onChange={e => setForm(p => ({ ...p, planned_date: e.target.value }))}
            />
          </div>

          {error && (
            <div className="rounded-lg bg-red-50 border border-red-200 px-3 py-2 flex items-start gap-2">
              <Icon name="ExclamationTriangleIcon" size={14} className="text-red-500 mt-0.5 flex-shrink-0" />
              <p className="text-sm text-red-700">{error}</p>
            </div>
          )}

          <div className="flex justify-end gap-3 pt-1">
            <button
              type="button"
              onClick={onClose}
              disabled={saving}
              className="px-4 py-2 rounded-lg text-sm font-semibold hover:bg-muted transition-colors disabled:opacity-50"
            >
              Annuler
            </button>
            <button
              type="submit"
              disabled={saving || activeParticipantOrgs.length === 0}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
            >
              {saving ? (
                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                <Icon name="PlusIcon" size={16} />
              )}
              {saving ? 'Création en cours…' : 'Ajouter'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

type ActiveTab = 'participants' | 'logistics' | 'documents' | 'risks' | 'value_report' | 'history';

export default function ProjetDetailPage() {
  const params = useParams();
  const router = useRouter();
  const projectId = params?.id as string;
  const supabase = createClient();

  // Core data
  const [project, setProject] = useState<CcfProject | null>(null);
  const [participants, setParticipants] = useState<ProjectParticipant[]>([]);
  const [logisticsSteps, setLogisticsSteps] = useState<LogisticsStep[]>([]);
  const [documents, setDocuments] = useState<Document[]>([]);
  const [valueReports, setValueReports] = useState<ValueReport[]>([]);
  const [organizations, setOrganizations] = useState<Organization[]>([]);

  // User context
  const [actorId, setActorId] = useState<string>('');
  const [myAdminOrgIds, setMyAdminOrgIds] = useState<string[]>([]);
  const [myMemberships, setMyMemberships] = useState<OrgMembership[]>([]);

  // UI state
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<ActiveTab>('participants');
  const [showDocUploader, setShowDocUploader] = useState(false);
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [showAddStepModal, setShowAddStepModal] = useState(false);

  // Phase/status edit
  const [editingPhase, setEditingPhase] = useState(false);
  const [newPhase, setNewPhase] = useState<ProjectPhase>('draft');
  const [newStatus, setNewStatus] = useState<ProjectStatus>('draft');
  const [phaseLoading, setPhaseLoading] = useState(false);

  // Value report form
  const [showVRForm, setShowVRForm] = useState(false);
  const [vrForm, setVrForm] = useState({ volume: '', coordination_value: '', notes: '', status: 'draft' as ValueReportStatus });
  const [vrLoading, setVrLoading] = useState(false);
  const [vrError, setVrError] = useState<string | null>(null);
  const [editingVR, setEditingVR] = useState<ValueReport | null>(null);

  // ─── Data loading ──────────────────────────────────────────────────────────

  const loadData = useCallback(async () => {
    if (!projectId) return;
    setLoading(true);
    setError(null);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setError('Non authentifié'); setLoading(false); return; }
      setActorId(user.id);

      // Load memberships
      const { data: memberships } = await supabase
        .from('organization_members')
        .select('organization_id, org_role, operational_profile, status')
        .eq('user_id', user.id)
        .eq('status', 'active');

      const mems: OrgMembership[] = memberships ?? [];
      setMyMemberships(mems);
      const adminIds = mems
        .filter((m) => m.org_role === 'admin' || m.org_role === 'owner')
        .map((m) => m.organization_id);
      setMyAdminOrgIds(adminIds);

      // Load project
      const { data: projectData, error: projectErr } = await supabase
        .from('ccf_projects')
        .select(`
          *,
          coordinator_org:organizations!ccf_projects_coordinator_org_id_fkey(name),
          opportunity:opportunities!ccf_projects_opportunity_id_fkey(title)
        `)
        .eq('id', projectId)
        .single();

      if (projectErr) throw projectErr;
      setProject(projectData as CcfProject);
      setNewPhase((projectData as CcfProject).phase);
      setNewStatus((projectData as CcfProject).status);

      // Load participants
      const { data: participantsData } = await supabase
        .from('project_participants')
        .select(`
          *,
          organization:organizations!project_participants_organization_id_fkey(name)
        `)
        .eq('project_id', projectId)
        .order('created_at', { ascending: true });
      setParticipants((participantsData ?? []) as ProjectParticipant[]);

      // Load logistics steps
      const { data: logisticsData } = await supabase
        .from('logistics_steps')
        .select(`
          *,
          responsible_org:organizations!logistics_steps_responsible_org_id_fkey(name)
        `)
        .eq('project_id', projectId)
        .order('created_at', { ascending: true });
      setLogisticsSteps((logisticsData ?? []) as LogisticsStep[]);

      // Load documents (object_type='project', object_id=projectId)
      const { data: docsData } = await supabase
        .from('documents')
        .select('*')
        .eq('object_type', 'project')
        .eq('object_id', projectId)
        .order('created_at', { ascending: false });
      setDocuments((docsData ?? []) as Document[]);

      // Load value reports
      const { data: vrData } = await supabase
        .from('value_reports')
        .select('*')
        .eq('project_id', projectId)
        .order('created_at', { ascending: false });
      setValueReports((vrData ?? []) as ValueReport[]);

      // Load organizations for doc uploader
      const { data: orgsData } = await supabase
        .from('organizations')
        .select('id, name')
        .order('name');
      setOrganizations(orgsData ?? []);

    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur de chargement'));
    } finally {
      setLoading(false);
    }
  }, [projectId, supabase]);

  useEffect(() => { loadData(); }, [loadData]);

  // ─── Derived: is coordinator admin ────────────────────────────────────────

  const isCoordinatorAdmin = project ? myAdminOrgIds.includes(project.coordinator_org_id) : false;

  // ─── Derived: can edit logistics step ─────────────────────────────────────
  // RLS: coordinator admin OR member of responsible org with admin/terrain profile
  const canEditStep = (step: LogisticsStep): boolean => {
    if (isCoordinatorAdmin) return true;
    if (!step.responsible_org_id) return false;
    const membership = myMemberships.find((m) => m.organization_id === step.responsible_org_id);
    if (!membership) return false;
    return membership.org_role === 'admin' || membership.org_role === 'owner' || membership.operational_profile === 'terrain';
  };

  // ─── Phase / Status change ─────────────────────────────────────────────────

  const handlePhaseStatusSave = async () => {
    if (!project) return;
    setPhaseLoading(true);
    try {
      const phaseChanged = newPhase !== project.phase;
      const { error: err } = await supabase
        .from('ccf_projects')
        .update({
          phase: newPhase,
          status: newStatus,
          updated_at: new Date().toISOString(),
        })
        .eq('id', project.id);
      if (err) throw err;

      // Manual business_event for phase change — no RPC handles this
      if (phaseChanged) {
        await supabase.from('business_events').insert({
          event_type: 'project_phase_changed',
          object_type: 'project',
          object_id: project.id,
          actor_id: actorId,
          organization_id: project.coordinator_org_id,
          payload: { old_phase: project.phase, new_phase: newPhase, new_status: newStatus },
        });
      }

      setEditingPhase(false);
      await loadData();
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors de la mise à jour'));
    } finally {
      setPhaseLoading(false);
    }
  };

  // ─── Invitation actions (reuse S06 RPCs — no manual business_event) ────────

  const handleAcceptInvitation = async (participant: ProjectParticipant) => {
    if (!participant.mandate_id) return;
    setActionLoading(participant.id);
    try {
      const { error: err } = await supabase.rpc('accept_project_invitation', {
        p_mandate_id: participant.mandate_id,
        p_project_id: projectId,
      });
      if (err) throw err;
      // DO NOT insert business_event manually — the RPC already does it server-side
      await loadData();
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors de l\'acceptation'));
    } finally {
      setActionLoading(null);
    }
  };

  const handleDeclineInvitation = async (participant: ProjectParticipant) => {
    if (!participant.mandate_id) return;
    setActionLoading(participant.id);
    try {
      const { error: err } = await supabase.rpc('decline_project_invitation', {
        p_mandate_id: participant.mandate_id,
      });
      if (err) throw err;
      // DO NOT insert business_event manually — the RPC already does it server-side
      await loadData();
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors du refus'));
    } finally {
      setActionLoading(null);
    }
  };

  // ─── Value report save ─────────────────────────────────────────────────────

  const handleVRSave = async () => {
    if (!project) return;
    setVrLoading(true);
    setVrError(null);
    try {
      const payload = {
        project_id: project.id,
        volume: vrForm.volume ? parseFloat(vrForm.volume) : null,
        coordination_value: vrForm.coordination_value ? parseFloat(vrForm.coordination_value) : null,
        notes: vrForm.notes.trim() || null,
        status: vrForm.status,
      };

      let valueReportId: string = editingVR?.id ?? '';
      if (editingVR) {
        const { error: err } = await supabase
          .from('value_reports')
          .update({ ...payload, updated_at: new Date().toISOString() })
          .eq('id', editingVR.id);
        if (err) throw err;
      } else {
        const { data: inserted, error: err } = await supabase
          .from('value_reports')
          .insert(payload)
          .select('id')
          .single();
        if (err) throw err;
        valueReportId = inserted.id;
      }

      // Manual business_event — no RPC handles this
      // INC-S05-02 : object_id doit référencer la ligne value_reports elle-même
      // (convention établie en S07/ccf_006e : object_id = id de l'objet visé,
      // jamais l'id du projet parent), pas project.id.
      await supabase.from('business_events').insert({
        event_type: 'value_report_generated',
        object_type: 'value_report',
        object_id: valueReportId,
        actor_id: actorId,
        organization_id: project.coordinator_org_id,
        payload: { project_id: project.id, status: vrForm.status },
      });

      setShowVRForm(false);
      setEditingVR(null);
      setVrForm({ volume: '', coordination_value: '', notes: '', status: 'draft' });
      await loadData();
    } catch (e: unknown) {
      setVrError(getErrorMessage(e, 'Erreur lors de l\'enregistrement'));
    } finally {
      setVrLoading(false);
    }
  };

  // ─── Risks (frontend-calculated, no DB table) ──────────────────────────────

  const risks = React.useMemo(
    () => computeProjectRisks(logisticsSteps, project, participants),
    [logisticsSteps, project, participants],
  );

  // ─── Render ────────────────────────────────────────────────────────────────

  if (loading) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center min-h-[60vh]">
          <div className="flex flex-col items-center gap-3 text-muted-foreground">
            <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
            <span className="text-sm">Chargement du projet…</span>
          </div>
        </div>
      </AppLayout>
    );
  }

  if (error && !project) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center min-h-[60vh]">
          <div className="flex flex-col items-center gap-3 text-red-600">
            <Icon name="ExclamationCircleIcon" size={32} />
            <p className="text-sm font-medium">{error}</p>
            <button onClick={() => router.back()} className="text-xs text-primary hover:underline">← Retour</button>
          </div>
        </div>
      </AppLayout>
    );
  }

  if (!project) return null;

  const TABS: { id: ActiveTab; label: string; icon: string; count?: number }[] = [
    { id: 'participants', label: 'Participants', icon: 'UsersIcon', count: participants.length },
    { id: 'logistics', label: 'Logistique', icon: 'TruckIcon', count: logisticsSteps.length },
    { id: 'documents', label: 'Documents', icon: 'FolderOpenIcon', count: documents.length },
    { id: 'risks', label: 'Risques', icon: 'ExclamationTriangleIcon', count: risks.length },
    { id: 'value_report', label: 'Rapport de valeur', icon: 'ChartBarIcon', count: valueReports.length },
    { id: 'history', label: 'Historique', icon: 'ClockIcon' },
  ];

  return (
    <AppLayout>
      <div className="max-w-6xl mx-auto px-4 py-6 space-y-6">

        {/* ── Header ── */}
        <div className="flex items-start gap-4">
          <button
            onClick={() => router.back()}
            className="mt-1 p-1.5 rounded-lg hover:bg-muted transition-colors text-muted-foreground"
            aria-label="Retour"
          >
            <Icon name="ArrowLeftIcon" size={18} />
          </button>
          <div className="flex-1 min-w-0">
            <div className="flex flex-wrap items-center gap-2 mb-1">
              <PhaseBadge phase={project.phase} />
              <StatusBadge status={project.status} />
              {risks.length > 0 && (
                <span className="inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2 py-0.5 border text-red-600 bg-red-50 border-red-200">
                  <Icon name="ExclamationTriangleIcon" size={10} />
                  {risks.length} risque{risks.length > 1 ? 's' : ''}
                </span>
              )}
            </div>
            <h1 className="text-xl font-bold text-foreground truncate">
              {project.opportunity?.title ?? `Projet ${project.id.slice(0, 8)}`}
            </h1>
            <p className="text-sm text-muted-foreground mt-0.5">
              {project.coordinator_org?.name ?? '—'}
              {project.start_date && ` · Début : ${new Date(project.start_date).toLocaleDateString('fr-CA')}`}
              {project.target_end_date && ` · Cible : ${new Date(project.target_end_date).toLocaleDateString('fr-CA')}`}
            </p>
          </div>

          {/* Phase/Status edit (coordinator admin only) */}
          {isCoordinatorAdmin && !editingPhase && (
            <button
              onClick={() => setEditingPhase(true)}
              className="flex items-center gap-1.5 px-3 py-2 rounded-lg border border-border text-sm font-medium text-foreground hover:bg-muted transition-colors"
            >
              <Icon name="PencilSquareIcon" size={16} />
              Modifier phase
            </button>
          )}
        </div>

        {/* ── Phase/Status edit panel ── */}
        {editingPhase && isCoordinatorAdmin && (
          <div className="bg-card border border-border rounded-xl p-5">
            <h3 className="text-sm font-semibold text-foreground mb-4">Modifier la phase et le statut</h3>
            <div className="grid grid-cols-2 gap-4 mb-4">
              <div>
                <label className="block text-xs font-medium text-foreground mb-1.5">Phase</label>
                <select
                  value={newPhase}
                  onChange={(e) => setNewPhase(e.target.value as ProjectPhase)}
                  className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  {PHASES.map((p) => (
                    <option key={p} value={p}>{PHASE_CONFIG[p].label}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-foreground mb-1.5">Statut</label>
                <select
                  value={newStatus}
                  onChange={(e) => setNewStatus(e.target.value as ProjectStatus)}
                  className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                >
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>{STATUS_CONFIG[s].label}</option>
                  ))}
                </select>
              </div>
            </div>
            {error && (
              <div className="flex items-center gap-2 px-3 py-2 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm mb-3">
                <Icon name="ExclamationCircleIcon" size={14} />
                {error}
              </div>
            )}
            <div className="flex gap-3">
              <button
                onClick={() => { setEditingPhase(false); setError(null); setNewPhase(project.phase); setNewStatus(project.status); }}
                className="px-4 py-2 rounded-lg border border-border text-sm font-medium text-foreground hover:bg-muted transition-colors"
              >
                Annuler
              </button>
              <button
                onClick={handlePhaseStatusSave}
                disabled={phaseLoading}
                className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
              >
                {phaseLoading ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> : null}
                Enregistrer
              </button>
            </div>
          </div>
        )}

        {/* ── Global error banner ── */}
        {error && (
          <div className="flex items-center gap-2 px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-red-700 text-sm">
            <Icon name="ExclamationCircleIcon" size={16} />
            {error}
            <button onClick={() => setError(null)} className="ml-auto p-0.5 hover:bg-red-100 rounded">
              <Icon name="XMarkIcon" size={14} />
            </button>
          </div>
        )}

        {/* ── Tabs ── */}
        <div className="border-b border-border">
          <div className="flex gap-1 overflow-x-auto">
            {TABS.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={`flex items-center gap-1.5 px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-primary text-primary' :'border-transparent text-muted-foreground hover:text-foreground'
                }`}
              >
                <Icon name={tab.icon as Parameters<typeof Icon>[0]['name']} size={14} />
                {tab.label}
                {tab.count !== undefined && tab.count > 0 && (
                  <span className={`text-[11px] font-semibold px-1.5 py-0.5 rounded-full ${
                    activeTab === tab.id ? 'bg-primary/10 text-primary' : 'bg-muted text-muted-foreground'
                  }`}>
                    {tab.count}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>

        {/* ── Tab content ── */}

        {/* PARTICIPANTS */}
        {activeTab === 'participants' && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-foreground">Participants ({participants.length})</h2>
              {isCoordinatorAdmin && (
                <button
                  onClick={() => setShowInviteModal(true)}
                  className="flex items-center gap-1.5 px-3 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
                >
                  <Icon name="UserPlusIcon" size={14} />
                  Inviter une organisation
                </button>
              )}
            </div>
            {participants.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
                <Icon name="UsersIcon" size={32} />
                <p className="text-sm">Aucun participant pour ce projet.</p>
              </div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                {participants.map((p) => (
                  <div key={p.id} className="bg-card border border-border rounded-xl p-4">
                    <div className="flex items-start justify-between gap-3 mb-2">
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-foreground truncate">
                          {p.organization?.name ?? p.organization_id.slice(0, 8)}
                        </p>
                        <p className="text-xs text-muted-foreground mt-0.5 capitalize">{p.project_role}</p>
                      </div>
                      <ParticipantBadge status={p.status} />
                    </div>
                    {p.mandate_id && p.status === 'invited' && (
                      <div className="flex gap-2 mt-3 pt-3 border-t border-border">
                        <button
                          onClick={() => handleAcceptInvitation(p)}
                          disabled={actionLoading === p.id}
                          className="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 bg-green-600 text-white rounded-lg text-xs font-medium hover:bg-green-700 disabled:opacity-50 transition-colors"
                        >
                          {actionLoading === p.id ? <div className="w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin" /> : <Icon name="CheckIcon" size={12} />}
                          Accepter
                        </button>
                        <button
                          onClick={() => handleDeclineInvitation(p)}
                          disabled={actionLoading === p.id}
                          className="flex-1 flex items-center justify-center gap-1.5 px-3 py-1.5 border border-red-200 text-red-600 rounded-lg text-xs font-medium hover:bg-red-50 disabled:opacity-50 transition-colors"
                        >
                          <Icon name="XMarkIcon" size={12} />
                          Refuser
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* LOGISTICS */}
        {activeTab === 'logistics' && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-foreground">Étapes logistiques ({logisticsSteps.length})</h2>
              {isCoordinatorAdmin && (
                <button
                  onClick={() => setShowAddStepModal(true)}
                  className="flex items-center gap-1.5 px-3 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
                >
                  <Icon name="PlusIcon" size={14} />
                  Ajouter une étape
                </button>
              )}
            </div>
            {logisticsSteps.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
                <Icon name="TruckIcon" size={32} />
                <p className="text-sm">Aucune étape logistique pour ce projet.</p>
              </div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                {logisticsSteps.map((step) => (
                  <LogisticsStepCard
                    key={step.id}
                    step={step}
                    canEdit={canEditStep(step)}
                    actorId={actorId}
                    coordinatorOrgId={project.coordinator_org_id}
                    onUpdated={loadData}
                  />
                ))}
              </div>
            )}
          </div>
        )}

        {/* DOCUMENTS */}
        {activeTab === 'documents' && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-foreground">Documents ({documents.length})</h2>
              {isCoordinatorAdmin && (
                <button
                  onClick={() => setShowDocUploader(true)}
                  className="flex items-center gap-1.5 px-3 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
                >
                  <Icon name="ArrowUpTrayIcon" size={14} />
                  Déposer un document
                </button>
              )}
            </div>
            {documents.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
                <Icon name="FolderOpenIcon" size={32} />
                <p className="text-sm">Aucun document pour ce projet.</p>
              </div>
            ) : (
              <div className="grid gap-3 sm:grid-cols-2">
                {documents.map((doc) => {
                  const cfg = DOC_STATUS_CONFIG[doc.status];
                  return (
                    <div key={doc.id} className="bg-card border border-border rounded-xl p-4">
                      <div className="flex items-start justify-between gap-3 mb-2">
                        <p className="text-sm font-semibold text-foreground truncate">{doc.title}</p>
                        <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border flex-shrink-0 ${cfg.cls}`}>
                          {cfg.label}
                        </span>
                      </div>
                      <p className="text-xs text-muted-foreground">
                        {doc.category ?? '—'} · v{doc.version}
                      </p>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* RISKS */}
        {activeTab === 'risks' && (
          <div className="space-y-3">
            <h2 className="text-sm font-semibold text-foreground">Risques détectés ({risks.length})</h2>
            {risks.length === 0 ? (
              <div className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
                <Icon name="ShieldCheckIcon" size={32} />
                <p className="text-sm">Aucun risque détecté.</p>
              </div>
            ) : (
              <div className="space-y-2">
                {risks.map((risk, i) => (
                  <div
                    key={i}
                    className={`flex items-start gap-3 px-4 py-3 rounded-xl border ${
                      risk.severity === 'high'
                        ? 'bg-red-50 border-red-200 text-red-700'
                        : risk.severity === 'medium'
                        ? 'bg-amber-50 border-amber-200 text-amber-700'
                        : 'bg-yellow-50 border-yellow-200 text-yellow-700'
                    }`}
                  >
                    <Icon
                      name={risk.icon as Parameters<typeof Icon>[0]['name']}
                      size={16}
                      className="mt-0.5 flex-shrink-0"
                    />
                    <p className="text-sm">{risk.label}</p>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* VALUE REPORT */}
        {activeTab === 'value_report' && (
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold text-foreground">Rapport de valeur</h2>
              {isCoordinatorAdmin && !showVRForm && (
                <button
                  onClick={() => {
                    const latest = valueReports[0];
                    if (latest) {
                      setEditingVR(latest);
                      setVrForm({
                        volume: latest.volume?.toString() ?? '',
                        coordination_value: latest.coordination_value?.toString() ?? '',
                        notes: latest.notes ?? '',
                        status: latest.status,
                      });
                    } else {
                      setEditingVR(null);
                      setVrForm({ volume: '', coordination_value: '', notes: '', status: 'draft' });
                    }
                    setShowVRForm(true);
                  }}
                  className="flex items-center gap-1.5 px-3 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
                >
                  <Icon name={valueReports.length > 0 ? 'PencilSquareIcon' : 'PlusIcon'} size={14} />
                  {valueReports.length > 0 ? 'Modifier' : 'Créer'}
                </button>
              )}
            </div>

            {showVRForm && isCoordinatorAdmin && (
              <div className="bg-card border border-border rounded-xl p-5 space-y-4">
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <label className="block text-xs font-medium text-foreground mb-1.5">Volume (t)</label>
                    <input
                      type="number"
                      step="0.01"
                      value={vrForm.volume}
                      onChange={(e) => setVrForm((p) => ({ ...p, volume: e.target.value }))}
                      className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                    />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-foreground mb-1.5">Valeur de coordination ($)</label>
                    <input
                      type="number"
                      step="0.01"
                      value={vrForm.coordination_value}
                      onChange={(e) => setVrForm((p) => ({ ...p, coordination_value: e.target.value }))}
                      className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                    />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-foreground mb-1.5">Notes</label>
                  <textarea
                    value={vrForm.notes}
                    onChange={(e) => setVrForm((p) => ({ ...p, notes: e.target.value }))}
                    rows={3}
                    className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  />
                </div>
                <div>
                  <label className="block text-xs font-medium text-foreground mb-1.5">Statut</label>
                  <select
                    value={vrForm.status}
                    onChange={(e) => setVrForm((p) => ({ ...p, status: e.target.value as ValueReportStatus }))}
                    className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                  >
                    {Object.keys(VALUE_REPORT_STATUS_CONFIG).map((s) => (
                      <option key={s} value={s}>{VALUE_REPORT_STATUS_CONFIG[s as ValueReportStatus].label}</option>
                    ))}
                  </select>
                </div>
                {vrError && (
                  <div className="flex items-center gap-2 px-3 py-2 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
                    <Icon name="ExclamationCircleIcon" size={14} />
                    {vrError}
                  </div>
                )}
                <div className="flex gap-3">
                  <button
                    onClick={() => { setShowVRForm(false); setVrError(null); }}
                    className="px-4 py-2 rounded-lg border border-border text-sm font-medium text-foreground hover:bg-muted transition-colors"
                  >
                    Annuler
                  </button>
                  <button
                    onClick={handleVRSave}
                    disabled={vrLoading}
                    className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
                  >
                    {vrLoading ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> : null}
                    Enregistrer
                  </button>
                </div>
              </div>
            )}

            {!showVRForm && valueReports.length === 0 && (
              <div className="flex flex-col items-center gap-2 py-12 text-muted-foreground">
                <Icon name="ChartBarIcon" size={32} />
                <p className="text-sm">Aucun rapport de valeur pour ce projet.</p>
              </div>
            )}

            {!showVRForm && valueReports.map((vr) => (
              <div key={vr.id} className="bg-card border border-border rounded-xl p-5 space-y-3">
                <div className="flex items-center justify-between">
                  <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border ${VALUE_REPORT_STATUS_CONFIG[vr.status].cls}`}>
                    {VALUE_REPORT_STATUS_CONFIG[vr.status].label}
                  </span>
                  <span className="text-xs text-muted-foreground">
                    {new Date(vr.created_at).toLocaleDateString('fr-CA')}
                  </span>
                </div>
                <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-semibold">Volume</p>
                    <p className="text-sm font-semibold text-foreground">{vr.volume != null ? `${vr.volume} t` : '—'}</p>
                  </div>
                  <div>
                    <p className="text-[11px] text-muted-foreground uppercase tracking-wide font-semibold">Valeur de coordination</p>
                    <p className="text-sm font-semibold text-foreground">{vr.coordination_value != null ? `${vr.coordination_value.toLocaleString('fr-CA')} $` : '—'}</p>
                  </div>
                </div>
                {vr.notes && (
                  <p className="text-sm text-muted-foreground whitespace-pre-wrap">{vr.notes}</p>
                )}
              </div>
            ))}
          </div>
        )}

        {/* HISTORY */}
        {activeTab === 'history' && (
          <div className="space-y-3">
            <h2 className="text-sm font-semibold text-foreground">Historique du projet</h2>
            <ObjectTimeline object_type="project" object_id={projectId} />
          </div>
        )}

      </div>

      {/* Document uploader modal */}
      {showDocUploader && (
        <ProjectDocumentUploader
          projectId={projectId}
          myAdminOrgIds={myAdminOrgIds}
          organizations={organizations}
          actorId={actorId}
          onClose={() => setShowDocUploader(false)}
          onUploaded={() => { setShowDocUploader(false); loadData(); }}
        />
      )}

      {/* Invite organization modal (E08-T02) */}
      {showInviteModal && project && (
        <InviteOrganizationModal
          project={project}
          actorId={actorId}
          allOrganizations={organizations}
          existingParticipantOrgIds={participants.map((p) => p.organization_id)}
          onClose={() => setShowInviteModal(false)}
          onInvited={() => { setShowInviteModal(false); loadData(); }}
        />
      )}

      {/* Add logistics step modal (E08bis) */}
      {showAddStepModal && project && (
        <AddLogisticsStepModal
          project={project}
          participants={participants}
          onClose={() => setShowAddStepModal(false)}
          onCreated={() => { setShowAddStepModal(false); loadData(); }}
        />
      )}
    </AppLayout>
  );
}
