'use client';
import React, { useEffect, useState, useCallback } from 'react';
import { createClient } from '@/lib/supabase/client';
import Icon from '@/components/ui/AppIcon';

interface EmissionFactor {
  id: string;
  category: string;
  source_reference: string | null;
  unit: string;
  value: number;
  uncertainty_percent: number | null;
  valid_from: string | null;
  valid_to: string | null;
  version: string | null;
  created_at: string;
}

const EMPTY_FORM = {
  category: '',
  source_reference: '',
  unit: 'kgCO2e/tkm',
  value: '',
  uncertainty_percent: '5',
  valid_from: '',
  valid_to: '',
  version: '2023.1',
};

interface FactorModalProps {
  factor?: EmissionFactor | null;
  onClose: () => void;
  onSaved: () => void;
}

function FactorModal({ factor, onClose, onSaved }: FactorModalProps) {
  const [form, setForm] = useState(factor ? {
    category: factor.category,
    source_reference: factor.source_reference ?? '',
    unit: factor.unit,
    value: String(factor.value),
    uncertainty_percent: String(factor.uncertainty_percent ?? 5),
    valid_from: factor.valid_from ?? '',
    valid_to: factor.valid_to ?? '',
    version: factor.version ?? '2023.1',
  } : EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!form.category.trim() || !form.unit.trim() || !form.value) {
      setError('Catégorie, unité et valeur sont requis');
      return;
    }
    setSaving(true);
    setError('');
    const supabase = createClient();
    const payload = {
      category: form.category,
      source_reference: form.source_reference || null,
      unit: form.unit,
      value: parseFloat(form.value),
      uncertainty_percent: parseFloat(form.uncertainty_percent) || 5,
      valid_from: form.valid_from || null,
      valid_to: form.valid_to || null,
      version: form.version || null,
    };
    const { error: err } = factor
      ? await supabase.from('emission_factors').update(payload).eq('id', factor.id)
      : await supabase.from('emission_factors').insert(payload);
    setSaving(false);
    if (err) { setError(err.message); return; }
    onSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="bg-card rounded-xl border border-border shadow-2xl w-full max-w-lg">
        <div className="flex items-center justify-between p-5 border-b border-border">
          <h2 className="text-lg font-700 text-foreground">{factor ? 'Modifier' : 'Nouveau'} facteur d&apos;émission</h2>
          <button onClick={onClose} className="btn-ghost p-1.5 rounded-lg"><Icon name="XMarkIcon" size={18} /></button>
        </div>
        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2">
              <label className="block text-sm font-600 text-foreground mb-1">Catégorie *</label>
              <input className="input w-full" value={form.category} onChange={e => setForm(f => ({ ...f, category: e.target.value }))} placeholder="Ex: transport_routier" />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Valeur *</label>
              <input type="number" step="any" className="input w-full" value={form.value} onChange={e => setForm(f => ({ ...f, value: e.target.value }))} placeholder="0.062" />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Unité *</label>
              <input className="input w-full" value={form.unit} onChange={e => setForm(f => ({ ...f, unit: e.target.value }))} placeholder="kgCO2e/tkm" />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Incertitude (%)</label>
              <input type="number" step="any" className="input w-full" value={form.uncertainty_percent} onChange={e => setForm(f => ({ ...f, uncertainty_percent: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Version</label>
              <input className="input w-full" value={form.version} onChange={e => setForm(f => ({ ...f, version: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Valide du</label>
              <input type="date" className="input w-full" value={form.valid_from} onChange={e => setForm(f => ({ ...f, valid_from: e.target.value }))} />
            </div>
            <div>
              <label className="block text-sm font-600 text-foreground mb-1">Valide au</label>
              <input type="date" className="input w-full" value={form.valid_to} onChange={e => setForm(f => ({ ...f, valid_to: e.target.value }))} />
            </div>
            <div className="col-span-2">
              <label className="block text-sm font-600 text-foreground mb-1">Source de référence</label>
              <input className="input w-full" value={form.source_reference} onChange={e => setForm(f => ({ ...f, source_reference: e.target.value }))} placeholder="Ex: ADEME Base Carbone 2023" />
            </div>
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

export default function AdminEmissionFactorsPage() {
  const [factors, setFactors] = useState<EmissionFactor[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showModal, setShowModal] = useState(false);
  const [editFactor, setEditFactor] = useState<EmissionFactor | null>(null);
  const [search, setSearch] = useState('');
  const [deleting, setDeleting] = useState<string | null>(null);

  const fetchFactors = useCallback(async () => {
    setLoading(true);
    const supabase = createClient();
    const { data, error: err } = await supabase.from('emission_factors').select('*').order('category');
    setLoading(false);
    if (err) { setError(err.message); return; }
    setFactors(data ?? []);
  }, []);

  useEffect(() => { fetchFactors(); }, [fetchFactors]);

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer ce facteur d\'émission ?')) return;
    setDeleting(id);
    const supabase = createClient();
    await supabase.from('emission_factors').delete().eq('id', id);
    setDeleting(null);
    fetchFactors();
  };

  const filtered = factors.filter(f =>
    f.category.toLowerCase().includes(search.toLowerCase()) ||
    (f.source_reference ?? '').toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="min-h-screen bg-background">
      <div className="max-w-6xl mx-auto px-4 py-8">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-2xl font-700 text-foreground">Facteurs d&apos;émission</h1>
            <p className="text-sm text-muted-foreground mt-1">Base de données GES — ISO 14064-2 / ADEME</p>
          </div>
          <button onClick={() => { setEditFactor(null); setShowModal(true); }} className="btn-primary flex items-center gap-2 px-4 py-2.5 rounded-lg text-sm font-600">
            <Icon name="PlusCircleIcon" size={16} />
            Nouveau facteur
          </button>
        </div>

        <div className="mb-4">
          <div className="relative">
            <Icon name="MagnifyingGlassIcon" size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground" />
            <input
              className="input w-full pl-9"
              placeholder="Rechercher par catégorie ou source..."
              value={search}
              onChange={e => setSearch(e.target.value)}
            />
          </div>
        </div>

        {loading ? (
          <div className="space-y-2">{[1,2,3,4].map(i => <div key={i} className="h-14 bg-muted rounded-xl animate-pulse" />)}</div>
        ) : error ? (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-red-700 text-sm">{error}</div>
        ) : (
          <div className="bg-card border border-border rounded-xl overflow-hidden">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-muted/50">
                  <th className="text-left px-4 py-3 font-600 text-muted-foreground">Catégorie</th>
                  <th className="text-left px-4 py-3 font-600 text-muted-foreground">Valeur</th>
                  <th className="text-left px-4 py-3 font-600 text-muted-foreground">Unité</th>
                  <th className="text-left px-4 py-3 font-600 text-muted-foreground">Incertitude</th>
                  <th className="text-left px-4 py-3 font-600 text-muted-foreground">Version</th>
                  <th className="text-left px-4 py-3 font-600 text-muted-foreground">Source</th>
                  <th className="px-4 py-3" />
                </tr>
              </thead>
              <tbody>
                {filtered.length === 0 ? (
                  <tr><td colSpan={7} className="text-center py-10 text-muted-foreground">Aucun facteur trouvé</td></tr>
                ) : filtered.map(factor => (
                  <tr key={factor.id} className="border-b border-border last:border-0 hover:bg-muted/30 transition-colors">
                    <td className="px-4 py-3 font-600 text-foreground">{factor.category}</td>
                    <td className="px-4 py-3 font-700 text-primary">{factor.value}</td>
                    <td className="px-4 py-3 text-muted-foreground text-xs">{factor.unit}</td>
                    <td className="px-4 py-3 text-amber-600 text-xs">±{factor.uncertainty_percent ?? 5}%</td>
                    <td className="px-4 py-3 text-muted-foreground text-xs">{factor.version ?? '—'}</td>
                    <td className="px-4 py-3 text-muted-foreground text-xs truncate max-w-[200px]">{factor.source_reference ?? '—'}</td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-1 justify-end">
                        <button onClick={() => { setEditFactor(factor); setShowModal(true); }} className="btn-ghost p-1.5 rounded-lg">
                          <Icon name="PencilSquareIcon" size={14} />
                        </button>
                        <button onClick={() => handleDelete(factor.id)} disabled={deleting === factor.id} className="btn-ghost p-1.5 rounded-lg text-red-500 hover:bg-red-50 disabled:opacity-50">
                          <Icon name="TrashIcon" size={14} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {showModal && (
        <FactorModal
          factor={editFactor}
          onClose={() => { setShowModal(false); setEditFactor(null); }}
          onSaved={fetchFactors}
        />
      )}
    </div>
  );
}
