'use client';
import React, { useEffect, useState, useCallback, useRef } from 'react';
import { createClient } from '@/lib/supabase/client';
import AppLayout from '@/components/AppLayout';
import Icon from '@/components/ui/AppIcon';

// ─── Types ────────────────────────────────────────────────────────────────────

interface VerificationSession {
  id: string;
  project_id: string;
  verifier_org: string | null;
  verifier_contact: string | null;
  scope: { period?: string; activities?: string; standard?: string } | null;
  status: 'planned' | 'in_progress' | 'completed';
  report_url: string | null;
  comments: string | null;
  created_at: string;
  projects?: { name: string; start_date: string | null; end_date: string | null } | null;
}

interface ActivityLog {
  id: string;
  project_id: string;
  activity_type: string;
  ghg_emissions_baseline_kgco2e: number | null;
  ghg_emissions_project_kgco2e: number | null;
  ghg_reduction_kgco2e: number | null;
  uncertainty_percent: number | null;
  timestamp: string;
  related_transport_request_id: string | null;
  projects?: { name: string } | null;
  transport_requests?: {
    transport_mode: string | null;
    distance_km: number | null;
    ghg_transport_kgco2e: number | null;
  } | null;
}

interface ScanEvent {
  id: string;
  container_id: string;
  action_type: string;
  gps_lat: number | null;
  gps_lng: number | null;
  scanned_at: string;
  event_hash: string | null;
  containers?: { name: string; qr_code: string } | null;
}

interface VerifierObservation {
  id: string;
  activity_log_id: string;
  observation_text: string;
  status: 'conforme' | 'non_conforme' | 'a_clarifier';
  created_at: string;
}

interface ChainResult {
  event_id: string;
  scanned_at: string;
  is_valid: boolean;
}

// ─── Status badge config ───────────────────────────────────────────────────────

const SESSION_STATUS: Record<string, { label: string; cls: string }> = {
  planned:     { label: 'Planifié',  cls: 'text-amber-700 bg-amber-50 border-amber-200' },
  in_progress: { label: 'En cours',  cls: 'text-blue-700 bg-blue-50 border-blue-200' },
  completed:   { label: 'Complété',  cls: 'text-green-700 bg-green-50 border-green-200' },
};

const OBS_STATUS: Record<string, { label: string; cls: string }> = {
  conforme:      { label: 'Conforme',     cls: 'text-green-700 bg-green-50 border-green-200' },
  non_conforme:  { label: 'Non conforme', cls: 'text-red-700 bg-red-50 border-red-200' },
  a_clarifier:   { label: 'À clarifier',  cls: 'text-amber-700 bg-amber-50 border-amber-200' },
};

// ─── Submit Report Modal ───────────────────────────────────────────────────────

interface SubmitReportModalProps {
  session: VerificationSession;
  onClose: () => void;
  onSaved: () => void;
}

