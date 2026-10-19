import { useState } from 'react';
import { Button, Card, CardContent } from '@databricks/appkit-ui/react';
import { ExternalLink } from 'lucide-react';
import { useApi } from '../lib/api';
import { EmptyBlock, ErrorBlock, LoadingBlock, SourceNote } from '../components/common';

interface AppConfig {
  dashboardEmbedUrl: string | null;
  dashboardUrl: string | null;
}

export function DashboardPage() {
  const { data, loading, error } = useApi<AppConfig>('/api/config');
  const [frameLoaded, setFrameLoaded] = useState(false);

  return (
    <div className="space-y-4 w-full max-w-[1400px] mx-auto">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-2xl font-bold">Investigation dashboard</h2>
          <p className="text-sm text-muted-foreground mt-1">
            AI/BI dashboard over the fusion gold tables: who accessed sensitive data, how unusual it was, where it moved, and the incident evidence. Use its
            <strong> Ask Genie</strong> button for follow-up questions.
          </p>
        </div>
        {data?.dashboardUrl && (
          <Button variant="outline" asChild>
            <a href={data.dashboardUrl} target="_blank" rel="noopener noreferrer">
              Open in Databricks <ExternalLink className="h-4 w-4 ml-1" />
            </a>
          </Button>
        )}
      </div>

      {loading && <LoadingBlock rows={6} />}
      {error && <ErrorBlock message={error} title="Dashboard configuration unavailable" />}
      {data && !data.dashboardEmbedUrl && (
        <EmptyBlock title="No dashboard configured" description="Set E2E_DASHBOARD_ID and E2E_WORKSPACE_HOST in app.yaml." />
      )}
      {data?.dashboardEmbedUrl && (
        <Card className="overflow-hidden">
          <CardContent className="p-0 relative">
            {!frameLoaded && (
              <div className="absolute inset-0 p-6"><LoadingBlock rows={10} /></div>
            )}
            <iframe
              title="Authorized access, unauthorized movement dashboard"
              src={data.dashboardEmbedUrl}
              className="w-full h-[min(1600px,calc(100vh-200px))] min-h-[720px] border-0"
              onLoad={() => setFrameLoaded(true)}
            />
          </CardContent>
        </Card>
      )}
      <SourceNote>
        Embedded AI/BI dashboard. It runs with your own credentials, so Unity Catalog permissions apply. If it stays blank, sign in
        to the workspace in this browser or use &ldquo;Open in Databricks&rdquo;.
      </SourceNote>
    </div>
  );
}
