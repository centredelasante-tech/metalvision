'use client';
import React, { useState, useEffect, useRef } from 'react';
import { useSearchParams } from 'next/navigation';
import Icon from '@/components/ui/AppIcon';
import { createClient } from '@/lib/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { LotDraft, SelectedContainer } from './NewLotWizard';

interface Props {
  draft: LotDraft;
  updateDraft: (u: Partial<LotDraft>) => void;
  onNext: () => void;
}

export default function StepContainer({ draft, updateDraft, onNext }: Props) {
  const { user } = useAuth();
  const searchParams = useSearchParams();
  const containerId = searchParams.get('container_id');

  const [searchQuery, setSearchQuery] = useState('');
  const [searchResults, setSearchResults] = useState<SelectedContainer[]>([]);
  const [searching, setSearching] = useState(false);
  const [autoLoading, setAutoLoading] = useState(false);
  const [autoError, setAutoError] = useState<string | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const autoLoadedRef = useRef(false);

  // Auto-load container from URL param
  useEffect(() => {
    if (!containerId || autoLoadedRef.current) return;
    autoLoadedRef.current = true;
    setAutoLoading(true);

    const load = async () => {
      try {
        const supabase = createClient();
        const { data, error } = await supabase
          .from('containers')
          .select('id, name, location')
          .eq('id', containerId)
          .single();

        if (error || !data) {
          setAutoError('Conteneur introuvable. Veuillez le rechercher manuellement.');
        } else {
          const container: SelectedContainer = {
            id: data.id,
            name: data.name,
            location: data.location ?? null,
          };
          updateDraft({ container });
          // Auto-advance to step 2
          setTimeout(() => onNext(), 600);
        }
      } catch {
        setAutoError('Erreur lors du chargement du conteneur.');
      } finally {
        setAutoLoading(false);
      }
    };

    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [containerId]);

  // Debounced search
  useEffect(() => {
    if (!searchQuery.trim()) {
      setSearchResults([]);
      return;
    }
    if (debounceRef.current) clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(async () => {
      setSearching(true);
      try {
        const supabase = createClient();
        const q = `%${searchQuery.trim()}%`;
        const { data, error } = await supabase
          .from('containers')
          .select('id, name, location')
          .or(`name.ilike.${q},qr_code.ilike.${q}`)
          .limit(8);

        if (!error && data) {
          setSearchResults(
            data.map((c: { id: string; name: string; location: string | null }) => ({
              id: c.id,
              name: c.name,
              location: c.location ?? null,
            }))
          );
        }
      } catch {
        // ignore
      } finally {
        setSearching(false);
      }
    }, 350);

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [searchQuery]);

  const handleSelect = (container: SelectedContainer) => {
    updateDraft({ container });
    setSearchResults([]);
    setSearchQuery('');
  };

  const handleClear = () => {
    updateDraft({ container: null });
    setSearchQuery('');
    setSearchResults([]);
  };

  // Auto-loading state
  if (autoLoading) {
    return (
      <div className="bg-card rounded-xl border border-border p-10 flex flex-col items-center gap-4">
        <div className="w-12 h-12 border-4 border-muted border-t-primary rounded-full animate-spin" />
        <p className="text-sm text-muted-foreground font-500">Chargement du conteneur…</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="bg-card rounded-xl border border-border p-5">
        <div className="flex items-center gap-2 mb-1">
          <Icon name="ArchiveBoxIcon" size={18} className="text-primary" />
          <h3 className="text-base font-600 text-foreground">Sélectionner un conteneur</h3>
        </div>
        <p className="text-sm text-muted-foreground mb-5">
          Tapez le nom ou le code du conteneur (ex : CT-001) pour le rechercher.
        </p>

        {autoError && (
          <div className="flex items-start gap-2 p-3 bg-red-50 border border-red-200 rounded-lg mb-4">
            <Icon name="ExclamationCircleIcon" size={16} className="text-red-500 flex-shrink-0 mt-0.5" />
            <p className="text-sm text-red-700">{autoError}</p>
          </div>
        )}

        {/* Selected container display */}
        {draft.container ? (
          <div className="flex items-center justify-between p-4 bg-secondary border border-primary/30 rounded-xl">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 bg-primary/10 rounded-lg flex items-center justify-center">
                <Icon name="ArchiveBoxIcon" size={20} className="text-primary" />
              </div>
              <div>
                <p className="text-sm font-700 text-foreground">{draft.container.name}</p>
                {draft.container.location && (
                  <p className="text-xs text-muted-foreground flex items-center gap-1 mt-0.5">
                    <Icon name="MapPinIcon" size={11} />
                    {draft.container.location}
                  </p>
                )}
              </div>
            </div>
            <button
              onClick={handleClear}
              className="p-2 rounded-lg hover:bg-muted transition-colors"
              aria-label="Changer de conteneur"
            >
              <Icon name="XMarkIcon" size={16} className="text-muted-foreground" />
            </button>
          </div>
        ) : (
          <div className="relative">
            <div className="absolute left-3 top-1/2 -translate-y-1/2 pointer-events-none">
              {searching ? (
                <div className="w-4 h-4 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
              ) : (
                <Icon name="MagnifyingGlassIcon" size={16} className="text-muted-foreground" />
              )}
            </div>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Rechercher par nom ou code (ex: CT-001)"
              className="w-full pl-9 pr-4 py-3 rounded-xl border border-border bg-input text-foreground text-sm focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground min-h-[48px]"
              autoComplete="off"
            />

            {/* Search results dropdown */}
            {searchResults.length > 0 && (
              <div className="absolute top-full left-0 right-0 mt-1 bg-card border border-border rounded-xl shadow-lg z-10 overflow-hidden">
                {searchResults.map((c) => (
                  <button
                    key={`result-${c.id}`}
                    onClick={() => handleSelect(c)}
                    className="w-full flex items-center gap-3 px-4 py-3 hover:bg-secondary transition-colors text-left border-b border-border last:border-0"
                  >
                    <div className="w-8 h-8 bg-muted rounded-lg flex items-center justify-center flex-shrink-0">
                      <Icon name="ArchiveBoxIcon" size={16} className="text-muted-foreground" />
                    </div>
                    <div>
                      <p className="text-sm font-600 text-foreground">{c.name}</p>
                      {c.location && (
                        <p className="text-xs text-muted-foreground">{c.location}</p>
                      )}
                    </div>
                    <Icon name="ChevronRightIcon" size={14} className="text-muted-foreground ml-auto" />
                  </button>
                ))}
              </div>
            )}

            {searchQuery.trim().length > 0 && !searching && searchResults.length === 0 && (
              <p className="text-xs text-muted-foreground mt-2 px-1">
                Aucun conteneur trouvé pour « {searchQuery} »
              </p>
            )}
          </div>
        )}
      </div>

      {/* Next button */}
      <button
        onClick={onNext}
        disabled={!draft.container}
        className={`w-full py-4 rounded-xl text-base font-600 flex items-center justify-center gap-2 transition-all min-h-[56px] ${
          draft.container
            ? 'btn-primary' :'bg-muted text-muted-foreground cursor-not-allowed'
        }`}
      >
        Continuer
        <Icon
          name="ArrowRightIcon"
          size={20}
          className={draft.container ? 'text-primary-foreground' : 'text-muted-foreground'}
        />
      </button>
    </div>
  );
}
