import type { ReactNode } from 'react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Card,
  CardContent,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
} from '@databricks/appkit-ui/react';
import { AlertTriangle, ArrowRight } from 'lucide-react';

const SEVERITY_CLASS: Record<string, string> = {
  critical: 'bg-destructive text-destructive-foreground',
  high: 'bg-warning text-warning-foreground',
  medium: 'bg-secondary text-secondary-foreground',
  low: 'bg-muted text-muted-foreground',
};

export function SeverityBadge({ severity }: { severity: string }) {
  return <Badge className={`${SEVERITY_CLASS[severity] ?? SEVERITY_CLASS.low} uppercase`}>{severity}</Badge>;
}

const PRIORITY_CLASS: Record<string, string> = {
  P1: 'bg-destructive text-destructive-foreground',
  P2: 'bg-warning text-warning-foreground',
  P3: 'bg-secondary text-secondary-foreground',
  P4: 'bg-muted text-muted-foreground',
};

export function PriorityBadge({ priority }: { priority: string }) {
  return <Badge className={PRIORITY_CLASS[priority] ?? PRIORITY_CLASS.P4}>{priority}</Badge>;
}

const STATUS_CLASS: Record<string, string> = {
  open: 'border-border text-muted-foreground',
  investigating: 'border-warning text-foreground',
  escalated: 'border-destructive text-destructive',
  contained: 'border-success text-success',
  closed: 'border-border text-muted-foreground line-through',
};

export function StatusBadge({ status }: { status: string }) {
  return (
    <Badge variant="outline" className={STATUS_CLASS[status] ?? STATUS_CLASS.open}>
      {status}
    </Badge>
  );
}

/** Risk score 0-100 with a proportional bar (honest, zero-based scale). */
export function RiskMeter({ value }: { value: number }) {
  const v = Math.max(0, Math.min(100, Number(value)));
  const tone = v >= 80 ? 'bg-destructive' : v >= 60 ? 'bg-warning' : 'bg-muted-foreground';
  return (
    <div className="flex items-center gap-2 min-w-[120px]">
      <div className="h-2 flex-1 rounded-full bg-muted overflow-hidden" aria-hidden>
        <div className={`h-full ${tone}`} style={{ width: `${v}%` }} />
      </div>
      <span className="tabular-nums text-sm font-medium w-10 text-right">{v.toFixed(0)}</span>
    </div>
  );
}

export function KpiTile({
  label,
  value,
  hint,
  tone = 'default',
}: {
  label: string;
  value: ReactNode;
  hint?: string;
  tone?: 'default' | 'destructive' | 'warning';
}) {
  const valueClass =
    tone === 'destructive' ? 'text-destructive' : tone === 'warning' ? 'text-foreground' : 'text-foreground';
  return (
    <Card className={tone === 'destructive' ? 'border-destructive/50' : tone === 'warning' ? 'border-warning/60' : ''}>
      <CardContent className="pt-5 pb-4">
        <div className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</div>
        <div className={`mt-1 text-3xl font-semibold tabular-nums ${valueClass}`}>{value}</div>
        {hint && <div className="mt-1 text-xs text-muted-foreground">{hint}</div>}
      </CardContent>
    </Card>
  );
}

export function HopPath({ hops, suspicious }: { hops: string[]; suspicious?: boolean }) {
  return (
    <div className="flex flex-wrap items-center gap-1 font-mono text-xs">
      {hops.map((h, i) => (
        <span key={`${h}-${i}`} className="flex items-center gap-1">
          {i > 0 && <ArrowRight className="h-3 w-3 text-muted-foreground" />}
          <span
            className={`rounded px-1.5 py-0.5 border ${
              i === hops.length - 1 && suspicious ? 'border-destructive text-destructive' : 'border-border'
            }`}
          >
            {h}
          </span>
        </span>
      ))}
    </div>
  );
}

export function LoadingBlock({ rows = 4 }: { rows?: number }) {
  return (
    <div className="space-y-2">
      {Array.from({ length: rows }, (_, i) => (
        <Skeleton key={i} className="h-6 w-full" />
      ))}
    </div>
  );
}

export function ErrorBlock({ message, title = 'Could not load data' }: { message: string; title?: string }) {
  return (
    <Alert variant="destructive">
      <AlertTriangle className="h-4 w-4" />
      <AlertTitle>{title}</AlertTitle>
      <AlertDescription className="break-words">{message}</AlertDescription>
    </Alert>
  );
}

export function EmptyBlock({ title, description }: { title: string; description?: string }) {
  return (
    <Empty>
      <EmptyHeader>
        <EmptyTitle>{title}</EmptyTitle>
        {description && <EmptyDescription>{description}</EmptyDescription>}
      </EmptyHeader>
    </Empty>
  );
}

export function SourceNote({ children }: { children: ReactNode }) {
  return <p className="text-xs text-muted-foreground">{children}</p>;
}

export function Chips({ items, mono }: { items: string[] | null | undefined; mono?: boolean }) {
  if (!items || items.length === 0) return <span className="text-muted-foreground">—</span>;
  return (
    <div className="flex flex-wrap gap-1">
      {items.map((x) => (
        <Badge key={x} variant="secondary" className={mono ? 'font-mono text-[11px]' : 'text-[11px]'}>
          {x}
        </Badge>
      ))}
    </div>
  );
}

const STAGE: Record<string, { label: string; cls: string }> = {
  uploaded_unauthorized: { label: 'Moved to unauthorized destination', cls: 'bg-destructive text-destructive-foreground' },
  uploaded_approved: { label: 'Moved to approved destination', cls: 'bg-secondary text-secondary-foreground' },
  materialized_only: { label: 'Saved to local file', cls: 'bg-warning text-warning-foreground' },
  dlp_only_no_sensitive_lineage: { label: 'DLP only - no sensitive lineage', cls: 'bg-muted text-muted-foreground' },
  access_only: { label: 'Access only', cls: 'bg-muted text-muted-foreground' },
};

export function StageBadge({ stage }: { stage: string }) {
  const s = STAGE[stage] ?? { label: stage, cls: 'bg-muted text-muted-foreground' };
  return <Badge className={s.cls}>{s.label}</Badge>;
}

const DISPOSITION_LABEL: Record<string, string> = {
  under_review: 'Under review',
  true_positive_misuse: 'True positive - insider misuse',
  true_positive_compromise: 'True positive - account/device compromise',
  benign_explained: 'Benign / explained',
  needs_more_evidence: 'Needs more evidence',
};
export const dispositionLabel = (d: string) => DISPOSITION_LABEL[d] ?? d;
export const DISPOSITIONS = Object.keys(DISPOSITION_LABEL);
