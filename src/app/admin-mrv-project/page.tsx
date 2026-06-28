'use client';
import React, { useEffect, useState, useCallback, Suspense } from 'react';
import { useSearchParams } from 'next/navigation';
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
  system_boundaries: Record<string, unknown> | null;
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
  comments: string | null;
  created_at: string;
}

function MRVProjectContent() {
  const searchParams = useSearchParams();
  const projectId = searchParams.get('id');

  const [project, setProject] = useState<Project | null>(null);
  const [logs, setLogs] = useState<ActivityLog[]>([]);
  const [evidence, setEvidence] = useState<EvidenceFile[]>([]);
  const [sessions, setSessions] = useState<VerificationSession[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState<'overview' | 'activities' | 'evidence' | 'verification'>('overview');
  const [exporting, setExporting] = useState(false);

  const fetchData = useCallback(async () => {
    if (!projectId) return;
    setLoading(true);
    const supabase = createClient();
    const [projRes, logsRes, evRes, sessRes] = await Promise.all([
      supabase.from('projects').select('*').eq('id', projectId).maybeSingle(),
      supabase.from('project_activity_logs').select('*').eq('project_id', projectId).order('timestamp', { ascending: false }),
      supabase.from('evidence_files').select('*').eq('project_id', projectId).order('timestamp', { ascending: false }),
      supabase.from('verification_sessions').select('*').eq('project_id', projectId).order('created_at', { ascending: false }),
    ]);
    setProject(projRes.data ?? null);
    setLogs(logsRes.data ?? []);
    setEvidence(evRes.data ?? []);
    setSessions(sessRes.data ?? []);
    setLoading(false);
  }, [projectId]);

  useEffect(() => { fetchData(); }, [fetchData]);

  const totalBaseline = logs.reduce((s, l) => s + (l.ghg_emissions_baseline_kgco2e ?? 0), 0);
  const totalProject = logs.reduce((s, l) => s + (l.ghg_emissions_project_kgco2e ?? 0), 0);
  const totalReduction = logs.reduce((s, l) => s + (l.ghg_reduction_kgco2e ?? 0), 0);

  const handleExport = async () => {
    if (!projectId) return;
    setExporting(true);
    try {
      const res = await fetch(`/api/projects/${projectId}/iso-report`);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `iso-report-${projectId}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      // silent
    }
    setExporting(false);
  };

  const updateStatus = async (newStatus: string) => {
    if (!projectId) return;
    const supabase = createClient();
    await supabase.from('projects').update({ status: newStatus }).eq('id', projectId);
    fetchData();
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!project) {
    return (
      <div className="min-h-screen bg-background flex items-center justify-center">
        <div className="text-center">
          <Icon name="ExclamationTriangleIcon" size={40} className="text-muted-foreground mx-auto mb-3" />
          <p className="text-muted-foreground">Projet introuvable</p>
        </div>
      </div>
    );
  }

  const tabs = [
    { id: 'overview', label: 'Vue d\'ensemble', icon: 'ChartBarIcon' },
    { id: 'activities', label: `Activités MRV (${logs.length})`, icon: 'ClipboardDocumentListIcon' },
    { id: 'evidence', label: `Preuves (${evidence.length})`, icon: 'DocumentTextIcon' },
    { id: 'verification', label: 'Vérification', icon: 'CheckBadgeIcon' },
  ] as const;

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        {/* Header */}
        <div className="flex items-start justify-between mb-6 gap-4">
          <div>
            <div className="flex items-center gap-2 text-sm text-muted-foreground mb-1">
              <a href="/admin-carbon-projects" className="hover:text-primary transition-colors">Projets Carbone</a>
              <Icon name="ChevronRightIcon" size={14} />
              <span className="text-foreground font-500">{project.name}</span>
            </div>
            <h1 className="text-2xl font-700 text-foreground">{project.name}</h1>
            {project.description && <p className="text-sm text-muted-foreground mt-1">{project.description}</p>}
          </div>
          <div className="flex items-center gap-2 flex-shrink-0">
            <select
              value={project.status}
              onChange={e => updateStatus(e.target.value)}
              className="input text-sm py-2 pr-8"
            >
              <option value="draft">Brouillon</option>
              <option value="active">Actif</option>
              <option value="verified">Vérifié</option>
            </select>
            <button
              onClick={handleExport}
              disabled={exporting}
              className="btn-primary flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-600 disabled:opacity-50"
            >
              <Icon name="ArrowDownTrayIcon" size={16} />
              {exporting ? 'Export...' : 'Rapport ISO'}
            </button>
          </div>
        </div>

        {/* GHG KPIs */}
        <div className="grid grid-cols-4 gap-4 mb-6">
          {[
            { label: 'Baseline GES', value: `${(totalBaseline / 1000).toFixed(2)} tCO₂e`, icon: 'CloudIcon', color: 'text-red-500' },
            { label: 'Projet GES', value: `${(totalProject / 1000).toFixed(2)} tCO₂e`, icon: 'BeakerIcon', color: 'text-blue-500' },
            { label: 'Réduction', value: `${(totalReduction / 1000).toFixed(2)} tCO₂e`, icon: 'ArrowTrendingDownIcon', color: 'text-green-500' },
            { label: 'Activités', value: logs.length, icon: 'ClipboardDocumentListIcon', color: 'text-purple-500' },
          ].map(kpi => (
            <div key={kpi.label} className="bg-card border border-border rounded-xl p-4">
              <div className={`w-8 h-8 rounded-lg bg-muted flex items-center justify-center mb-2 ${kpi.color}`}>
                <Icon name={kpi.icon as Parameters<typeof Icon>[0]['name']} size={16} />
              </div>
              <p className="text-xl font-700 text-foreground">{kpi.value}</p>
              <p className="text-xs text-muted-foreground">{kpi.label}</p>
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
                activeTab === tab.id
                  ? 'border-primary text-primary' :'border-transparent text-muted-foreground hover:text-foreground'
              }`}
            >
              <Icon name={tab.icon as Parameters<typeof Icon>[0]['name']} size={14} />
              {tab.label}
            </button>
          ))}
        </div>

        {/* Tab content */}
        {activeTab === 'overview' && (
          <div className="grid grid-cols-2 gap-6">
            <div className="bg-card border border-border rounded-xl p-5">
              <h3 className="font-700 text-foreground mb-3 flex items-center gap-2">
                <Icon name="DocumentTextIcon" size={16} className="text-muted-foreground" />
                Baseline
              </h3>
              <p className="text-sm text-muted-foreground">{project.baseline_description ?? 'Non défini'}</p>
            </div>
            <div className="bg-card border border-border rounded-xl p-5">
              <h3 className="font-700 text-foreground mb-3 flex items-center gap-2">
                <Icon name="LightBulbIcon" size={16} className="text-muted-foreground" />
                Scénario Projet
              </h3>
              <p className="text-sm text-muted-foreground">{project.project_scenario_description ?? 'Non défini'}</p>
            </div>
            <div className="bg-card border border-border rounded-xl p-5 col-span-2">
              <h3 className="font-700 text-foreground mb-3 flex items-center gap-2">
                <Icon name="GlobeAltIcon" size={16} className="text-muted-foreground" />
                Frontières du système
              </h3>
              {project.system_boundaries ? (
                <pre className="text-xs text-muted-foreground bg-muted rounded-lg p-3 overflow-auto">
                  {JSON.stringify(project.system_boundaries, null, 2)}
                </pre>
              ) : (
                <p className="text-sm text-muted-foreground">Non définies</p>
              )}
            </div>
          </div>
        )}

        {activeTab === 'activities' && (
          <div className="space-y-3">
            {logs.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-10 text-center">
                <Icon name="ClipboardDocumentListIcon" size={36} className="text-muted-foreground mx-auto mb-2" />
                <p className="text-muted-foreground text-sm">Aucune activité MRV enregistrée</p>
              </div>
            ) : logs.map(log => (
              <div key={log.id} className="bg-card border border-border rounded-xl p-4">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <p className="font-600 text-foreground text-sm">{log.activity_type}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">{new Date(log.timestamp).toLocaleString('fr-CA')}</p>
                  </div>
                  <div className="flex gap-4 text-right text-xs">
                    <div>
                      <p className="text-muted-foreground">Baseline</p>
                      <p className="font-700 text-red-600">{log.ghg_emissions_baseline_kgco2e?.toFixed(1)} kgCO₂e</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Projet</p>
                      <p className="font-700 text-blue-600">{log.ghg_emissions_project_kgco2e?.toFixed(1)} kgCO₂e</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Réduction</p>
                      <p className="font-700 text-green-600">{log.ghg_reduction_kgco2e?.toFixed(1)} kgCO₂e</p>
                    </div>
                    <div>
                      <p className="text-muted-foreground">Incertitude</p>
                      <p className="font-700 text-amber-600">±{log.uncertainty_percent?.toFixed(1)}%</p>
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {activeTab === 'evidence' && (
          <div className="space-y-3">
            {evidence.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-10 text-center">
                <Icon name="DocumentTextIcon" size={36} className="text-muted-foreground mx-auto mb-2" />
                <p className="text-muted-foreground text-sm">Aucune preuve attachée</p>
              </div>
            ) : evidence.map(ev => (
              <div key={ev.id} className="bg-card border border-border rounded-xl p-4 flex items-center gap-4">
                <div className="w-10 h-10 rounded-lg bg-muted flex items-center justify-center flex-shrink-0">
                  <Icon name="DocumentTextIcon" size={18} className="text-muted-foreground" />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="font-600 text-foreground text-sm truncate">{ev.file_url ?? 'Fichier sans URL'}</p>
                  <p className="text-xs text-muted-foreground">{ev.type} — {new Date(ev.timestamp).toLocaleString('fr-CA')}</p>
                  {ev.gps && (
                    <p className="text-xs text-muted-foreground mt-0.5">
                      GPS: {String(ev.gps.lat)}, {String(ev.gps.lng)}
                    </p>
                  )}
                </div>
                {ev.file_url && (
                  <a href={ev.file_url} target="_blank" rel="noopener noreferrer" className="btn-ghost p-2 rounded-lg">
                    <Icon name="ArrowTopRightOnSquareIcon" size={16} />
                  </a>
                )}
              </div>
            ))}
          </div>
        )}

        {activeTab === 'verification' && (
          <div className="space-y-4">
            {sessions.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-10 text-center">
                <Icon name="CheckBadgeIcon" size={36} className="text-muted-foreground mx-auto mb-2" />
                <p className="text-muted-foreground text-sm">Aucune session de vérification</p>
              </div>
            ) : sessions.map(session => (
              <div key={session.id} className="bg-card border border-border rounded-xl p-5">
                <div className="flex items-start justify-between gap-4 mb-3">
                  <div>
                    <p className="font-700 text-foreground">{session.verifier_org ?? 'Organisme non défini'}</p>
                    <p className="text-sm text-muted-foreground">{session.verifier_contact}</p>
                  </div>
                  <span className={`px-2.5 py-1 rounded-full text-xs font-600 border ${
                    session.status === 'completed' ? 'text-green-700 bg-green-50 border-green-200' :
                    session.status === 'in_progress'? 'text-blue-700 bg-blue-50 border-blue-200' : 'text-amber-700 bg-amber-50 border-amber-200'
                  }`}>
                    {session.status === 'completed' ? 'Complété' : session.status === 'in_progress' ? 'En cours' : 'Planifié'}
                  </span>
                </div>
                {session.comments && <p className="text-sm text-muted-foreground">{session.comments}</p>}
                <p className="text-xs text-muted-foreground mt-2">Créé: {new Date(session.created_at).toLocaleDateString('fr-CA')}</p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

export default function AdminMRVProjectPage() {
  return (
    <Suspense fallback={<div className="min-h-screen bg-background flex items-center justify-center"><div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" /></div>}>
      <MRVProjectContent />
    </Suspense>
  );
}
