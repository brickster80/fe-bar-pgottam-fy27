import { useNavigate } from 'react-router';
import {
  Card, CardContent, CardDescription, CardHeader, CardTitle,
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow, useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { ChevronRight } from 'lucide-react';
import { fmtDate, fmtInt, num, shortAsset, useApi, type IncidentRow, type Kpis } from '../lib/api';
import { EmptyBlock, ErrorBlock, KpiTile, LoadingBlock, PriorityBadge, RiskMeter, SourceNote, StageBadge, dispositionLabel } from '../components/common';

function FourQuestions() {
  const { data, loading, error } = useAnalyticsQuery('four_questions', {});
  return (
    <Card>
      <CardHeader>
        <CardTitle>Four questions turn ~40,000 governed queries into one explainable incident</CardTitle>
        <CardDescription>Databricks audit, query history and lineage fused with identity, endpoint and DLP signals</CardDescription>
      </CardHeader>
      <CardContent>
        {loading && <LoadingBlock rows={2} />}
        {error && <ErrorBlock message={error} />}
        {data && data.length === 0 && <EmptyBlock title="No pipeline output yet" />}
        {data && data.length > 0 && (
          <div className="grid grid-cols-2 md:grid-cols-6 gap-3">
            {data.map((s, i) => (
              <div key={s.step} className="flex items-center gap-2">
                <div className={`flex-1 rounded-md border p-3 ${i === data.length - 1 ? 'border-destructive' : ''}`}>
                  <div className={`text-2xl font-semibold tabular-nums ${i === data.length - 1 ? 'text-destructive' : ''}`}>{fmtInt(num(s.cnt))}</div>
                  <div className="text-xs text-muted-foreground mt-1">{s.stage}</div>
                </div>
                {i < data.length - 1 && <ChevronRight className="hidden md:block h-4 w-4 text-muted-foreground shrink-0" />}
              </div>
            ))}
          </div>
        )}
        <div className="mt-3"><SourceNote>Source: capmarkets_stg.febar_e2e silver/gold (Lakeflow pipeline) · SQL warehouse</SourceNote></div>
      </CardContent>
    </Card>
  );
}

export function IncidentsPage() {
  const navigate = useNavigate();
  const { data: k, error: kErr } = useApi<Kpis>('/api/e2e/kpis');
  const { data, loading, error } = useApi<IncidentRow[]>('/api/e2e/incidents?limit=50');

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div className="flex flex-wrap items-end justify-between gap-2">
        <div>
          <h2 className="text-2xl font-bold">Authorized access, unauthorized movement</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Who accessed sensitive financial data, was it unusual, did it leave, and what does the evidence say?
          </p>
        </div>
        <SourceNote>Data through {fmtDate(k?.data_through)}</SourceNote>
      </div>

      {kErr && <ErrorBlock message={kErr} title="KPIs unavailable" />}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <KpiTile label="P1 incidents" value={k ? fmtInt(k.p1) : '…'} hint={k ? `of ${fmtInt(k.incidents)} candidates` : undefined} tone="destructive" />
        <KpiTile label="Moved to unauthorized destination" value={k ? fmtInt(k.unauthorized_movements) : '…'} hint={k ? `${fmtInt(k.approved_movements)} moved to approved corporate tenant` : undefined} tone="destructive" />
        <KpiTile label="Explained by exception ticket" value={k ? fmtInt(k.explained_by_exception) : '…'} hint="Large pulls with an approved business reason" />
        <KpiTile label="Response actions approved" value={k ? fmtInt(k.approved_actions) : '…'} hint="Analyst decisions recorded in Lakebase" tone="warning" />
      </div>

      <FourQuestions />

      <Card>
        <CardHeader>
          <CardTitle>Incident queue</CardTitle>
          <CardDescription>Fused risk = 60% evidence rules + 40% ML anomaly. Click an incident to investigate.</CardDescription>
        </CardHeader>
        <CardContent>
          {loading && <LoadingBlock rows={8} />}
          {error && <ErrorBlock message={error} />}
          {data && data.length === 0 && <EmptyBlock title="No incidents" description="Run the febar-e2e job to correlate signals." />}
          {data && data.length > 0 && (
            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Employee</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Priority</TableHead>
                    <TableHead>Fused risk</TableHead>
                    <TableHead>Governed asset</TableHead>
                    <TableHead className="text-right">vs self / peers</TableHead>
                    <TableHead>Did it move?</TableHead>
                    <TableHead>Leading hypothesis (GenAI)</TableHead>
                    <TableHead>Review</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.map((r) => (
                    <TableRow key={r.incident_id} className="cursor-pointer" onClick={() => void navigate(`/incident/${r.incident_id}`)}>
                      <TableCell>
                        <div className="font-medium">{r.full_name}</div>
                        <div className="text-xs text-muted-foreground">{r.role} · {r.department}</div>
                      </TableCell>
                      <TableCell className="text-xs whitespace-nowrap">{fmtDate(r.incident_date)}</TableCell>
                      <TableCell><PriorityBadge priority={r.priority} /></TableCell>
                      <TableCell><RiskMeter value={r.fused_risk} /></TableCell>
                      <TableCell className="font-mono text-xs">{shortAsset(r.primary_asset)}</TableCell>
                      <TableCell className="text-right tabular-nums text-xs">
                        {r.max_ratio_vs_self !== null ? `${r.max_ratio_vs_self}×` : '—'} / {r.max_ratio_vs_peers !== null ? `${r.max_ratio_vs_peers}×` : '—'}
                      </TableCell>
                      <TableCell>
                        <StageBadge stage={r.chain_stage} />
                        {r.exception_ticket && <div className="text-xs text-muted-foreground mt-1">covered by {r.exception_ticket}</div>}
                      </TableCell>
                      <TableCell className="text-sm">{r.leading_hypothesis ?? <span className="text-muted-foreground">—</span>}</TableCell>
                      <TableCell className="text-xs">
                        {dispositionLabel(r.disposition)}
                        {r.approved_actions > 0 && <div className="text-muted-foreground">{r.approved_actions} actions approved</div>}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
          <div className="mt-3"><SourceNote>Source: Lakebase e2e.incidents + e2e.assessments, review state from e2e_response</SourceNote></div>
        </CardContent>
      </Card>
    </div>
  );
}
