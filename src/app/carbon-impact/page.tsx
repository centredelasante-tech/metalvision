'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

interface Project {
  id: string;
  name: string;
  status: string;
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

export default function ClientCarbonImpactPage() {
  const [projects, setProjects] = useState<Project[]>([]);
  const [logs, setLogs] = useState<ActivityLog[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedProject, setSelectedProject] = useState<string>('all');
  const [exporting, setExporting] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    setLoading(true);
    const supabase = createClient();
    const [projRes, logsRes] = await Promise.all([
      supabase.from('projects').select('id, name, status, start_date, end_date').order('created_at', { ascending: false }),
      supabase.from('project_activity_logs').select('*').order('timestamp', { ascending: false }).limit(50),
    ]);
    setProjects(projRes.data ?? []);
    setLogs(logsRes.data ?? []);
    setLoading(false);
  }, []);

  useEffect(() => { fetchData(); }, [fetchData]);

  const filteredLogs = selectedProject === 'all'
    ? logs
    : logs.filter(l => {
        // We need project_id on logs — fetch per project
        return true;
      });

  const totalReduction = logs.reduce((s, l) => s + (l.ghg_reduction_kgco2e ?? 0), 0);
  const totalBaseline = logs.reduce((s, l) => s + (l.ghg_emissions_baseline_kgco2e ?? 0), 0);
  const totalProject = logs.reduce((s, l) => s + (l.ghg_emissions_project_kgco2e ?? 0), 0);
  const reductionPct = totalBaseline > 0 ? (totalReduction / totalBaseline) * 100 : 0;

  const handleDownloadReport = async (projectId: string) => {
    setExporting(projectId);
    try {
      const res = await fetch(`/api/projects/${projectId}/iso-report`);
      const blob = await res.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `rapport-iso-${projectId}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch {
      // silent
    }
    setExporting(null);
  };

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-5xl mx-auto px-4 py-8">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-2xl font-700 text-foreground">Impact Carbone</h1>
          <p className="text-sm text-muted-foreground mt-1">Vos réductions GES — Conformité ISO 14064-2</p>
        </div>

        {loading ? (
          <div className="space-y-4">{[1,2,3].map(i => <div key={i} className="h-28 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : (
          <>
            {/* Hero KPIs */}
            <div className="grid grid-cols-2 gap-4 mb-8 lg:grid-cols-4">
              <div className="bg-gradient-to-br from-green-500 to-green-600 rounded-xl p-5 text-white col-span-2 lg:col-span-1">
                <Icon name="ArrowTrendingDownIcon" size={24} className="mb-2 opacity-80" />
                <p className="text-3xl font-700">{(totalReduction / 1000).toFixed(2)}</p>
                <p className="text-sm opacity-80 mt-0.5">tCO₂e évitées</p>
              </div>
              <div className="bg-card border border-border rounded-xl p-5">
                <Icon name="CloudIcon" size={20} className="text-red-500 mb-2" />
                <p className="text-2xl font-700 text-foreground">{(totalBaseline / 1000).toFixed(2)}</p>
                <p className="text-xs text-muted-foreground">tCO₂e baseline</p>
              </div>
              <div className="bg-card border border-border rounded-xl p-5">
                <Icon name="BeakerIcon" size={20} className="text-blue-500 mb-2" />
                <p className="text-2xl font-700 text-foreground">{(totalProject / 1000).toFixed(2)}</p>
                <p className="text-xs text-muted-foreground">tCO₂e projet</p>
              </div>
              <div className="bg-card border border-border rounded-xl p-5">
                <Icon name="ChartBarIcon" size={20} className="text-purple-500 mb-2" />
                <p className="text-2xl font-700 text-foreground">{reductionPct.toFixed(1)}%</p>
                <p className="text-xs text-muted-foreground">Réduction GES</p>
              </div>
            </div>

            {/* Progress bar */}
            <div className="bg-card border border-border rounded-xl p-5 mb-6">
              <div className="flex items-center justify-between mb-2">
                <p className="text-sm font-600 text-foreground">Progression réduction GES</p>
                <p className="text-sm font-700 text-green-600">{reductionPct.toFixed(1)}%</p>
              </div>
              <div className="h-3 bg-muted rounded-full overflow-hidden">
                <div
                  className="h-full bg-gradient-to-r from-green-500 to-green-400 rounded-full transition-all duration-700"
                  style={{ width: `${Math.min(reductionPct, 100)}%` }}
                />
              </div>
              <div className="flex justify-between mt-1 text-xs text-muted-foreground">
                <span>0 tCO₂e</span>
                <span>{(totalBaseline / 1000).toFixed(1)} tCO₂e (baseline)</span>
              </div>
            </div>

            {/* Projects */}
            <h2 className="text-lg font-700 text-foreground mb-4">Mes projets carbone</h2>
            {projects.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-10 text-center mb-6">
                <Icon name="FolderOpenIcon" size={36} className="text-muted-foreground mx-auto mb-2" />
                <p className="text-muted-foreground text-sm">Aucun projet carbone actif</p>
              </div>
            ) : (
              <div className="space-y-3 mb-8">
                {projects.map(project => (
                  <div key={project.id} className="bg-card border border-border rounded-xl p-5 flex items-center justify-between gap-4">
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        <p className="font-700 text-foreground truncate">{project.name}</p>
                        <span className={`px-2 py-0.5 rounded-full text-xs font-600 border ${
                          project.status === 'verified' ? 'text-blue-700 bg-blue-50 border-blue-200' :
                          project.status === 'active'? 'text-green-700 bg-green-50 border-green-200' : 'text-amber-700 bg-amber-50 border-amber-200'
                        }`}>
                          {project.status === 'verified' ? 'Vérifié' : project.status === 'active' ? 'Actif' : 'Brouillon'}
                        </span>
                      </div>
                      {project.start_date && (
                        <p className="text-xs text-muted-foreground">
                          {new Date(project.start_date).toLocaleDateString('fr-CA')}
                          {project.end_date && ` → ${new Date(project.end_date).toLocaleDateString('fr-CA')}`}
                        </p>
                      )}
                    </div>
                    <button
                      onClick={() => handleDownloadReport(project.id)}
                      disabled={exporting === project.id}
                      className="btn-ghost flex items-center gap-2 px-3 py-2 rounded-lg text-sm font-600 disabled:opacity-50 flex-shrink-0"
                    >
                      <Icon name="ArrowDownTrayIcon" size={16} />
                      {exporting === project.id ? 'Export...' : 'Rapport ISO'}
                    </button>
                  </div>
                ))}
              </div>
            )}

            {/* Recent activities */}
            <h2 className="text-lg font-700 text-foreground mb-4">Activités MRV récentes</h2>
            {filteredLogs.length === 0 ? (
              <div className="bg-card border border-border rounded-xl p-10 text-center">
                <Icon name="ClipboardDocumentListIcon" size={36} className="text-muted-foreground mx-auto mb-2" />
                <p className="text-muted-foreground text-sm">Aucune activité enregistrée</p>
              </div>
            ) : (
              <div className="space-y-2">
                {filteredLogs.slice(0, 10).map(log => (
                  <div key={log.id} className="bg-card border border-border rounded-xl p-4 flex items-center justify-between gap-4">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-lg bg-green-50 flex items-center justify-center flex-shrink-0">
                        <Icon name="ArrowTrendingDownIcon" size={16} className="text-green-600" />
                      </div>
                      <div>
                        <p className="text-sm font-600 text-foreground">{log.activity_type}</p>
                        <p className="text-xs text-muted-foreground">{new Date(log.timestamp).toLocaleDateString('fr-CA')}</p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p className="text-sm font-700 text-green-600">-{log.ghg_reduction_kgco2e?.toFixed(1)} kgCO₂e</p>
                      <p className="text-xs text-muted-foreground">±{log.uncertainty_percent?.toFixed(1)}%</p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