function SubmitReportModal({ session, onClose, onSaved }: SubmitReportModalProps) {
  const [comments, setComments] = useState('');
  const [reportUrl, setReportUrl] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!comments.trim()) { setError('Les commentaires sont obligatoires.'); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const { error: err } = await supabase
      .from('verification_sessions')
      .update({
        status: 'completed',
        comments: comments.trim(),
        report_url: reportUrl.trim() || null,
      })
      .eq('id', session.id);
    setSaving(false);
    if (err) { setError(err.message); return; }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-base font-700 text-foreground">Soumettre le rapport de vérification</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">
              Commentaires de vérification <span className="text-red-500">*</span>
            </label>
            <textarea
              className="input w-full min-h-[100px] resize-y"
              placeholder="Observations, conclusions, recommandations…"
              value={comments}
              onChange={e => setComments(e.target.value)}
              required
            />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">
              Lien vers le rapport final <span className="text-muted-foreground text-xs">(optionnel)</span>
            </label>
            <input
              type="url"
              className="input w-full"
              placeholder="https://…"
              value={reportUrl}
              onChange={e => setReportUrl(e.target.value)}
            />
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex justify-end gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">
              Annuler
            </button>
            <button
              type="submit"
              disabled={saving}
              className="btn-primary px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50"
            >
              {saving ? 'Envoi…' : 'Soumettre'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Add Observation Modal ─────────────────────────────────────────────────────

interface AddObservationModalProps {
  activityLogId: string;
  verifierId: string;
  onClose: () => void;
  onSaved: () => void;
}

function AddObservationModal({ activityLogId, verifierId, onClose, onSaved }: AddObservationModalProps) {
  const [text, setText] = useState('');
  const [status, setStatus] = useState<'conforme' | 'non_conforme' | 'a_clarifier'>('conforme');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!text.trim()) { setError("L'observation est obligatoire."); return; }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const { error: err } = await supabase.from('verifier_observations').insert({
      activity_log_id: activityLogId,
      verifier_id: verifierId,
      observation_text: text.trim(),
      status,
    });
    setSaving(false);
    if (err) { setError(err.message); return; }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-md">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-base font-700 text-foreground">Ajouter une observation</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">
              Observation du vérificateur <span className="text-red-500">*</span>
            </label>
            <textarea
              className="input w-full min-h-[80px] resize-y"
              placeholder="Décrivez votre observation…"
              value={text}
              onChange={e => setText(e.target.value)}
              required
            />
          </div>
          <div>
            <label className="block text-sm font-600 text-foreground mb-1">Statut</label>
            <select
              className="input w-full"
              value={status}
              onChange={e => setStatus(e.target.value as typeof status)}
            >
              <option value="conforme">Conforme</option>
              <option value="non_conforme">Non conforme</option>
              <option value="a_clarifier">À clarifier</option>
            </select>
          </div>
          {error && <p className="text-sm text-red-600">{error}</p>}
          <div className="flex justify-end gap-3 pt-2">
            <button type="button" onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">
              Annuler
            </button>
            <button
              type="submit"
              disabled={saving}
              className="btn-primary px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50"
            >
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Chain Integrity Modal ─────────────────────────────────────────────────────

interface ChainModalProps {
  containerId: string;
  containerName: string;
  onClose: () => void;
}

function ChainModal({ containerId, containerName, onClose }: ChainModalProps) {
  const [results, setResults] = useState<ChainResult[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    const run = async () => {
      setLoading(true);
      const supabase = createClient();
      const { data, error: err } = await supabase.rpc('verify_container_chain', {
        p_container_id: containerId,
      });
      setLoading(false);
      if (err) { setError(err.message); return; }
      setResults((data as ChainResult[]) ?? []);
    };
    run();
  }, [containerId]);

  const allValid = results.length > 0 && results.every(r => r.is_valid);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg max-h-[80vh] flex flex-col">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <div>
            <h2 className="text-base font-700 text-foreground">Intégrité de la chaîne</h2>
            <p className="text-xs text-muted-foreground mt-0.5">{containerName}</p>
          </div>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg">
            <Icon name="XMarkIcon" size={18} />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-5">
          {loading ? (
            <div className="space-y-2">
              {[1, 2, 3].map(i => <div key={i} className="h-10 bg-muted rounded-lg animate-pulse" />)}
            </div>
          ) : error ? (
            <p className="text-sm text-red-600">{error}</p>
          ) : results.length === 0 ? (
            <p className="text-sm text-muted-foreground text-center py-6">Aucun événement pour ce conteneur.</p>
          ) : (
            <>
              <div className={`flex items-center gap-2 p-3 rounded-lg mb-4 text-sm font-600 ${
                allValid ? 'bg-green-50 text-green-700 border border-green-200' : 'bg-red-50 text-red-700 border border-red-200'
              }`}>
                <Icon name={allValid ? 'ShieldCheckIcon' : 'ExclamationTriangleIcon'} size={16} />
                {allValid ? 'Chaîne intègre — tous les événements sont valides' : 'Anomalie détectée — certains événements sont invalides'}
              </div>
              <div className="space-y-2">
                {results.map((r, i) => (
                  <div key={r.event_id} className="flex items-center gap-3 p-3 rounded-lg border border-border bg-background">
                    <span className="text-xs text-muted-foreground w-5 text-right flex-shrink-0">{i + 1}</span>
                    <Icon
                      name={r.is_valid ? 'LockClosedIcon' : 'LockOpenIcon'}
                      size={14}
                      className={r.is_valid ? 'text-green-600 flex-shrink-0' : 'text-red-600 flex-shrink-0'}
                    />
                    <span className="text-xs text-foreground flex-1 font-mono truncate">{r.event_id}</span>
                    <span className="text-xs text-muted-foreground flex-shrink-0">
                      {new Date(r.scanned_at).toLocaleString('fr-CA')}
                    </span>
                    <span className={`text-xs font-600 flex-shrink-0 ${r.is_valid ? 'text-green-600' : 'text-red-600'}`}>
                      {r.is_valid ? 'OK' : 'INVALIDE'}
                    </span>
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
        <div className="p-4 border-t border-border flex justify-end">
          <button onClick={onClose} className="btn-ghost px-4 py-2 rounded-lg text-sm font-600">
            Fermer
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Main Page ─────────────────────────────────────────────────────────────────

type TabId = 'projets' | 'logs' | 'preuves' | 'rapport';

export default function VerifierMRVPage() {
  const [authorized, setAuthorized] = useState<boolean | null>(null);
  const [currentUser, setCurrentUser] = useState<{ id: string; email: string } | null>(null);
  const [activeTab, setActiveTab] = useState<TabId>('projets');

  // Tab 1 — Sessions
  const [sessions, setSessions] = useState<VerificationSession[]>([]);
  const [loadingSessions, setLoadingSessions] = useState(true);
  const [submitModal, setSubmitModal] = useState<VerificationSession | null>(null);

  // Tab 2 — Activity logs
  const [logs, setLogs] = useState<ActivityLog[]>([]);
  const [loadingLogs, setLoadingLogs] = useState(false);
  const [observations, setObservations] = useState<Record<string, VerifierObservation[]>>({});
  const [obsModal, setObsModal] = useState<string | null>(null); // activity_log_id

  // Tab 3 — Scan events
  const [scanEvents, setScanEvents] = useState<ScanEvent[]>([]);
  const [loadingScans, setLoadingScans] = useState(false);
  const [chainModal, setChainModal] = useState<{ id: string; name: string } | null>(null);

  // Tab 4 — Synthesis
  const [exportingPdf, setExportingPdf] = useState(false);

  // ── Auth check ──────────────────────────────────────────────────────────────
  useEffect(() => {
    const checkAuth = async () => {
      const supabase = createClient();
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) { setAuthorized(false); return; }

      const roleMeta = user.raw_user_meta_data?.role ?? user.user_metadata?.role;
      if (roleMeta === 'verifier') {
        setAuthorized(true);
        setCurrentUser({ id: user.id, email: user.email ?? '' });
        return;
      }
      // Check company_members
      const { data: member } = await supabase
        .from('company_members')
        .select('role')
        .eq('user_id', user.id)
        .limit(1)
        .single();

      if (member?.role === 'verifier') {
        setAuthorized(true);
        setCurrentUser({ id: user.id, email: user.email ?? '' });
      } else {
        setAuthorized(false);
      }
    };
    checkAuth();
  }, []);

  // ── Fetch sessions (Tab 1) ──────────────────────────────────────────────────
  const fetchSessions = useCallback(async () => {
    if (!currentUser) return;
    setLoadingSessions(true);
    const supabase = createClient();

    const [statusResult, contactResult] = await Promise.all([
      supabase
        .from('verification_sessions')
        .select('*, projects(name, start_date, end_date)')
        .in('status', ['planned', 'in_progress'])
        .order('created_at', { ascending: false }),
      supabase
        .from('verification_sessions')
        .select('*, projects(name, start_date, end_date)')
        .eq('verifier_contact', currentUser.email)
        .order('created_at', { ascending: false }),
    ]);

    const merged = [...(statusResult.data ?? []), ...(contactResult.data ?? [])];
    const seen = new Set<string>();
    const deduplicated = merged.filter(s => {
      if (seen.has(s.id)) return false;
      seen.add(s.id);
      return true;
    });
    deduplicated.sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

    setSessions(deduplicated as VerificationSession[]);
    setLoadingSessions(false);
  }, [currentUser]);

  // ── Fetch logs (Tab 2) ──────────────────────────────────────────────────────
  const fetchLogs = useCallback(async () => {
    if (!currentUser) return;
    setLoadingLogs(true);
    const supabase = createClient();
    const { data } = await supabase
      .from('project_activity_logs')
      .select('*, projects(name)')
      .order('timestamp', { ascending: false })
      .limit(200);
    const logList = (data as ActivityLog[]) ?? [];

    const transportIds = logList
      .map(l => l.related_transport_request_id)
      .filter(Boolean) as string[];

    let transportMap: Record<string, { transport_mode: string | null; distance_km: number | null; ghg_transport_kgco2e: number | null }> = {};

    if (transportIds.length > 0) {
      const { data: transports } = await supabase
        .from('transport_requests')
        .select('id, transport_mode, distance_km, ghg_transport_kgco2e')
        .in('id', transportIds);
      
      if (transports) {
        transportMap = Object.fromEntries(
          transports.map(t => [t.id, { 
            transport_mode: t.transport_mode, 
            distance_km: t.distance_km, 
            ghg_transport_kgco2e: t.ghg_transport_kgco2e 
          }])
        );
      }
    }

    const enrichedLogs = logList.map(l => ({
      ...l,
      transport_requests: l.related_transport_request_id 
        ? transportMap[l.related_transport_request_id] ?? null 
        : null
    }));

    setLogs(enrichedLogs);

    // Fetch observations for these logs
    if (logList.length > 0) {
      const ids = logList.map(l => l.id);
      const { data: obsData } = await supabase
        .from('verifier_observations')
        .select('*')
        .in('activity_log_id', ids)
        .eq('verifier_id', currentUser.id);
      const obsMap: Record<string, VerifierObservation[]> = {};
      for (const obs of (obsData as VerifierObservation[]) ?? []) {
        if (!obsMap[obs.activity_log_id]) obsMap[obs.activity_log_id] = [];
        obsMap[obs.activity_log_id].push(obs);
      }
      setObservations(obsMap);
    }
    setLoadingLogs(false);
  }, [currentUser]);

  // ── Fetch scan events (Tab 3) ───────────────────────────────────────────────
  const fetchScanEvents = useCallback(async () => {
    if (!currentUser) return;
    setLoadingScans(true);
    const supabase = createClient();
    const { data } = await supabase
      .from('scan_events')
      .select('*, containers(name, qr_code)')
      .order('scanned_at', { ascending: false })
      .limit(300);
    setScanEvents((data as ScanEvent[]) ?? []);
    setLoadingScans(false);
  }, [currentUser]);

  useEffect(() => {
    if (!currentUser) return;
    fetchSessions();
  }, [currentUser, fetchSessions]);

  useEffect(() => {
    if (!currentUser || activeTab !== 'logs') return;
    fetchLogs();
  }, [currentUser, activeTab, fetchLogs]);

  useEffect(() => {
    if (!currentUser || activeTab !== 'preuves') return;
    fetchScanEvents();
  }, [currentUser, activeTab, fetchScanEvents]);

  // ── Start verification ──────────────────────────────────────────────────────
  const handleStart = async (sessionId: string) => {
    const supabase = createClient();
    const { error } = await supabase
      .from('verification_sessions')
      .update({ status: 'in_progress' })
      .eq('id', sessionId);
    if (error) {
      console.error('handleStart error:', error.message, error.code);
      alert('Erreur: ' + error.message);
      return;
    }
    fetchSessions();
  };

  // ── PDF Export (Tab 4) ──────────────────────────────────────────────────────
  const handleExportPdf = async () => {
    if (!currentUser) return;
    setExportingPdf(true);
    try {
      const totalReduction = logs.reduce((s, l) => s + (l.ghg_reduction_kgco2e ?? 0), 0);
      const totalBaseline = logs.reduce((s, l) => s + (l.ghg_emissions_baseline_kgco2e ?? 0), 0);
      const totalProject = logs.reduce((s, l) => s + (l.ghg_emissions_project_kgco2e ?? 0), 0);
      const transportLogs = logs.filter(l => l.related_transport_request_id);
      const traceable = scanEvents.filter(s => s.event_hash).length;

      const allObs: VerifierObservation[] = Object.values(observations).flat();

      // ── Fetch completed sessions with comments for the conclusion section ──
      const supabase = createClient();
      const { data: completedSessionsData } = await supabase
        .from('verification_sessions')
        .select('*, projects(name, start_date, end_date)')
        .eq('status', 'completed')
        .not('comments', 'is', null)
        .order('created_at', { ascending: false });
      const completedSessions: VerificationSession[] = (completedSessionsData ?? []).filter(
        (s: VerificationSession) => s.comments && s.comments.trim() !== ''
      );

      const modeStats: Record<string, { count: number; dist: number; baseline: number; project: number; reduction: number }> = {};
      for (const l of logs) {
        const mode = l.transport_requests?.transport_mode ?? 'inconnu';
        if (!modeStats[mode]) modeStats[mode] = { count: 0, dist: 0, baseline: 0, project: 0, reduction: 0 };
        modeStats[mode].count++;
        modeStats[mode].dist += l.transport_requests?.distance_km ?? 0;
        modeStats[mode].baseline += l.ghg_emissions_baseline_kgco2e ?? 0;
        modeStats[mode].project += l.ghg_emissions_project_kgco2e ?? 0;
        modeStats[mode].reduction += l.ghg_reduction_kgco2e ?? 0;
      }

      const now = new Date();
      const dateStr = now.toLocaleDateString('fr-CA');

      const html = `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="UTF-8"/>
<title>Rapport MRV — MetalTrace</title>
<style>
  body { font-family: Arial, sans-serif; font-size: 12px; color: #1a1a1a; margin: 40px; }
  h1 { font-size: 20px; color: #1a1a1a; margin-bottom: 4px; }
  h2 { font-size: 14px; color: #374151; margin-top: 24px; margin-bottom: 8px; border-bottom: 1px solid #e5e7eb; padding-bottom: 4px; }
  .header { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 24px; }
  .badge { background: #f0fdf4; color: #166534; border: 1px solid #bbf7d0; padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: bold; }
  .kpi-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; margin-bottom: 24px; }
  .kpi { background: #f9fafb; border: 1px solid #e5e7eb; border-radius: 8px; padding: 12px; text-align: center; }
  .kpi-value { font-size: 18px; font-weight: bold; color: #059669; }
  .kpi-label { font-size: 10px; color: #6b7280; margin-top: 2px; }
  table { width: 100%; border-collapse: collapse; font-size: 11px; }
  th { background: #f3f4f6; text-align: left; padding: 6px 8px; font-weight: 600; border: 1px solid #e5e7eb; }
  td { padding: 5px 8px; border: 1px solid #e5e7eb; }
  tr:nth-child(even) td { background: #f9fafb; }
  .obs-item { margin-bottom: 8px; padding: 8px; background: #f9fafb; border-left: 3px solid #6b7280; border-radius: 4px; }
  .obs-status { font-size: 10px; font-weight: bold; }
  .conforme { color: #166534; }
  .non_conforme { color: #991b1b; }
  .a_clarifier { color: #92400e; }
  .conclusion-item { margin-bottom: 8px; padding: 8px; background: #f0fdf4; border-left: 3px solid #059669; border-radius: 4px; }
  .conclusion-org { font-size: 10px; font-weight: bold; color: #166534; }
  .conclusion-project { font-size: 10px; color: #6b7280; margin-bottom: 4px; }
  .signature { margin-top: 40px; padding: 16px; border: 1px solid #e5e7eb; border-radius: 8px; background: #f9fafb; }
  .sig-line { margin-top: 8px; font-size: 11px; color: #374151; }
  .footer { margin-top: 32px; font-size: 10px; color: #9ca3af; text-align: center; }
</style>
</head>
<body>
<div class="header">
  <div>
    <h1>METALTRACE — Rapport de vérification MRV</h1>
    <p style="color:#6b7280;margin:0">ISO 14064-2 — Monitoring, Reporting, Verification</p>
    <p style="color:#6b7280;margin:4px 0 0">Généré le ${dateStr}</p>
  </div>
  <span class="badge">Vérifié via MetalTrace dMRV</span>
</div>

<h2>KPIs de synthèse</h2>
<div class="kpi-grid">
  <div class="kpi"><div class="kpi-value">${(totalReduction / 1000).toFixed(3)}</div><div class="kpi-label">tCO₂e réduites</div></div>
  <div class="kpi"><div class="kpi-value">${transportLogs.length}</div><div class="kpi-label">Transports vérifiés</div></div>
  <div class="kpi"><div class="kpi-value">${traceable}</div><div class="kpi-label">Lots traçables</div></div>
  <div class="kpi"><div class="kpi-value">${logs.length}</div><div class="kpi-label">Activités totales</div></div>
</div>

<h2>Répartition par mode de transport</h2>
<table>
  <thead>
    <tr>
      <th>Mode</th><th>Nb transports</th><th>Distance km</th>
      <th>Baseline kgCO₂e</th><th>Projet kgCO₂e</th><th>Réduction kgCO₂e</th>
    </tr>
  </thead>
  <tbody>
    ${Object.entries(modeStats).map(([mode, s]) => `
    <tr>
      <td>${mode}</td>
      <td>${s.count}</td>
      <td>${s.dist.toFixed(1)}</td>
      <td>${s.baseline.toFixed(2)}</td>
      <td>${s.project.toFixed(2)}</td>
      <td>${s.reduction.toFixed(2)}</td>
    </tr>`).join('')}
    <tr style="font-weight:bold;background:#f0fdf4">
      <td>TOTAL</td>
      <td>${logs.length}</td>
      <td>—</td>
      <td>${totalBaseline.toFixed(2)}</td>
      <td>${totalProject.toFixed(2)}</td>
      <td>${totalReduction.toFixed(2)}</td>
    </tr>
  </tbody>
</table>

<h2>Observations du vérificateur (${allObs.length})</h2>
${allObs.length === 0 ? '<p style="color:#6b7280">Aucune observation enregistrée.</p>' :
  allObs.map(o => `
<div class="obs-item">
  <span class="obs-status ${o.status}">${OBS_STATUS[o.status]?.label ?? o.status}</span>
  <p style="margin:4px 0 0">${o.observation_text}</p>
  <p style="margin:2px 0 0;color:#9ca3af;font-size:10px">${new Date(o.created_at).toLocaleString('fr-CA')}</p>
</div>`).join('')}

<h2>Conclusion de la vérification (${completedSessions.length})</h2>
${completedSessions.length === 0
  ? '<p style="color:#6b7280">Aucune session de vérification clôturée avec commentaire.</p>'
  : completedSessions.map(cs => `
<div class="conclusion-item">
  <div class="conclusion-org">${cs.verifier_org ?? 'Organisation non renseignée'}</div>
  ${cs.projects?.name ? `<div class="conclusion-project">Projet : ${cs.projects.name}</div>` : ''}
  <p style="margin:4px 0 0">${cs.comments}</p>
  ${cs.report_url ? `<p style="margin:4px 0 0;font-size:10px"><a href="${cs.report_url}" style="color:#059669">Voir le rapport officiel</a></p>` : ''}
</div>`).join('')}

<div class="signature">
  <strong>Signature électronique</strong>
  <div class="sig-line">Vérificateur : ${currentUser.email}</div>
  <div class="sig-line">Date : ${dateStr}</div>
  <div class="sig-line">Plateforme : Vérifié via MetalTrace dMRV — ISO 14064-2</div>
</div>

<div class="footer">MetalTrace dMRV — Rapport généré automatiquement — ${now.toISOString()}</div>
</body>
</html>`;

      const blob = new Blob([html], { type: 'text/html' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `rapport-mrv-${dateStr}.html`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error('Erreur export PDF:', err);
      alert('Une erreur est survenue lors de la génération du rapport. Veuillez réessayer.');
    }
    setExportingPdf(false);
  };

  // ── Computed values for Tab 4 ───────────────────────────────────────────────
  const totalReduction = logs.reduce((s, l) => s + (l.ghg_reduction_kgco2e ?? 0), 0);
  const totalBaseline = logs.reduce((s, l) => s + (l.ghg_emissions_baseline_kgco2e ?? 0), 0);
  const totalProject = logs.reduce((s, l) => s + (l.ghg_emissions_project_kgco2e ?? 0), 0);
  const transportLogs = logs.filter(l => l.related_transport_request_id);
  const traceableLots = scanEvents.filter(s => s.event_hash).length;
  const timestamps = logs.map(l => l.timestamp).filter(Boolean).sort();
  const periodMin = timestamps[0] ? new Date(timestamps[0]).toLocaleDateString('fr-CA') : '—';
  const periodMax = timestamps[timestamps.length - 1] ? new Date(timestamps[timestamps.length - 1]).toLocaleDateString('fr-CA') : '—';

  const modeStats: Record<string, { count: number; dist: number; baseline: number; project: number; reduction: number }> = {};
  for (const l of logs) {
    const mode = l.transport_requests?.transport_mode ?? 'inconnu';
    if (!modeStats[mode]) modeStats[mode] = { count: 0, dist: 0, baseline: 0, project: 0, reduction: 0 };
    modeStats[mode].count++;
    modeStats[mode].dist += l.transport_requests?.distance_km ?? 0;
    modeStats[mode].baseline += l.ghg_emissions_baseline_kgco2e ?? 0;
    modeStats[mode].project += l.ghg_emissions_project_kgco2e ?? 0;
    modeStats[mode].reduction += l.ghg_reduction_kgco2e ?? 0;
  }

  // ── Render guards ───────────────────────────────────────────────────────────
  if (authorized === null) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (authorized === false) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center p-4">
        <div className="bg-card border border-border rounded-xl p-10 text-center max-w-sm">
          <Icon name="ShieldExclamationIcon" size={40} className="text-red-500 mx-auto mb-3" />
          <h2 className="text-lg font-700 text-foreground mb-2">Accès refusé</h2>
          <p className="text-sm text-muted-foreground">
            Cette page est réservée aux utilisateurs avec le rôle <strong>vérificateur</strong>.
          </p>
        </div>
      </div>
    );
  }

  const tabs: { id: TabId; label: string; icon: string }[] = [
    { id: 'projets',  label: 'Projets assignés',       icon: 'ClipboardDocumentCheckIcon' },
    { id: 'logs',     label: 'Logs d\'activité GES',   icon: 'TableCellsIcon' },
    { id: 'preuves',  label: 'Preuves & traçabilité',  icon: 'LinkIcon' },
    { id: 'rapport',  label: 'Rapport de synthèse',    icon: 'DocumentChartBarIcon' },
  ];

  return (
    <AppLayout activeRoute="/verifier-mrv" userRole="verifier">
      {/* Modals */}
      {submitModal && (
        <SubmitReportModal
          session={submitModal}
          onClose={() => setSubmitModal(null)}
          onSaved={fetchSessions}
        />
      )}
      {obsModal && currentUser && (
        <AddObservationModal
          activityLogId={obsModal}
          verifierId={currentUser.id}
          onClose={() => setObsModal(null)}
          onSaved={fetchLogs}
        />
      )}
      {chainModal && (
        <ChainModal
          containerId={chainModal.id}
          containerName={chainModal.name}
          onClose={() => setChainModal(null)}
        />
      )}

      {/* Page header */}
      <div className="mb-6">
        <div className="flex items-center gap-2 mb-1">
          <span className="px-2.5 py-1 rounded-full text-xs font-700 bg-purple-50 text-purple-700 border border-purple-200">
            Accès Vérificateur — ISO 14064-2
          </span>
        </div>
        <h1 className="text-2xl font-700 text-foreground">Interface de vérification MRV</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Monitoring, Reporting, Verification — Audit indépendant
        </p>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 border-b border-border mb-6 overflow-x-auto">
        {tabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-2 px-4 py-2.5 text-sm font-600 border-b-2 transition-all -mb-px whitespace-nowrap ${
              activeTab === tab.id
                ? 'border-primary text-primary' :'border-transparent text-muted-foreground hover:text-foreground'
            }`}
          >
            <Icon name={tab.icon as Parameters<typeof Icon>[0]['name']} size={14} />
            {tab.label}
          </button>
        ))}
      </div>

      {/* ═══ TAB 1 — Projets assignés ═══════════════════════════════════════════ */}
      {activeTab === 'projets' && (
        <div className="space-y-4">
          {loadingSessions ? (
            <div className="space-y-3">
              {[1, 2, 3].map(i => <div key={i} className="h-36 bg-muted rounded-xl animate-pulse" />)}
            </div>
          ) : sessions.length === 0 ? (
            <div className="bg-card border border-border rounded-xl p-12 text-center">
              <Icon name="ClipboardDocumentCheckIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
              <p className="text-muted-foreground text-sm">Aucune session de vérification assignée</p>
            </div>
          ) : sessions.map(session => {
            const scope = session.scope;
            return (
              <div key={session.id} className="bg-card border border-border rounded-xl p-5">
                <div className="flex items-start justify-between gap-4 mb-4">
                  <div className="flex-1 min-w-0">
                    <h3 className="font-700 text-foreground text-base truncate">
                      {session.projects?.name ?? 'Projet inconnu'}
                    </h3>
                    {session.verifier_org && (
                      <p className="text-sm text-muted-foreground mt-0.5">{session.verifier_org}</p>
                    )}
                  </div>
                  <span className={`px-2.5 py-1 rounded-full text-xs font-600 border flex-shrink-0 ${SESSION_STATUS[session.status]?.cls}`}>
                    {SESSION_STATUS[session.status]?.label}
                  </span>
                </div>

                {/* Scope */}
                {scope && (
                  <div className="grid grid-cols-3 gap-3 mb-4 p-3 bg-muted/40 rounded-lg">
                    {scope.period && (
                      <div>
                        <p className="text-xs text-muted-foreground mb-0.5">Période</p>
                        <p className="text-xs font-600 text-foreground">{scope.period}</p>
                      </div>
                    )}
                    {scope.activities && (
                      <div>
                        <p className="text-xs text-muted-foreground mb-0.5">Activités</p>
                        <p className="text-xs font-600 text-foreground">{scope.activities}</p>
                      </div>
                    )}
                    {scope.standard && (
                      <div>
                        <p className="text-xs text-muted-foreground mb-0.5">Standard</p>
                        <p className="text-xs font-600 text-foreground">{scope.standard}</p>
                      </div>
                    )}
                  </div>
                )}

                {/* Period */}
                {(session.projects?.start_date || session.projects?.end_date) && (
                  <p className="text-xs text-muted-foreground mb-4">
                    Période couverte :{' '}
                    <span className="font-600 text-foreground">
                      {session.projects.start_date ?? '?'} → {session.projects.end_date ?? 'en cours'}
                    </span>
                  </p>
                )}

                {/* Comments */}
                {session.comments && (
                  <p className="text-sm text-muted-foreground italic mb-4 border-l-2 border-border pl-3">
                    {session.comments}
                  </p>
                )}

                {/* Actions */}
                <div className="flex items-center gap-3 flex-wrap">
                  {session.status === 'planned' && (
                    <button
                      onClick={() => handleStart(session.id)}
                      className="btn-primary flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600"
                    >
                      <Icon name="PlayIcon" size={14} />
                      Démarrer la vérification
                    </button>
                  )}
                  {session.status === 'in_progress' && (
                    <button
                      onClick={() => setSubmitModal(session)}
                      className="flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600 bg-green-600 text-white hover:bg-green-700 transition-colors"
                    >
                      <Icon name="DocumentCheckIcon" size={14} />
                      Soumettre le rapport
                    </button>
                  )}
                  {session.report_url && (
                    <a
                      href={session.report_url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="btn-ghost flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-600"
                    >
                      <Icon name="ArrowTopRightOnSquareIcon" size={14} />
                      Voir le rapport
                    </a>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ═══ TAB 2 — Logs d'activité GES ════════════════════════════════════════ */}
      {activeTab === 'logs' && (
        <div>
          {loadingLogs ? (
            <div className="space-y-2">
              {[1, 2, 3, 4].map(i => <div key={i} className="h-14 bg-muted rounded-xl animate-pulse" />)}
            </div>
          ) : logs.length === 0 ? (
            <div className="bg-card border border-border rounded-xl p-12 text-center">
              <Icon name="TableCellsIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
              <p className="text-muted-foreground text-sm">Aucun log d'activité disponible</p>
            </div>
          ) : (
            <div className="bg-card border border-border rounded-xl overflow-hidden">
              <div className="overflow-x-auto">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b border-border bg-muted/40">
                      <th className="text-left px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Date/heure</th>
                      <th className="text-left px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Projet</th>
                      <th className="text-left px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Type</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Baseline kgCO₂e</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Projet kgCO₂e</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Réduction kgCO₂e</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Incertitude</th>
                      <th className="text-center px-4 py-3 font-600 text-muted-foreground whitespace-nowrap">Observations</th>
                      <th className="px-4 py-3"></th>
                    </tr>
                  </thead>
                  <tbody>
                    {logs.map((log, idx) => {
                      const logObs = observations[log.id] ?? [];
                      return (
                        <tr key={log.id} className={`border-b border-border last:border-0 ${idx % 2 === 0 ? '' : 'bg-muted/20'}`}>
                          <td className="px-4 py-3 text-muted-foreground whitespace-nowrap">
                            {new Date(log.timestamp).toLocaleString('fr-CA')}
                          </td>
                          <td className="px-4 py-3 font-600 text-foreground whitespace-nowrap">
                            {log.projects?.name ?? '—'}
                          </td>
                          <td className="px-4 py-3 whitespace-nowrap">
                            <span className="px-2 py-0.5 rounded-full text-xs font-600 bg-blue-50 text-blue-700 border border-blue-200">
                              {log.activity_type}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-right text-red-600 font-600 whitespace-nowrap">
                            {(log.ghg_emissions_baseline_kgco2e ?? 0).toFixed(3)}
                          </td>
                          <td className="px-4 py-3 text-right text-blue-600 font-600 whitespace-nowrap">
                            {(log.ghg_emissions_project_kgco2e ?? 0).toFixed(3)}
                          </td>
                          <td className="px-4 py-3 text-right whitespace-nowrap">
                            <span className="px-2 py-0.5 rounded-full text-xs font-700 bg-green-50 text-green-700 border border-green-200">
                              {(log.ghg_reduction_kgco2e ?? 0).toFixed(3)}
                            </span>
                          </td>
                          <td className="px-4 py-3 text-right text-amber-600 font-600 whitespace-nowrap">
                            ±{(log.uncertainty_percent ?? 0).toFixed(1)}%
                          </td>
                          <td className="px-4 py-3 text-center">
                            {logObs.length > 0 && (
                              <div className="flex flex-wrap gap-1 justify-center">
                                {logObs.map(o => (
                                  <span key={o.id} className={`px-1.5 py-0.5 rounded text-[10px] font-600 border ${OBS_STATUS[o.status]?.cls}`}>
                                    {OBS_STATUS[o.status]?.label}
                                  </span>
                                ))}
                              </div>
                            )}
                          </td>
                          <td className="px-4 py-3 whitespace-nowrap">
                            <div className="flex items-center gap-2">
                              {log.related_transport_request_id && (
                                <span title="Transport lié" className="text-blue-500">
                                  <Icon name="TruckIcon" size={12} />
                                </span>
                              )}
                              <button
                                onClick={() => setObsModal(log.id)}
                                className="btn-ghost px-2 py-1 rounded text-xs font-600 flex items-center gap-1 whitespace-nowrap"
                              >
                                <Icon name="PlusIcon" size={12} />
                                Observation
                              </button>
                            </div>
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}

      {/* ═══ TAB 3 — Preuves & traçabilité ══════════════════════════════════════ */}
      {activeTab === 'preuves' && (
        <div>
          {loadingScans ? (
            <div className="space-y-3">
              {[1, 2, 3].map(i => <div key={i} className="h-16 bg-muted rounded-xl animate-pulse" />)}
            </div>
          ) : scanEvents.length === 0 ? (
            <div className="bg-card border border-border rounded-xl p-12 text-center">
              <Icon name="LinkIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
              <p className="text-muted-foreground text-sm">Aucun événement de scan disponible</p>
            </div>
          ) : (
            <>
              {/* Group by container */}
              {(() => {
                const byContainer: Record<string, ScanEvent[]> = {};
                for (const ev of scanEvents) {
                  const key = ev.container_id;
                  if (!byContainer[key]) byContainer[key] = [];
                  byContainer[key].push(ev);
                }
                return Object.entries(byContainer).map(([containerId, events]) => {
                  const containerName = events[0]?.containers?.name ?? containerId.slice(0, 8);
                  return (
                    <div key={containerId} className="bg-card border border-border rounded-xl mb-4 overflow-hidden">
                      <div className="flex items-center justify-between px-5 py-3 border-b border-border bg-muted/30">
                        <div className="flex items-center gap-2">
                          <Icon name="ArchiveBoxIcon" size={16} className="text-muted-foreground" />
                          <span className="font-700 text-foreground text-sm">{containerName}</span>
                          <span className="text-xs text-muted-foreground font-mono">
                            {events[0]?.containers?.qr_code}
                          </span>
                        </div>
                        <button
                          onClick={() => setChainModal({ id: containerId, name: containerName })}
                          className="btn-ghost flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-600"
                        >
                          <Icon name="ShieldCheckIcon" size={13} />
                          Vérifier l'intégrité
                        </button>
                      </div>
                      <div className="divide-y divide-border">
                        {events.map(ev => (
                          <div key={ev.id} className="flex items-center gap-4 px-5 py-3">
                            {/* Timeline dot */}
                            <div className="flex-shrink-0 w-2 h-2 rounded-full bg-primary" />
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2 flex-wrap">
                                <span className={`px-2 py-0.5 rounded text-xs font-600 border ${
                                  ev.action_type === 'depot' ? 'bg-blue-50 text-blue-700 border-blue-200' :
                                  ev.action_type === 'collecte'? 'bg-amber-50 text-amber-700 border-amber-200' : 'bg-purple-50 text-purple-700 border-purple-200'
                                }`}>
                                  {ev.action_type}
                                </span>
                                <span className="text-xs text-muted-foreground">
                                  {new Date(ev.scanned_at).toLocaleString('fr-CA')}
                                </span>
                                {ev.gps_lat && ev.gps_lng && (
                                  <span className="text-xs text-muted-foreground">
                                    GPS: {Number(ev.gps_lat).toFixed(4)}, {Number(ev.gps_lng).toFixed(4)}
                                  </span>
                                )}
                              </div>
                            </div>
                            {ev.event_hash ? (
                              <div className="flex items-center gap-1 text-green-600 flex-shrink-0" title="Chaîne intègre">
                                <Icon name="LockClosedIcon" size={14} />
                                <span className="text-xs font-600">Signé</span>
                              </div>
                            ) : (
                              <div className="flex items-center gap-1 text-muted-foreground flex-shrink-0">
                                <Icon name="LockOpenIcon" size={14} />
                                <span className="text-xs">Non signé</span>
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  );
                });
              })()}
            </>
          )}
        </div>
      )}

      {/* ═══ TAB 4 — Rapport de synthèse ════════════════════════════════════════ */}
      {activeTab === 'rapport' && (
        <div className="space-y-6">
          {/* KPIs */}
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
            {[
              { label: 'Réductions GES vérifiées', value: `${(totalReduction / 1000).toFixed(3)} tCO₂e`, color: 'text-green-600', icon: 'CloudIcon' },
              { label: 'Transports vérifiés', value: String(transportLogs.length), color: 'text-blue-600', icon: 'TruckIcon' },
              { label: 'Lots traçables (hash)', value: String(traceableLots), color: 'text-purple-600', icon: 'LinkIcon' },
              { label: 'Période couverte', value: `${periodMin} → ${periodMax}`, color: 'text-amber-600', icon: 'CalendarIcon' },
            ].map(kpi => (
              <div key={kpi.label} className="bg-card border border-border rounded-xl p-4">
                <div className="flex items-center gap-2 mb-2">
                  <Icon name={kpi.icon as Parameters<typeof Icon>[0]['name']} size={16} className="text-muted-foreground" />
                  <p className="text-xs text-muted-foreground">{kpi.label}</p>
                </div>
                <p className={`text-xl font-700 ${kpi.color}`}>{kpi.value}</p>
              </div>
            ))}
          </div>

          {/* Breakdown by transport mode */}
          <div className="bg-card border border-border rounded-xl overflow-hidden">
            <div className="px-5 py-3 border-b border-border">
              <h2 className="font-700 text-foreground text-sm">Répartition par mode de transport</h2>
            </div>
            {Object.keys(modeStats).length === 0 ? (
              <div className="p-8 text-center">
                <p className="text-sm text-muted-foreground">Aucune donnée de transport disponible</p>
              </div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-xs">
                  <thead>
                    <tr className="border-b border-border bg-muted/40">
                      <th className="text-left px-4 py-3 font-600 text-muted-foreground">Mode</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground">Nb transports</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground">Distance km</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground">Baseline kgCO₂e</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground">Projet kgCO₂e</th>
                      <th className="text-right px-4 py-3 font-600 text-muted-foreground">Réduction kgCO₂e</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Object.entries(modeStats).map(([mode, s], idx) => (
                      <tr key={mode} className={`border-b border-border last:border-0 ${idx % 2 === 0 ? '' : 'bg-muted/20'}`}>
                        <td className="px-4 py-3 font-600 text-foreground capitalize">{mode}</td>
                        <td className="px-4 py-3 text-right text-foreground">{s.count}</td>
                        <td className="px-4 py-3 text-right text-foreground">{s.dist.toFixed(1)}</td>
                        <td className="px-4 py-3 text-right text-red-600 font-600">{s.baseline.toFixed(2)}</td>
                        <td className="px-4 py-3 text-right text-blue-600 font-600">{s.project.toFixed(2)}</td>
                        <td className="px-4 py-3 text-right">
                          <span className="px-2 py-0.5 rounded-full text-xs font-700 bg-green-50 text-green-700 border border-green-200">
                            {s.reduction.toFixed(2)}
                          </span>
                        </td>
                      </tr>
                    ))}
                    <tr className="bg-muted/40 font-700">
                      <td className="px-4 py-3 text-foreground">TOTAL</td>
                      <td className="px-4 py-3 text-right text-foreground">{logs.length}</td>
                      <td className="px-4 py-3 text-right text-muted-foreground">—</td>
                      <td className="px-4 py-3 text-right text-red-600">{totalBaseline.toFixed(2)}</td>
                      <td className="px-4 py-3 text-right text-blue-600">{totalProject.toFixed(2)}</td>
                      <td className="px-4 py-3 text-right text-green-600">{totalReduction.toFixed(2)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            )}
          </div>

          {/* Export button */}
          <div className="flex justify-end">
            <button
              onClick={handleExportPdf}
              disabled={exportingPdf}
              className="btn-primary flex items-center gap-2 px-5 py-2.5 rounded-lg text-sm font-600 disabled:opacity-50"
            >
              <Icon name="ArrowDownTrayIcon" size={16} />
              {exportingPdf ? 'Génération…' : 'Exporter en PDF'}
            </button>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
