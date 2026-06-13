import AppLayout from '@/components/AppLayout';
import ContainerDetailContent from './components/ContainerDetailContent';

export default function ContainerDetailPage() {
  return (
    <AppLayout activeRoute="/container-detail" userRole="admin">
      <ContainerDetailContent />
    </AppLayout>
  );
}