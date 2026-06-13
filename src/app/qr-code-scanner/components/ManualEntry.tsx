'use client';
import React, { useState } from 'react';
import { useForm } from 'react-hook-form';
import Icon from '@/components/ui/AppIcon';

interface ManualForm {
  containerId: string;
}

export default function ManualEntry() {
  const [submitted, setSubmitted] = useState(false);
  const {
    register,
    handleSubmit,
    formState: { errors },
    reset,
  } = useForm<ManualForm>();

  const onSubmit = (data: ManualForm) => {
    // BACKEND INTEGRATION: Look up container by ID, redirect to container page
    console.log('Manual entry:', data.containerId);
    setSubmitted(true);
    setTimeout(() => {
      setSubmitted(false);
      reset();
    }, 2000);
  };

  return (
    <div className="bg-card rounded-xl border border-border p-5">
      <div className="flex items-center gap-2 mb-4">
        <Icon name="PencilSquareIcon" size={18} className="text-primary" />
        <h3 className="text-sm font-600 text-foreground">Saisie manuelle</h3>
      </div>
      <p className="text-xs text-muted-foreground mb-4">
        Si le QR code est illisible, entrez l'identifiant du conteneur (ex : CT-003)
      </p>
      <form onSubmit={handleSubmit(onSubmit)} className="flex gap-3">
        <div className="flex-1">
          <input
            {...register('containerId', {
              required: "L'identifiant est requis",
              pattern: {
                value: /^CT-\d{3}$/i,
                message: 'Format attendu : CT-001',
              },
            })}
            placeholder="CT-001"
            className="w-full px-4 py-2.5 rounded-lg border border-border bg-input text-foreground text-sm font-500 focus:outline-none focus:ring-2 focus:ring-ring placeholder:text-muted-foreground"
          />
          {errors.containerId && (
            <p className="text-xs text-red-600 mt-1">{errors.containerId.message}</p>
          )}
        </div>
        <button
          type="submit"
          className={`px-5 py-2.5 rounded-lg text-sm font-600 flex items-center gap-2 transition-all ${
            submitted
              ? 'bg-primary/20 text-primary cursor-default' :'btn-primary'
          }`}
          disabled={submitted}
        >
          {submitted ? (
            <>
              <Icon name="CheckIcon" size={16} className="text-primary" />
              Trouvé
            </>
          ) : (
            <>
              <Icon name="MagnifyingGlassIcon" size={16} className="text-primary-foreground" />
              Rechercher
            </>
          )}
        </button>
      </form>
    </div>
  );
}