import AppLayout from '@/components/AppLayout';
import LotManagementContent from './components/LotManagementContent';

export default function LotManagementPage() {
  return (
    <AppLayout activeRoute="/lot-management" userRole="admin">
      <LotManagementContent />
    </AppLayout>
  );
}