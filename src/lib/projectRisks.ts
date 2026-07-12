// Shared risk calculation — used by both /projets/:id (S05) and /cockpit (S09).
// Any change to risk definitions must be made here only.

export interface RiskItem {
  label: string;
  severity: 'high' | 'medium' | 'low';
  icon: string;
}

interface LogisticsStepLike {
  status: string;
}

interface ProjectLike {
  target_end_date: string | null;
  phase: string;
}

interface ParticipantLike {
  status: string;
}

export function computeProjectRisks(
  logisticsSteps: LogisticsStepLike[],
  project: ProjectLike | null,
  participants: ParticipantLike[],
): RiskItem[] {
  const items: RiskItem[] = [];

  // Blocked logistics steps
  const blockedSteps = logisticsSteps.filter((s) => s.status === 'blocked');
  if (blockedSteps.length > 0) {
    items.push({
      label: `${blockedSteps.length} étape${blockedSteps.length > 1 ? 's' : ''} logistique${blockedSteps.length > 1 ? 's' : ''} bloquée${blockedSteps.length > 1 ? 's' : ''}`,
      severity: 'high',
      icon: 'ExclamationTriangleIcon',
    });
  }

  // Overdue project (target_end_date passed, phase not closed)
  if (project?.target_end_date && project.phase !== 'closed') {
    const targetDate = new Date(project.target_end_date);
    const now = new Date();
    if (targetDate < now) {
      items.push({
        label: `Date cible dépassée (${targetDate.toLocaleDateString('fr-CA')}) — phase non clôturée`,
        severity: 'high',
        icon: 'ClockIcon',
      });
    }
  }

  // Declined participants
  const declinedParticipants = participants.filter((p) => p.status === 'declined');
  if (declinedParticipants.length > 0) {
    items.push({
      label: `${declinedParticipants.length} invitation${declinedParticipants.length > 1 ? 's' : ''} refusée${declinedParticipants.length > 1 ? 's' : ''}`,
      severity: 'medium',
      icon: 'UserMinusIcon',
    });
  }

  return items;
}
