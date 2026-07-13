'use client';
import React, { useEffect, useState, useCallback, useRef } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

type DocVisibility = 'organization_private' | 'project' | 'confidential';
type DocStatus = 'draft' | 'submitted' | 'approved' | 'rejected' | 'archived';
type ObjectType = 'organization' | 'capability' | 'opportunity' | 'project' | 'mandate' | 'value_report';

interface Document {
  id: string;
  owner_org_id: string;
  object_type: ObjectType;
  object_id: string;
  title: string;
  category: string | null;
  version: string;
  visibility: DocVisibility;
  storage_path: string | null;
  status: DocStatus;
  created_at: string;
  updated_at: string;
}

interface OrgMembership {
  organization_id: string;
  org_role: string;
  status: string;
}

interface Organization {
  id: string;
  name: string;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Bug mineur relevé au test live du 12 juillet (ADR-MVP.md §9octies) : `e instanceof Error`
// est faux pour une PostgrestError (objet simple avec .message/.code/.details, pas une
// instance d'Error) — le message réel de Postgres/PostgREST était donc toujours masqué
// par un texte générique. Cette fonction couvre les deux formes d'erreur rencontrées ici.
function getErrorMessage(e: unknown, fallback: string): string {
  if (e instanceof Error) return e.message;
  if (e && typeof e === 'object' && 'message' in e && typeof (e as { message: unknown }).message === 'string') {
    return (e as { message: string }).message;
  }
  return fallback;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const STATUS_CONFIG: Record<DocStatus, { label: string; cls: string; icon: string }> = {
  draft:     { label: 'Brouillon',  cls: 'text-gray-600 bg-gray-100 border-gray-200',    icon: 'DocumentIcon' },
  submitted: { label: 'Soumis',     cls: 'text-amber-700 bg-amber-50 border-amber-200',  icon: 'ClockIcon' },
  approved:  { label: 'Approuvé',   cls: 'text-green-700 bg-green-50 border-green-200',  icon: 'CheckCircleIcon' },
  rejected:  { label: 'Refusé',     cls: 'text-red-600 bg-red-50 border-red-200',        icon: 'XCircleIcon' },
  archived:  { label: 'Archivé',    cls: 'text-slate-400 bg-slate-50 border-slate-100',  icon: 'ArchiveBoxIcon' },
};

const VISIBILITY_CONFIG: Record<DocVisibility, { label: string; cls: string; description: string }> = {
  organization_private: { label: 'Privé (org)',  cls: 'text-slate-600 bg-slate-100 border-slate-200', description: 'Membres de l\'organisation propriétaire uniquement' },
  project:              { label: 'Projet',       cls: 'text-blue-700 bg-blue-50 border-blue-200',     description: 'Membres de l\'org + participants actifs du projet' },
  confidential:         { label: 'Confidentiel', cls: 'text-purple-700 bg-purple-50 border-purple-200', description: 'Déposant + parties autorisées selon le type d\'objet' },
};

const OBJECT_TYPE_LABELS: Record<ObjectType, string> = {
  organization: 'Organisation',
  capability:   'Capacité',
  opportunity:  'Opportunité',
  project:      'Projet',
  mandate:      'Mandat',
  value_report: 'Rapport de valeur',
};

const OBJECT_TYPES: ObjectType[] = ['organization', 'capability', 'opportunity', 'project', 'mandate', 'value_report'];

// ─── Sub-components ───────────────────────────────────────────────────────────

function DocStatusBadge({ status }: { status: DocStatus }) {
  const cfg = STATUS_CONFIG[status] ?? STATUS_CONFIG.draft;
  return (
    <span className={`inline-flex items-center gap-1 rounded-full text-xs font-semibold px-2.5 py-1 border ${cfg.cls}`}>
      <Icon name={cfg.icon as Parameters<typeof Icon>[0]['name']} size={12} />
      {cfg.label}
    </span>
  );
}

function VisibilityBadge({ visibility }: { visibility: DocVisibility }) {
  const cfg = VISIBILITY_CONFIG[visibility] ?? VISIBILITY_CONFIG.organization_private;
  return (
    <span className={`inline-flex items-center rounded-full text-xs font-semibold px-2 py-0.5 border ${cfg.cls}`}>
      {cfg.label}
    </span>
  );
}

// ─── Upload Form Modal ────────────────────────────────────────────────────────

interface UploadFormProps {
  myAdminOrgIds: string[];
  organizations: Organization[];
  actorId: string;
  onClose: () => void;
  onUploaded: () => void;
}

function DocumentUploader({ myAdminOrgIds, organizations, actorId, onClose, onUploaded }: UploadFormProps) {
  const supabase = createClient();
  const fileInputRef = useRef<HTMLInputElement>(null);

  const [form, setForm] = useState({
    owner_org_id: myAdminOrgIds[0] ?? '',
    object_type: 'organization' as ObjectType,
    object_id: '',
    title: '',
    category: '',
    version: '1.0',
    visibility: 'organization_private' as DocVisibility,
  });
  const [file, setFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // MVP-RA-026: visibility 'project' only allowed when object_type = 'project'
  const visibilityOptions: DocVisibility[] = form.object_type === 'project'
    ? ['organization_private', 'project', 'confidential']
    : ['organization_private', 'confidential'];

  // If current visibility is 'project' but object_type changed away from 'project', reset
  const handleObjectTypeChange = (ot: ObjectType) => {
    setForm((prev) => ({
      ...prev,
      object_type: ot,
      visibility: ot !== 'project' && prev.visibility === 'project' ? 'organization_private' : prev.visibility,
    }));
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    if (!form.owner_org_id) { setError('Sélectionnez l\'organisation propriétaire'); return; }
    if (!form.object_id.trim()) { setError('L\'identifiant de l\'objet rattaché est obligatoire'); return; }
    if (!UUID_RE.test(form.object_id.trim())) { setError('L\'identifiant de l\'objet doit être un UUID valide (ex. 3fa85f64-5717-4562-b3fc-2c963f66afa6)'); return; }
    if (!form.title.trim()) { setError('Le titre est obligatoire'); return; }
    if (!file) { setError('Sélectionnez un fichier à déposer'); return; }

    // MVP-RA-026 guard
    if (form.visibility === 'project' && form.object_type !== 'project') {
      setError('La visibilité "Projet" n\'est autorisée que si l\'objet rattaché est de type "Projet"');
      return;
    }

    setUploading(true);
    try {
      // 1. Upload file to Supabase Storage
      const ext = file.name.split('.').pop() ?? 'bin';
      const storagePath = `documents/${form.owner_org_id}/${Date.now()}_${file.name.replace(/[^a-zA-Z0-9._-]/g, '_')}`;

      const { error: storageErr } = await supabase.storage
        .from('documents')
        .upload(storagePath, file, { upsert: false });

      if (storageErr) throw new Error(`Erreur de stockage : ${storageErr.message}`);

      // 2. Insert document record
      const { error: insertErr } = await supabase.from('documents').insert({
        owner_org_id: form.owner_org_id,
        object_type: form.object_type,
        object_id: form.object_id.trim(),
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
      <div className="bg-card rounded-xl shadow-xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between px-6 py-4 border-b border-border">
          <div>
            <h2 className="text-base font-bold text-foreground">Déposer un document</h2>
            <p className="text-xs text-muted-foreground mt-0.5">Statut initial : Brouillon</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-muted transition-colors">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="px-6 py-5 space-y-4">
          {/* Organisation propriétaire */}
          <div>
            <label className="block text-xs font-medium text-foreground mb-1.5">Organisation propriétaire *</label>
            <select
              value={form.owner_org_id}
              onChange={(e) => setForm((p) => ({ ...p, owner_org_id: e.target.value }))}
              className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              required
            >
              <option value="">Sélectionner…</option>
              {organizations
                .filter((o) => myAdminOrgIds.includes(o.id))
                .map((o) => (
                  <option key={o.id} value={o.id}>{o.name}</option>
                ))}
            </select>
          </div>

          {/* Type d'objet + ID */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-foreground mb-1.5">Type d'objet *</label>
              <select
                value={form.object_type}
                onChange={(e) => handleObjectTypeChange(e.target.value as ObjectType)}
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
              >
                {OBJECT_TYPES.map((t) => (
                  <option key={t} value={t}>{OBJECT_TYPE_LABELS[t]}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-foreground mb-1.5">ID de l'objet *</label>
              <input
                type="text"
                value={form.object_id}
                onChange={(e) => setForm((p) => ({ ...p, object_id: e.target.value }))}
                placeholder="UUID de l'objet (ex. 3fa85f64-5717-4562-b3fc-2c963f66afa6)"
                pattern="[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
                title="Doit être un UUID valide"
                className="w-full px-3 py-2 rounded-lg border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary/30"
                required
              />
            </div>
          </div>

          {/* Titre */}
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

          {/* Catégorie + Version */}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-medium text-foreground mb-1.5">Catégorie</label>
              <input
                type="text"
                value={form.category}
                onChange={(e) => setForm((p) => ({ ...p, category: e.target.value }))}
                placeholder="ex. Contrat, Rapport…"
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

          {/* Visibilité — MVP-RA-026 */}
          <div>
            <label className="block text-xs font-medium text-foreground mb-1.5">Visibilité *</label>
            <div className="space-y-2">
              {visibilityOptions.map((v) => (
                <label
                  key={v}
                  className={`flex items-start gap-3 px-3 py-2.5 rounded-lg border cursor-pointer transition-colors ${
                    form.visibility === v
                      ? 'border-primary bg-primary/5' :'border-border bg-card hover:bg-muted'
                  }`}
                >
                  <input
                    type="radio"
                    name="visibility"
                    value={v}
                    checked={form.visibility === v}
                    onChange={() => setForm((p) => ({ ...p, visibility: v }))}
                    className="mt-0.5 accent-primary"
                  />
                  <div>
                    <p className="text-sm font-medium text-foreground">{VISIBILITY_CONFIG[v].label}</p>
                    <p className="text-xs text-muted-foreground">{VISIBILITY_CONFIG[v].description}</p>
                  </div>
                </label>
              ))}
            </div>
            {form.object_type !== 'project' && (
              <p className="mt-1.5 text-xs text-amber-600 flex items-center gap-1">
                <Icon name="InformationCircleIcon" size={12} />
                La visibilité "Projet" est disponible uniquement si l'objet rattaché est de type "Projet" (MVP-RA-026)
              </p>
            )}
          </div>

          {/* Fichier */}
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
                <div className="text-center">
                  <p className="text-sm text-muted-foreground">Cliquez pour sélectionner un fichier</p>
                  <p className="text-xs text-muted-foreground mt-0.5">Tous formats acceptés</p>
                </div>
              )}
            </div>
            <input
              ref={fileInputRef}
              type="file"
              className="hidden"
              onChange={(e) => setFile(e.target.files?.[0] ?? null)}
            />
          </div>

          {/* Error */}
          {error && (
            <div className="flex items-start gap-2 px-3 py-2.5 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm">
              <Icon name="ExclamationCircleIcon" size={16} className="flex-shrink-0 mt-0.5" />
              <span>{error}</span>
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 px-4 py-2.5 rounded-lg border border-border text-sm font-medium text-foreground hover:bg-muted transition-colors"
            >
              Annuler
            </button>
            <button
              type="submit"
              disabled={uploading}
              className="flex-1 flex items-center justify-center gap-2 px-4 py-2.5 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 disabled:opacity-50 transition-colors"
            >
              {uploading ? (
                <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                <Icon name="ArrowUpTrayIcon" size={16} />
              )}
              {uploading ? 'Dépôt en cours…' : 'Déposer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function DocumentsPage() {
  const supabase = createClient();

  // State
  const [documents, setDocuments] = useState<Document[]>([]);
  const [organizations, setOrganizations] = useState<Organization[]>([]);
  const [myOrgIds, setMyOrgIds] = useState<string[]>([]);
  const [myAdminOrgIds, setMyAdminOrgIds] = useState<string[]>([]);
  const [actorId, setActorId] = useState<string>('');

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  // Filters
  const [filterStatus, setFilterStatus] = useState<DocStatus | 'all'>('all');
  const [filterObjectType, setFilterObjectType] = useState<ObjectType | 'all'>('all');

  // UI state
  const [selectedDoc, setSelectedDoc] = useState<Document | null>(null);
  const [showUploader, setShowUploader] = useState(false);

  // ─── Data loading ──────────────────────────────────────────────────────────

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setError('Non authentifié'); setLoading(false); return; }
      setActorId(user.id);

      // Load memberships
      const { data: memberships } = await supabase
        .from('organization_members')
        .select('organization_id, org_role, status')
        .eq('user_id', user.id)
        .eq('status', 'active');

      const mems: OrgMembership[] = memberships ?? [];
      const orgIds = mems.map((m) => m.organization_id);
      const adminIds = mems
        .filter((m) => m.org_role === 'admin' || m.org_role === 'owner')
        .map((m) => m.organization_id);
      setMyOrgIds(orgIds);
      setMyAdminOrgIds(adminIds);

      // Load documents — RLS already filters visibility, no client-side filter needed
      const { data: docsData, error: docsErr } = await supabase
        .from('documents')
        .select('*')
        .order('created_at', { ascending: false });

      if (docsErr) throw docsErr;
      setDocuments((docsData ?? []) as Document[]);

      // Load organizations for uploader
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
  }, [supabase]);

  useEffect(() => { loadData(); }, [loadData]);

  // ─── Helpers ───────────────────────────────────────────────────────────────

  const isOwnerAdmin = (doc: Document) => myAdminOrgIds.includes(doc.owner_org_id);

  // ─── State machine actions ─────────────────────────────────────────────────

  /**
   * draft → submitted
   * Mechanism: direct UPDATE + manual business_events insert (no RPC)
   */
  const handleSubmit = async (doc: Document) => {
    setActionLoading(doc.id);
    try {
      const { error: err } = await supabase
        .from('documents')
        .update({ status: 'submitted', updated_at: new Date().toISOString() })
        .eq('id', doc.id);
      if (err) throw err;

      // Manual business_events insert required (no RPC handles this)
      await supabase.from('business_events').insert({
        event_type: 'document_submitted',
        object_type: 'document',
        object_id: doc.id,
        actor_id: actorId,
        organization_id: doc.owner_org_id,
        payload: { document_id: doc.id, title: doc.title },
      });

      await loadData();
      setSelectedDoc(null);
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors de la soumission'));
    } finally {
      setActionLoading(null);
    }
  };

  /**
   * submitted → approved | rejected
   * Mechanism: approve_document() RPC ONLY — never manual UPDATE or business_events insert
   * The RPC handles both the status update AND the business_events insert server-side.
   */
  const handleApproveOrReject = async (doc: Document, decision: 'approved' | 'rejected') => {
    setActionLoading(doc.id);
    try {
      const { error: err } = await supabase.rpc('approve_document', {
        p_document_id: doc.id,
        p_decision: decision,
      });
      if (err) throw err;
      // DO NOT insert business_events manually — the RPC already does it (INC-S06-06 / ADR-MVP.md §9quinquies)

      await loadData();
      setSelectedDoc(null);
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors de la décision'));
    } finally {
      setActionLoading(null);
    }
  };

  /**
   * approved | rejected → archived
   * Mechanism: direct UPDATE + manual business_events insert (no RPC)
   */
  const handleArchive = async (doc: Document) => {
    if (!confirm('Archiver ce document ? Cette action est irréversible.')) return;
    setActionLoading(doc.id);
    try {
      const { error: err } = await supabase
        .from('documents')
        .update({ status: 'archived', updated_at: new Date().toISOString() })
        .eq('id', doc.id);
      if (err) throw err;

      // Manual business_events insert required (no RPC handles this)
      await supabase.from('business_events').insert({
        event_type: 'document_archived',
        object_type: 'document',
        object_id: doc.id,
        actor_id: actorId,
        organization_id: doc.owner_org_id,
        payload: { document_id: doc.id, title: doc.title },
      });

      await loadData();
      setSelectedDoc(null);
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Erreur lors de l\'archivage'));
    } finally {
      setActionLoading(null);
    }
  };

  // ─── Filtered documents ────────────────────────────────────────────────────

  const filtered = documents.filter((d) => {
    if (filterStatus !== 'all' && d.status !== filterStatus) return false;
    if (filterObjectType !== 'all' && d.object_type !== filterObjectType) return false;
    return true;
  });

  // ─── Detail panel actions ──────────────────────────────────────────────────

  function DetailActions({ doc }: { doc: Document }) {
    const isLoading = actionLoading === doc.id;
    const isAdmin = isOwnerAdmin(doc);

    return (
      <div className="space-y-2">
        {/* draft → submitted (owner admin only) */}
        {doc.status === 'draft' && isAdmin && (
          <button
            onClick={() => handleSubmit(doc)}
            disabled={isLoading}
            className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-amber-600 text-white rounded-lg text-sm font-medium hover:bg-amber-700 disabled:opacity-50 transition-colors"
          >
            {isLoading ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> : <Icon name="PaperAirplaneIcon" size={16} />}
            Soumettre
          </button>
        )}

        {/* submitted → approved (via RPC) */}
        {doc.status === 'submitted' && (
          <button
            onClick={() => handleApproveOrReject(doc, 'approved')}
            disabled={isLoading}
            className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 disabled:opacity-50 transition-colors"
          >
            {isLoading ? <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin" /> : <Icon name="CheckCircleIcon" size={16} />}
            Approuver
          </button>
        )}

        {/* submitted → rejected (via RPC) */}
        {doc.status === 'submitted' && (
          <button
            onClick={() => handleApproveOrReject(doc, 'rejected')}
            disabled={isLoading}
            className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-red-100 text-red-700 rounded-lg text-sm font-medium hover:bg-red-200 disabled:opacity-50 transition-colors"
          >
            {isLoading ? <div className="w-4 h-4 border-2 border-red-700 border-t-transparent rounded-full animate-spin" /> : <Icon name="XCircleIcon" size={16} />}
            Refuser
          </button>
        )}

        {/* approved | rejected → archived (owner admin only) */}
        {(doc.status === 'approved' || doc.status === 'rejected') && isAdmin && (
          <button
            onClick={() => handleArchive(doc)}
            disabled={isLoading}
            className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-slate-100 text-slate-700 rounded-lg text-sm font-medium hover:bg-slate-200 disabled:opacity-50 transition-colors"
          >
            {isLoading ? <div className="w-4 h-4 border-2 border-slate-700 border-t-transparent rounded-full animate-spin" /> : <Icon name="ArchiveBoxIcon" size={16} />}
            Archiver
          </button>
        )}

        {/* No actions available */}
        {doc.status === 'archived' && (
          <p className="text-xs text-muted-foreground text-center py-2">Document archivé — aucune action disponible</p>
        )}
        {doc.status === 'draft' && !isAdmin && (
          <p className="text-xs text-muted-foreground text-center py-2">Seul l'administrateur de l'organisation propriétaire peut soumettre ce document</p>
        )}
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
            <h1 className="text-xl font-bold text-foreground">Documents</h1>
            <p className="text-sm text-muted-foreground mt-0.5">
              Dépôt documentaire gouverné — E09
            </p>
          </div>
          {myAdminOrgIds.length > 0 && (
            <button
              onClick={() => setShowUploader(true)}
              className="flex items-center gap-2 px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
            >
              <Icon name="ArrowUpTrayIcon" size={16} />
              Déposer un document
            </button>
          )}
        </div>

        {/* Error banner */}
        {error && (
          <div className="mx-6 mt-4 flex items-center gap-2 px-4 py-3 bg-red-50 border border-red-200 rounded-lg text-red-700 text-sm flex-shrink-0">
            <Icon name="ExclamationCircleIcon" size={16} />
            <span className="flex-1">{error}</span>
            <button onClick={() => setError(null)}>
              <Icon name="XMarkIcon" size={14} />
            </button>
          </div>
        )}

        {/* Filters */}
        <div className="flex items-center gap-3 px-6 py-3 border-b border-border bg-muted/30 flex-shrink-0 flex-wrap">
          <div className="flex items-center gap-1.5">
            <span className="text-xs text-muted-foreground font-medium">Statut :</span>
            {(['all', 'draft', 'submitted', 'approved', 'rejected', 'archived'] as const).map((s) => (
              <button
                key={s}
                onClick={() => setFilterStatus(s)}
                className={`px-2.5 py-1 rounded-full text-xs font-medium transition-colors ${
                  filterStatus === s
                    ? 'bg-primary text-primary-foreground'
                    : 'bg-card border border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                {s === 'all' ? 'Tous' : STATUS_CONFIG[s as DocStatus]?.label ?? s}
              </button>
            ))}
          </div>
          <div className="flex items-center gap-1.5 ml-auto">
            <span className="text-xs text-muted-foreground font-medium">Objet :</span>
            <select
              value={filterObjectType}
              onChange={(e) => setFilterObjectType(e.target.value as ObjectType | 'all')}
              className="px-2.5 py-1 rounded-lg border border-border bg-card text-xs text-foreground focus:outline-none focus:ring-2 focus:ring-primary/30"
            >
              <option value="all">Tous types</option>
              {OBJECT_TYPES.map((t) => (
                <option key={t} value={t}>{OBJECT_TYPE_LABELS[t]}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Content: list + detail panel */}
        <div className="flex flex-1 min-h-0 overflow-hidden">

          {/* Document list */}
          <div className={`flex flex-col overflow-y-auto ${selectedDoc ? 'w-1/2 border-r border-border' : 'w-full'}`}>
            {loading ? (
              <div className="flex items-center justify-center py-16">
                <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
              </div>
            ) : filtered.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-16 text-center px-6">
                <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mb-3">
                  <Icon name="DocumentTextIcon" size={24} className="text-muted-foreground" />
                </div>
                <p className="text-sm font-medium text-foreground">Aucun document</p>
                <p className="text-xs text-muted-foreground mt-1">
                  {filterStatus !== 'all' || filterObjectType !== 'all' ?'Aucun document ne correspond aux filtres sélectionnés.' :'Déposez votre premier document pour commencer.'}
                </p>
              </div>
            ) : (
              <div className="divide-y divide-border">
                {filtered.map((doc) => {
                  const isSelected = selectedDoc?.id === doc.id;
                  return (
                    <button
                      key={doc.id}
                      onClick={() => setSelectedDoc(isSelected ? null : doc)}
                      className={`w-full text-left px-6 py-4 transition-colors hover:bg-muted/50 ${isSelected ? 'bg-primary/5 border-l-2 border-primary' : ''}`}
                    >
                      <div className="flex items-start justify-between gap-3">
                        <div className="flex items-start gap-3 min-w-0">
                          <div className="w-9 h-9 rounded-lg bg-muted flex items-center justify-center flex-shrink-0 mt-0.5">
                            <Icon name="DocumentTextIcon" size={18} className="text-muted-foreground" />
                          </div>
                          <div className="min-w-0">
                            <p className="text-sm font-semibold text-foreground truncate">{doc.title}</p>
                            <div className="flex items-center gap-2 mt-1 flex-wrap">
                              <span className="text-xs text-muted-foreground">
                                {OBJECT_TYPE_LABELS[doc.object_type]}
                              </span>
                              {doc.category && (
                                <>
                                  <span className="text-muted-foreground/40">·</span>
                                  <span className="text-xs text-muted-foreground">{doc.category}</span>
                                </>
                              )}
                              <span className="text-muted-foreground/40">·</span>
                              <span className="text-xs text-muted-foreground">v{doc.version}</span>
                            </div>
                          </div>
                        </div>
                        <div className="flex flex-col items-end gap-1.5 flex-shrink-0">
                          <DocStatusBadge status={doc.status} />
                          <VisibilityBadge visibility={doc.visibility} />
                        </div>
                      </div>
                    </button>
                  );
                })}
              </div>
            )}
          </div>

          {/* Detail panel */}
          {selectedDoc && (
            <div className="w-1/2 flex flex-col overflow-y-auto bg-card">
              {/* Panel header */}
              <div className="flex items-center justify-between px-5 py-4 border-b border-border flex-shrink-0">
                <h2 className="text-sm font-bold text-foreground truncate pr-4">{selectedDoc.title}</h2>
                <button
                  onClick={() => setSelectedDoc(null)}
                  className="p-1.5 rounded-lg hover:bg-muted transition-colors flex-shrink-0"
                >
                  <Icon name="XMarkIcon" size={16} />
                </button>
              </div>

              <div className="flex-1 overflow-y-auto px-5 py-4 space-y-5">
                {/* Status + visibility */}
                <div className="flex items-center gap-2 flex-wrap">
                  <DocStatusBadge status={selectedDoc.status} />
                  <VisibilityBadge visibility={selectedDoc.visibility} />
                </div>

                {/* State machine diagram */}
                <div className="bg-muted/50 rounded-lg px-4 py-3">
                  <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Cycle de vie</p>
                  <div className="flex items-center gap-1 flex-wrap text-xs">
                    {(['draft', 'submitted', 'approved', 'rejected', 'archived'] as DocStatus[]).map((s, i) => {
                      const isCurrent = selectedDoc.status === s;
                      const cfg = STATUS_CONFIG[s];
                      return (
                        <React.Fragment key={s}>
                          {i > 0 && <Icon name="ChevronRightIcon" size={10} className="text-muted-foreground/50" />}
                          <span className={`px-2 py-0.5 rounded-full font-medium ${isCurrent ? cfg.cls + ' border' : 'text-muted-foreground/60'}`}>
                            {cfg.label}
                          </span>
                        </React.Fragment>
                      );
                    })}
                  </div>
                </div>

                {/* Metadata */}
                <div className="space-y-2.5">
                  <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Détails</p>
                  <dl className="space-y-2">
                    {[
                      { label: 'Type d\'objet', value: OBJECT_TYPE_LABELS[selectedDoc.object_type] },
                      { label: 'ID objet', value: selectedDoc.object_id },
                      { label: 'Catégorie', value: selectedDoc.category ?? '—' },
                      { label: 'Version', value: `v${selectedDoc.version}` },
                      { label: 'Chemin stockage', value: selectedDoc.storage_path ?? '—' },
                      { label: 'Créé le', value: new Date(selectedDoc.created_at).toLocaleDateString('fr-CA') },
                      { label: 'Mis à jour', value: new Date(selectedDoc.updated_at).toLocaleDateString('fr-CA') },
                    ].map(({ label, value }) => (
                      <div key={label} className="flex items-start justify-between gap-3">
                        <dt className="text-xs text-muted-foreground flex-shrink-0">{label}</dt>
                        <dd className="text-xs text-foreground font-medium text-right break-all">{value}</dd>
                      </div>
                    ))}
                  </dl>
                </div>

                {/* Download link */}
                {selectedDoc.storage_path && (
                  <div>
                    <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Fichier</p>
                    <DownloadButton doc={selectedDoc} />
                  </div>
                )}

                {/* Actions */}
                <div>
                  <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Actions</p>
                  <DetailActions doc={selectedDoc} />
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* Upload modal */}
      {showUploader && (
        <DocumentUploader
          myAdminOrgIds={myAdminOrgIds}
          organizations={organizations}
          actorId={actorId}
          onClose={() => setShowUploader(false)}
          onUploaded={() => {
            setShowUploader(false);
            loadData();
          }}
        />
      )}
    </AppLayout>
  );
}

// ─── Download button (signed URL) ─────────────────────────────────────────────

function DownloadButton({ doc }: { doc: Document }) {
  const supabase = createClient();
  const [loading, setLoading] = useState(false);

  const handleDownload = async () => {
    if (!doc.storage_path) return;
    setLoading(true);
    try {
      const { data, error } = await supabase.storage
        .from('documents')
        .createSignedUrl(doc.storage_path, 60);
      if (error) throw error;
      window.open(data.signedUrl, '_blank');
    } catch (e: unknown) {
      alert(getErrorMessage(e, 'Erreur lors du téléchargement'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <button
      onClick={handleDownload}
      disabled={loading}
      className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-muted border border-border text-foreground rounded-lg text-sm font-medium hover:bg-muted/80 disabled:opacity-50 transition-colors"
    >
      {loading ? (
        <div className="w-4 h-4 border-2 border-foreground border-t-transparent rounded-full animate-spin" />
      ) : (
        <Icon name="ArrowDownTrayIcon" size={16} />
      )}
      Télécharger
    </button>
  );
}
