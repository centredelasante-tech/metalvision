'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

// ============================================================================
// /admin-verification-sessions
// ----------------------------------------------------------------------------
// AUDIT (juillet 2026) : la version précédente de cette page écrivait
// directement dans verification_sessions via .insert()/.update() — y compris
// un sélecteur de statut libre incluant 'completed'. Cette page est
// antérieure aux garde-fous de la migration 05 (carbon_guard_verification_
// session_update, carbon_check_verification_session_outcome_invariant,
// plan_verification_session(), complete_verification_session()). Une
// tentative d'écrire directement status='completed' est bloquée
// structurellement par le trigger (aucun verification_outcome n'existe
// encore) — donc sans risque de corruption — mais l'interface proposait une
// action qui ne pouvait jamais aboutir, et ne permettait jamais d'assigner un
// vérificateur accrédité ni une période de reporting, seuls chemins réels
// vers un résultat de vérification exploitable.
//
// Correctifs appliqués (aucune migration modifiée, aucun calcul métier
// déplacé côté client — cette page ne fait qu'appeler les RPC existantes) :
//   - création : INSERT direct limité à project_id/verifier_org/
//     verifier_contact/comments/report_url — status n'est jamais fourni
//     (défaut serveur 'planned').
//   - édition : verifier_org/verifier_contact/report_url ne sont proposés en
//     édition directe que tant qu'aucun verification_outcome n'existe pour
//     la session et que son statut n'est pas completed (gel structurel
//     identique côté serveur) ; comments reste toujours éditable (jamais
//     gelé côté serveur).
//   - « Planifier » appelle plan_verification_session() (reporting_period_*
//     + verifier_user_id, restreint aux identités accréditées actives).
//   - « Marquer en cours » reste un UPDATE direct de status uniquement
//     (transition planned -> in_progress, explicitement autorisée par le
//     trigger de garde), proposé seulement une fois la session planifiée.
//   - « Compléter » appelle complete_verification_session() ; n'est proposé
//     qu'à l'utilisateur connecté correspondant à verifier_user_id (seul
//     appelant autorisé côté serveur — auth.uid() = verifier_user_id).
//   - le statut n'est plus jamais réglable librement.
// ============================================================================

interface VerificationSession {
  id: string;
  project_id: string;
  verifier_org: string | null;
  verifier_contact: string | null;
  scope: Record<string, unknown> | null;
  status: 'planned' | 'in_progress' | 'completed';
  report_url: string | null;
  comments: string | null;
  reporting_period_start: string | null;
  reporting_period_end: string | null;
  verifier_user_id: string | null;
  created_at: string;
  projects?: { name: string } | null;
}

interface AccreditedVerifierOption {
  user_id: string;
  label: string;
}

interface EvidenceFileOption {
  id: string;
  file_url: string | null;
  timestamp: string | null;
}

const STATUS_CONFIG: Record<string, { label: string; color: string }> = {
  planned:     { label: 'Planifié',  color: 'text-amber-700 bg-amber-50 border-amber-200' },
  in_progress: { label: 'En cours', color: 'text-blue-700 bg-blue-50 border-blue-200' },
  completed:   { label: 'Complété', color: 'text-green-700 bg-green-50 border-green-200' },
};

function ErrorBanner({ message }: { message: string | null }) {
  if (!message) return null;
  return <div className="bg-red-50 border border-red-200 rounded-lg p-3 text-sm text-red-700 mb-4">{message}</div>;
}

function getErrorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err) return String((err as { message: unknown }).message);
  return 'Erreur inconnue.';
}

function fmtDate(s: string | null | undefined): string {
  if (!s) return '—';
  return new Date(s).toLocaleDateString('fr-CA');
}

// ----------------------------------------------------------------------------
// Modale : créer / modifier les champs libres d'une session
// ----------------------------------------------------------------------------

