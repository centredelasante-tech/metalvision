'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

interface Project {
  id: string;
  name: string;
  description: string | null;
  status: string;
  baseline_description: string | null;
  project_scenario_description: string | null;
  start_date: string | null;
  end_date: string | null;
}

interface ActivityLog {
  id: string;
  activity_type: string;
  ghg_emissions_baseline_kgco2e: number;
  ghg_emissions_project_kgco2e: number;
  ghg_reduction_kgco2e: number;
  uncertainty_percent: number;
  timestamp: string;
}

interface EvidenceFile {
  id: string;
  type: string;
  file_url: string | null;
  timestamp: string;
  gps: Record<string, unknown> | null;
}

interface VerificationSession {
  id: string;
  verifier_org: string | null;
  verifier_contact: string | null;
  status: string;
  report_url: string | null;
  comments: string | null;
  created_at: string;
}

export default function VerifierMRVPage() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [selectedProjectId, setSelectedProjectId] = useState<string>('');
  const [logs, setLogs] = useState<ActivityLog[]>([]);
  const [evidence, setEvidence] = useState<EvidenceFile[]>([]);
  const [sessions, setSessions] = useState<VerificationSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingDetail, setLoadingDetail] = useState(false);
  const [exporting, setExporting] = useState(false);
  const [activeTab, setActiveTab] = useState<'activities' | 'evidence' | 'verification'>('activities');

  const fetchProjects = useCallback(async () => {
    setLoading(true);
    const supabase = createClient();
    const { data } = await supabase.from('projects').select('*').order('created_at', { ascending: false });
    const list = data ?? [];
    setProjects(list);
    if (list.length > 0) setSelectedProjectId(list[0].id);
    setLoading(false);
  }, []);

  const fetchProjectDetail = useCallback(async (projectId: string) => {
    if (!projectId) return;
    setLoadingDetail(true);
    const supabase = createClient();
    const [logsRes, evRes, sessRes] = await Promise.all([
      supabase.from('project_activity_logs').select('*').eq('project_id', projectId).order('timestamp', { ascending: false }),
      supabase.from('evidence_files').select('*').eq('project_id', projectId).order('timestamp', { ascending: false }),
      supabase.from('verification_sessions').select('*').eq('project_id', projectId).order('created_at', { ascending: false }),
    ]);
    setLogs(logsRes.data ?? []);
    setEvidence(evRes.data ?? []);
    setSessions(sessRes.data ?? []);
    setLoadingDetail(false);
  }, []);

  useEffect(() => { fetchProjects(); }, [fetchProjects]);
  useEffect(() => { if (selectedProjectId) fetchProjectDetail(selectedProjectId); }, [selectedProjectId, fetchProjectDetail]);

  const selectedProject = projects.find(p => p.id === selectedProjectId);
  const totalBaseline = logs.reduce((s, l) => s + (l.ghg_emissions_baseline_kgco2e ?? 0), 0);
  const totalProject = logs.reduce((s, l) => s + (l.ghg_emissions_project_kgco2e ?? 0), 0);
  const totalReduction = logs.reduce((s, l) => s + (l.ghg_reduction_kgco2e ?? 0), 0);

  const handleExport = async () => {
    if (!selectedProjectId) return;
    setExporting(true);
    try {
      const res = await fetch(`/api/projects/${selectedProjectId}/iso-report`);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `iso-report-${selectedProjectId}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      // silent
    }
    setExporting(false);
  };

  const tabs = [
    { id: 'activities', label: `Activités MRV (${logs.length})`, icon: 'ClipboardDocumentListIcon' },
    { id: 'evidence', label: `Preuves (${evidence.length})`, icon: 'DocumentTextIcon' },
    { id: 'verification', label: `Vérification (${sessions.length})`, icon: 'CheckBadgeIcon' },
  ] as const;

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="px-2.5 py-1 rounded-full text-xs font-700 bg-purple-50 text-purple-700 border border-purple-200">
                Accès Vérificateur — Lecture seule
              </span>
            </div>
            <h1 className="text-2xl font-700 text-foreground">Vue MRV complète</h1>
            <p className="text-sm text-muted-foreground mt-1">ISO 14064-2 — Monitoring, Reporting, Verification</p>
          </div>
          <button
            onClick={handleExport}
            disabled={exporting || !selectedProjectId}
            className="btn-primary flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600 disabled:opacity-50"
          >
            <Icon name="ArrowDownTrayIcon" size={16} />
            {exporting ? 'Export...' : 'Télécharger rapport ISO'}
          </button>
        </div>

        {loading ? (
          <div className="space-y-4">{[1,2,3].map(i => <div key={i} className="h-24 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : projects.length === 0 ? (
          <div className="bg-card border border-border rounded-xl p-12 text-center">
            <Icon name="FolderOpenIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
            <p className="text-muted-foreground">Aucun projet disponible</p>
          </div>
        ) : (
          <>
            {/* Project selector */}
            <div className="bg-card border border-border rounded-xl p-4 mb-6">
              <label className="block text-sm font-600 text-foreground mb-2">Sélectionner un projet</label>
              <select
                className="input w-full max-w-md"
                value={selectedProjectId}
                onChange={e => setSelectedProjectId(e.target.value)}
              >
                {projects.map(p => (
                  <option key={p.id} value={p.id}>{p.name} — {p.status}</option>
                ))}
              </select>
            </div>

            {selectedProject && (
              <>
                {/* Project info */}
                <div className="bg-card border border-border rounded-xl p-5 mb-6">
                  <div className="flex items-start justify-between gap-4">
                    <div>
                      <h2 className="text-lg font-700 text-foreground">{selectedProject.name}</h2>
                      {selectedProject.description && <p className="text-sm text-muted-foreground mt-1">{selectedProject.description}</p>}
                    </div>
                    <span className={`px-2.5 py-1 rounded-full text-xs font-600 border flex-shrink-0 ${
                      selectedProject.status === 'verified' ? 'text-blue-700 bg-blue-50 border-blue-200' :
                      selectedProject.status === 'active'? 'text-green-700 bg-green-50 border-green-200' : 'text-amber-700 bg-amber-50 border-amber-200'
                    }`}>
                      {selectedProject.status === 'verified' ? 'Vérifié' : selectedProject.status === 'active' ? 'Actif' : 'Brouillon'}
                    </span>
                  </div>
                  <div className="grid grid-cols-2 gap-4 mt-4 pt-4 border-t border-border">
                    <div>
                      <p className="text-xs text-muted-foreground mb-1">Baseline</p>
                      <p className="text-sm text-foreground">{selectedProject.baseline_description ?? 'Non défini'}</p>
                    </div>
                    <div>
                      <p className="text-xs text-muted-foreground mb-1">Scénario projet</p>
                      <p className="text-sm text-foreground">{selectedProject.project_scenario_description ?? 'Non défini'}</p>
                    </div>
                  </div>
                </div>

                {/* GHG summary */}
                <div className="grid grid-cols-4 gap-4 mb-6">
                  {[
                    { label: 'Baseline GES', value: `${(totalBaseline / 1000).toFixed(3)} tCO₂e`, color: 'text-red-600' },
                    { label: 'Projet GES', value: `${(totalProject / 1000).toFixed(3)} tCO₂e`, color: 'text-blue-600' },
                    { label: 'Réduction', value: `${(totalReduction / 1000).toFixed(3)} tCO₂e`, color: 'text-green-600' },
                    { label: 'Activités', value: String(logs.length), color: 'text-purple-600' },
                  ].map(kpi => (
                    <div key={kpi.label} className="bg-card border border-border rounded-xl p-4 text-center">
                      <p className={`text-xl font-700 ${kpi.color}`}>{kpi.value}</p>
                      <p className="text-xs text-muted-foreground mt-1">{kpi.label}</p>
                    </div>
                  ))}
                </div>

                {/* Tabs */}
                <div className="flex gap-1 border-b border-border mb-6">
                  {tabs.map(tab => (
                    <button
                      key={tab.id}
                      onClick={() => setActiveTab(tab.id)}
                      className={`flex items-center gap-2 px-4 py-2.5 text-sm font-600 border-b-2 transition-all -mb-px ${
                        activeTab === tab.id ? 'border-primary text-primary' : 'border-transparent text-muted-foreground hover:text-foreground'
                      }`}
                    >
                      <Icon name={tab.icon as Parameters<typeof Icon>[0]['name']} size={14} />
                      {tab.label}
                    </button>
                  ))}
                </div>

                {loadingDetail ? (
                  <div className="space-y-2">{[1,2,3].map(i => <div key={i} className="h-14 bg-muted rounded-xl animate-pulse" />)}</div>
                ) : (
                  <>
                    {activeTab === 'activities' && (
                      <div className="space-y-2">
                        {logs.length === 0 ? (
                          <div className="bg-card border border-border rounded-xl p-10 text-center">
                            <p className="text-muted-foreground text-sm">Aucune activité MRV</p>
                          </div>
                        ) : logs.map(log => (
                          <div key={log.id} className="bg-card border border-border rounded-xl p-4">
                            <div className="flex items-center justify-between gap-4">
                              <div>
                                <p className="font-600 text-foreground text-sm">{log.activity_type}</p>
                                <p className="text-xs text-muted-foreground">{new Date(log.timestamp).toLocaleString('fr-CA')}</p>
                              </div>
                              <div className="flex gap-4 text-right text-xs">
                                <div><p className="text-muted-foreground">Baseline</p><p className="font-700 text-red-600">{log.ghg_emissions_baseline_kgco2e?.toFixed(2)} kg</p></div>
                                <div><p className="text-muted-foreground">Projet</p><p className="font-700 text-blue-600">{log.ghg_emissions_project_kgco2e?.toFixed(2)} kg</p></div>
                                <div><p className="text-muted-foreground">Réduction</p><p className="font-700 text-green-600">{log.ghg_reduction_kgco2e?.toFixed(2)} kg</p></div>
                                <div><p className="text-muted-foreground">Incertitude</p><p className="font-700 text-amber-600">±{log.uncertainty_percent?.toFixed(1)}%</p></div>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}

                    {activeTab === 'evidence' && (
                      <div className="space-y-2">
                        {evidence.length === 0 ? (
                          <div className="bg-card border border-border rounded-xl p-10 text-center">
                            <p className="text-muted-foreground text-sm">Aucune preuve disponible</p>
                          </div>
                        ) : evidence.map(ev => (
                          <div key={ev.id} className="bg-card border border-border rounded-xl p-4 flex items-center gap-4">
                            <div className="w-8 h-8 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
                              <Icon name="DocumentTextIcon" size={16} className="text-muted-foreground" />
                            </div>
                            <div className="flex-1 min-w-0">
                              <p className="font-600 text-foreground text-sm truncate">{ev.file_url ?? 'Sans URL'}</p>
                              <p className="text-xs text-muted-foreground">{ev.type} — {new Date(ev.timestamp).toLocaleString('fr-CA')}</p>
                              {ev.gps && <p className="text-xs text-muted-foreground">GPS: {String(ev.gps.lat)}, {String(ev.gps.lng)}</p>}
                            </div>
                            {ev.file_url && (
                              <a href={ev.file_url} target="_blank" rel="noopener noreferrer" className="btn-ghost p-2 rounded-lg flex-shrink-0">
                                <Icon name="ArrowTopRightOnSquareIcon" size={16} />
                              </a>
                            )}
                          </div>
                        ))}
                      </div>
                    )}

                    {activeTab === 'verification' && (
                      <div className="space-y-3">
                        {sessions.length === 0 ? (
                          <div className="bg-card border border-border rounded-xl p-10 text-center">
                            <p className="text-muted-foreground text-sm">Aucune session de vérification</p>
                          </div>
                        ) : sessions.map(session => (
                          <div key={session.id} className="bg-card border border-border rounded-xl p-5">
                            <div className="flex items-start justify-between gap-4">
                              <div>
                                <p className="font-700 text-foreground">{session.verifier_org ?? 'Organisme non défini'}</p>
                                <p className="text-sm text-muted-foreground">{session.verifier_contact}</p>
                                {session.comments && <p className="text-sm text-muted-foreground mt-1 italic">{session.comments}</p>}
                              </div>
                              <div className="flex items-center gap-2 flex-shrink-0">
                                <span className={`px-2.5 py-1 rounded-full text-xs font-600 border ${
                                  session.status === 'completed' ? 'text-green-700 bg-green-50 border-green-200' :
                                  session.status === 'in_progress'? 'text-blue-700 bg-blue-50 border-blue-200' : 'text-amber-700 bg-amber-50 border-amber-200'
                                }`}>
                                  {session.status === 'completed' ? 'Complété' : session.status === 'in_progress' ? 'En cours' : 'Planifié'}
                                </span>
                                {session.report_url && (
                                  <a href={session.report_url} target="_blank" rel="noopener noreferrer" className="btn-ghost p-2 rounded-lg">
                                    <Icon name="ArrowTopRightOnSquareIcon" size={16} />
                                  </a>
                                )}
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </>
                )}
              </>
            )}
          </>
        )}
      </div>
    </div>
  );
}