function SessionModal({
  session,
  projects,
  frozen,
  onClose,
  onSaved,
}: {
  session?: VerificationSession | null;
  projects: { id: string; name: string }[];
  frozen: boolean; // un résultat existe déjà ou statut completed : verifier_org/contact/report_url gelés
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    project_id: session?.project_id ?? (projects[0]?.id ?? ''),
    verifier_org: session?.verifier_org ?? '',
    verifier_contact: session?.verifier_contact ?? '',
    report_url: session?.report_url ?? '',
    comments: session?.comments ?? '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!session && !form.project_id) { setError('Projet requis'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    if (session) {
      const payload: Record<string, unknown> = { comments: form.comments || null };
      if (!frozen) {
        payload.verifier_org = form.verifier_org || null;
        payload.verifier_contact = form.verifier_contact || null;
        payload.report_url = form.report_url || null;
      }
      const { error: err } = await supabase.from('verification_sessions').update(payload).eq('id', session.id);
      setSaving(false);
      if (err) { setError(getErrorMessage(err)); return; }
    } else {
      // Création : status n'est jamais fourni (défaut serveur 'planned').
      const { error: err } = await supabase.from('verification_sessions').insert({
        project_id: form.project_id,
        verifier_org: form.verifier_org || null,
        verifier_contact: form.verifier_contact || null,
        report_url: form.report_url || null,
        comments: form.comments || null,
      });
      setSaving(false);
      if (err) { setError(getErrorMessage(err)); return; }
    }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">{session ? 'Modifier' : 'Nouvelle'} session de vérification</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {!session && (
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Projet *</label>
              <select className="input w-full" value={form.project_id} onChange={(e) => setForm((f) => ({ ...f, project_id: e.target.value }))}>
                {projects.map((p) => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>
          )}
          {session && frozen && (
            <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-2">
              Un résultat de vérification existe déjà pour cette session (ou son statut est complété) : organisme vérificateur, contact et URL du rapport sont gelés côté serveur et ne sont plus modifiables ici.
            </p>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Organisme vérificateur</label>
              <input disabled={frozen} className="input w-full disabled:opacity-50" value={form.verifier_org} onChange={(e) => setForm((f) => ({ ...f, verifier_org: e.target.value }))} placeholder="Bureau Veritas..." />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Contact</label>
              <input disabled={frozen} className="input w-full disabled:opacity-50" value={form.verifier_contact} onChange={(e) => setForm((f) => ({ ...f, verifier_contact: e.target.value }))} placeholder="email@veritas.ca" />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">URL rapport</label>
            <input disabled={frozen} className="input w-full disabled:opacity-50" value={form.report_url} onChange={(e) => setForm((f) => ({ ...f, report_url: e.target.value }))} placeholder="https://..." />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Commentaires</label>
            <textarea className="input w-full h-20 resize-none" value={form.comments} onChange={(e) => setForm((f) => ({ ...f, comments: e.target.value }))} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="submit" disabled={saving} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Sauvegarde...' : 'Sauvegarder'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale : planifier (plan_verification_session)
// ----------------------------------------------------------------------------

function PlanModal({ session, onClose, onSaved }: { session: VerificationSession; onClose: () => void; onSaved: () => void }) {
  const [verifiers, setVerifiers] = useState<AccreditedVerifierOption[]>([]);
  const [loadingVerifiers, setLoadingVerifiers] = useState(true);
  const [verifiersError, setVerifiersError] = useState('');
  const [start, setStart] = useState(session.reporting_period_start ?? '');
  const [end, setEnd] = useState(session.reporting_period_end ?? '');
  const [verifierUserId, setVerifierUserId] = useState(session.verifier_user_id ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      setLoadingVerifiers(true);
      setVerifiersError('');
      const supabase = createClient();
      const { data, error: err } = await supabase
        .from('accredited_verifiers')
        .select('user_id, profiles!accredited_verifiers_user_id_fkey(full_name, email)')
        .eq('active', true);
      if (err) { setVerifiersError(getErrorMessage(err)); setLoadingVerifiers(false); return; }
      const opts: AccreditedVerifierOption[] = (data ?? []).map((v: any) => ({
        user_id: v.user_id,
        label: v.profiles?.full_name ?? v.profiles?.email ?? v.user_id,
      }));
      setVerifiers(opts);
      setLoadingVerifiers(false);
    })();
  }, []);

  const handleSubmit = async () => {
    setError('');
    // plan_verification_session() accepte techniquement des paramètres NULL,
    // mais une session ne peut ensuite jamais progresser utilement (marquer
    // en cours / compléter) sans période complète et vérificateur assigné —
    // les trois sont donc exigés ici pour éviter une confirmation trompeuse.
    if (!start || !end || !verifierUserId) { setError('La période complète (début et fin) et le vérificateur sont requis.'); return; }
    if (end < start) { setError('La date de fin ne peut pas précéder la date de début.'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('plan_verification_session', {
      p_verification_session_id: session.id,
      p_reporting_period_start: start || null,
      p_reporting_period_end: end || null,
      p_verifier_user_id: verifierUserId || null,
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">Planifier la session</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Début période</label>
              <input type="date" className="input w-full" value={start} onChange={(e) => setStart(e.target.value)} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Fin période</label>
              <input type="date" className="input w-full" value={end} onChange={(e) => setEnd(e.target.value)} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Vérificateur accrédité</label>
            {loadingVerifiers ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : verifiersError ? (
              <ErrorBanner message={verifiersError} />
            ) : verifiers.length === 0 ? (
              <p className="text-sm text-red-600">Aucune identité de vérificateur accréditée active (table accredited_verifiers).</p>
            ) : (
              <select className="input w-full" value={verifierUserId} onChange={(e) => setVerifierUserId(e.target.value)}>
                <option value="">— Choisir —</option>
                {verifiers.map((v) => <option key={v.user_id} value={v.user_id}>{v.label}</option>)}
              </select>
            )}
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Enregistrement…' : 'Planifier'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Modale : compléter (complete_verification_session)
// ----------------------------------------------------------------------------

function CompleteModal({
  session,
  hasOutcome,
  onClose,
  onSaved,
}: {
  session: VerificationSession;
  hasOutcome: boolean; // un résultat actif existe déjà : cette opération le supersède
  onClose: () => void;
  onSaved: () => void;
}) {
  const [files, setFiles] = useState<EvidenceFileOption[]>([]);
  const [loadingFiles, setLoadingFiles] = useState(true);
  const [filesError, setFilesError] = useState('');
  const [verified, setVerified] = useState('');
  const [eligible, setEligible] = useState('');
  const [documentId, setDocumentId] = useState('');
  const [adjustmentReason, setAdjustmentReason] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      setLoadingFiles(true);
      setFilesError('');
      const supabase = createClient();
      const { data, error: err } = await supabase
        .from('evidence_files')
        .select('id, file_url, timestamp')
        .eq('project_id', session.project_id)
        .eq('type', 'verification_report')
        .not('file_hash', 'is', null)
        .order('timestamp', { ascending: false });
      if (err) { setFilesError(getErrorMessage(err)); setLoadingFiles(false); return; }
      setFiles((data ?? []) as EvidenceFileOption[]);
      setLoadingFiles(false);
    })();
  }, [session.project_id]);

  const handleSubmit = async () => {
    setError('');
    const v = parseFloat(verified);
    const e = parseFloat(eligible);
    if (!verified || Number.isNaN(v) || v < 0) { setError('verified_reduction_tco2e invalide.'); return; }
    if (!eligible || Number.isNaN(e) || e < 0) { setError('eligible_tco2e invalide.'); return; }
    if (!documentId) { setError('Document de preuve (rapport de vérification) requis.'); return; }
    // Le serveur exige adjustment_reason dès qu'un résultat actif existe déjà
    // (supersession) — rendu obligatoire ici pour ne pas laisser l'appel
    // échouer inutilement après saisie du reste du formulaire.
    if (hasOutcome && !adjustmentReason.trim()) { setError('Motif d’ajustement requis : cette vérification supersède un résultat déjà actif.'); return; }
    setSaving(true);
    const supabase = createClient();
    const { error: err } = await supabase.rpc('complete_verification_session', {
      p_verification_session_id: session.id,
      p_verified_reduction_tco2e: v,
      p_eligible_tco2e: e,
      p_verification_report_document_id: documentId,
      p_adjustment_reason: adjustmentReason || null,
    });
    setSaving(false);
    if (err) { setError(getErrorMessage(err)); return; }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">{hasOutcome ? 'Corriger / superséder le résultat' : 'Compléter la vérification'}</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <div className="p-5 space-y-4">
          {hasOutcome && (
            <p className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg p-2">
              Un résultat actif existe déjà pour cette session. Cet appel en crée un nouveau qui le supersède (le précédent devient historique) — un motif d&apos;ajustement est obligatoire.
            </p>
          )}
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Réduction vérifiée (tCO2e) *</label>
              <input className="input w-full" type="number" min="0" step="0.0001" value={verified} onChange={(e) => setVerified(e.target.value)} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Admissible (tCO2e) *</label>
              <input className="input w-full" type="number" min="0" step="0.0001" value={eligible} onChange={(e) => setEligible(e.target.value)} />
            </div>
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Rapport de vérification (preuve) *</label>
            {loadingFiles ? (
              <p className="text-sm text-muted-foreground">Chargement…</p>
            ) : filesError ? (
              <ErrorBanner message={filesError} />
            ) : files.length === 0 ? (
              <p className="text-sm text-red-600">Aucune preuve de type verification_report (avec empreinte de fichier) pour ce projet.</p>
            ) : (
              <select className="input w-full" value={documentId} onChange={(e) => setDocumentId(e.target.value)}>
                <option value="">— Choisir —</option>
                {files.map((f) => (
                  <option key={f.id} value={f.id}>{f.file_url ? f.file_url.split('/').pop() : f.id}{f.timestamp ? ` (${fmtDate(f.timestamp)})` : ''}</option>
                ))}
              </select>
            )}
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Motif d&apos;ajustement{hasOutcome ? ' *' : ' (requis si divergence par rapport au calcul suggéré)'}</label>
            <textarea className="input w-full h-16 resize-none" value={adjustmentReason} onChange={(e) => setAdjustmentReason(e.target.value)} />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost flex-1 py-2 rounded-lg text-sm font-600">Annuler</button>
            <button type="button" disabled={saving} onClick={handleSubmit} className="btn-primary flex-1 py-2 rounded-lg text-sm font-600 disabled:opacity-50">
              {saving ? 'Enregistrement…' : hasOutcome ? 'Confirmer la supersession' : 'Compléter'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------------------
// Page principale
// ----------------------------------------------------------------------------

export default function AdminVerificationSessionsPage() {
  const [sessions, setSessions] = useState<VerificationSession[]>([]);
  const [projects, setProjects] = useState<{ id: string; name: string }[]>([]);
  const [sessionIdsWithOutcome, setSessionIdsWithOutcome] = useState<Set<string>>(new Set());
  const [currentUserId, setCurrentUserId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [listError, setListError] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [editSession, setEditSession] = useState<VerificationSession | null>(null);
  const [planSession, setPlanSession] = useState<VerificationSession | null>(null);
  const [completeSession, setCompleteSession] = useState<VerificationSession | null>(null);
  const [filterStatus, setFilterStatus] = useState<string>('all');

  const fetchData = useCallback(async () => {
    setLoading(true);
    setListError('');
    const supabase = createClient();
    const [sessRes, projRes, outcomeRes, userRes] = await Promise.all([
      supabase.from('verification_sessions').select('*, projects(name)').order('created_at', { ascending: false }),
      supabase.from('projects').select('id, name').order('name'),
      supabase.from('verification_outcomes').select('verification_session_id'),
      supabase.auth.getUser(),
    ]);
    const errors = [sessRes.error, projRes.error, outcomeRes.error, userRes.error].filter(Boolean);
    if (errors.length > 0) {
      setListError(errors.map((e) => getErrorMessage(e)).join(' · '));
      setLoading(false);
      return;
    }
    setSessions((sessRes.data ?? []) as VerificationSession[]);
    setProjects(projRes.data ?? []);
    setSessionIdsWithOutcome(new Set((outcomeRes.data ?? []).map((o: any) => o.verification_session_id)));
    setCurrentUserId(userRes.data?.user?.id ?? null);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filtered = filterStatus === 'all' ? sessions : sessions.filter((s) => s.status === filterStatus);

  const handleMarkInProgress = async (session: VerificationSession) => {
    setListError('');
    const supabase = createClient();
    const { error: err } = await supabase.from('verification_sessions').update({ status: 'in_progress' }).eq('id', session.id);
    if (err) { setListError(getErrorMessage(err)); return; }
    fetchData();
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Sessions de vérification</h1>
            <p className="text-sm text-muted-foreground mt-1">Gestion des vérifications tierces ISO 14064-2</p>
          </div>
          <button onClick={() => { setEditSession(null); setShowModal(true); }} className="btn-primary flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600">
            <Icon name="PlusCircleIcon" size={16} />
            Nouvelle session
          </button>
        </div>

        <ErrorBanner message={listError} />

        {/* KPIs */}
        <div className="grid grid-cols-3 gap-4 mb-6">
          {(['planned', 'in_progress', 'completed'] as const).map((s) => (
            <div key={s} className="bg-card border border-border rounded-xl p-4 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center">
                <Icon name={s === 'completed' ? 'CheckBadgeIcon' : s === 'in_progress' ? 'ClockIcon' : 'CalendarIcon'} size={20} className={s === 'completed' ? 'text-green-600' : s === 'in_progress' ? 'text-blue-600' : 'text-amber-600'} />
              </div>
              <div>
                <p className="text-2xl font-700 text-foreground">{sessions.filter((x) => x.status === s).length}</p>
                <p className="text-xs text-muted-foreground">{STATUS_CONFIG[s].label}</p>
              </div>
            </div>
          ))}
        </div>

        {/* Filter */}
        <div className="flex gap-2 mb-4">
          {['all', 'planned', 'in_progress', 'completed'].map((s) => (
            <button key={s} onClick={() => setFilterStatus(s)} className={`px-3 py-1.5 rounded-lg text-xs font-600 border transition-all ${filterStatus === s ? 'bg-primary text-primary-foreground border-primary' : 'bg-card text-muted-foreground border-border hover:border-primary/50'}`}>
              {s === 'all' ? 'Tous' : STATUS_CONFIG[s]?.label}
            </button>
          ))}
        </div>

        {loading ? (
          <div className="space-y-3">{[1, 2, 3].map((i) => <div key={i} className="h-24 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : filtered.length === 0 ? (
          <div className="bg-card border border-border rounded-xl p-12 text-center">
            <Icon name="CheckBadgeIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground font-500">Aucune session trouvée</p>
          </div>
        ) : (
          <div className="space-y-3">
            {filtered.map((session) => {
              const hasOutcome = sessionIdsWithOutcome.has(session.id);
              const frozen = hasOutcome || session.status === 'completed';
              const isPlanned = Boolean(session.reporting_period_start && session.reporting_period_end && session.verifier_user_id);
              const canMarkInProgress = session.status === 'planned' && isPlanned;
              const canPlan = !frozen;
              const canComplete = session.status !== 'planned' && session.verifier_user_id === currentUserId;
              return (
                <div key={session.id} className="bg-card border border-border rounded-xl p-5">
                  <div className="flex items-start justify-between gap-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-3 mb-1">
                        <p className="font-700 text-foreground">{session.verifier_org ?? 'Organisme non défini'}</p>
                        <span className={`px-2.5 py-0.5 rounded-full text-xs font-600 border ${STATUS_CONFIG[session.status]?.color}`}>
                          {STATUS_CONFIG[session.status]?.label}
                        </span>
                        {hasOutcome && <span className="px-2.5 py-0.5 rounded-full text-xs font-600 border text-purple-700 bg-purple-50 border-purple-200">Résultat enregistré</span>}
                      </div>
                      <p className="text-sm text-muted-foreground">
                        Projet: <span className="text-foreground font-500">{session.projects?.name ?? session.project_id}</span>
                      </p>
                      {session.verifier_contact && <p className="text-xs text-muted-foreground mt-0.5">{session.verifier_contact}</p>}
                      {session.reporting_period_start && (
                        <p className="text-xs text-muted-foreground mt-0.5">Période : {fmtDate(session.reporting_period_start)} → {fmtDate(session.reporting_period_end)}</p>
                      )}
                      {session.comments && <p className="text-sm text-muted-foreground mt-1 italic">{session.comments}</p>}
                    </div>
                    <div className="flex items-center gap-2 flex-shrink-0">
                      {session.report_url && (
                        <a href={session.report_url} target="_blank" rel="noopener noreferrer" className="btn-ghost p-2 rounded-lg">
                          <Icon name="ArrowTopRightOnSquareIcon" size={16} />
                        </a>
                      )}
                      <button onClick={() => { setEditSession(session); setShowModal(true); }} className="btn-ghost p-2 rounded-lg" title="Modifier">
                        <Icon name="PencilSquareIcon" size={16} />
                      </button>
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-2 mt-3">
                    {canPlan && (
                      <button onClick={() => setPlanSession(session)} className="btn-ghost px-3 py-1.5 rounded-lg text-xs font-600">
                        {session.verifier_user_id ? 'Replanifier' : 'Planifier'}
                      </button>
                    )}
                    {canMarkInProgress && (
                      <button onClick={() => handleMarkInProgress(session)} className="btn-ghost px-3 py-1.5 rounded-lg text-xs font-600">Marquer en cours</button>
                    )}
                    {canComplete && (
                      <button onClick={() => setCompleteSession(session)} className="btn-primary px-3 py-1.5 rounded-lg text-xs font-600">
                        {hasOutcome ? 'Corriger / superséder le résultat' : 'Compléter la vérification'}
                      </button>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground mt-2">Créé: {fmtDate(session.created_at)}</p>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {showModal && (
        <SessionModal
          session={editSession}
          projects={projects}
          frozen={editSession ? (sessionIdsWithOutcome.has(editSession.id) || editSession.status === 'completed') : false}
          onClose={() => { setShowModal(false); setEditSession(null); }}
          onSaved={fetchData}
        />
      )}
      {planSession && (
        <PlanModal session={planSession} onClose={() => setPlanSession(null)} onSaved={fetchData} />
      )}
      {completeSession && (
        <CompleteModal
          session={completeSession}
          hasOutcome={sessionIdsWithOutcome.has(completeSession.id)}
          onClose={() => setCompleteSession(null)}
          onSaved={fetchData}
        />
      )}
    </div>
  );
}
