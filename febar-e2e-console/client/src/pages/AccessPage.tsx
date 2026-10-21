import {
  Badge, BarChart, Card, CardContent, CardDescription, CardHeader, CardTitle,
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow, useAnalyticsQuery,
} from '@databricks/appkit-ui/react';
import { sql } from '@databricks/appkit-ui/js';
import { Lock, Radio, ShieldCheck } from 'lucide-react';
import { fmtInt, isTrue, num, shortAsset } from '../lib/api';
import { EmptyBlock, ErrorBlock, LoadingBlock, SourceNote } from '../components/common';

const WINDOW = { start_date: sql.date('2026-09-16') };

function ByAsset() {
  const { data, loading, error } = useAnalyticsQuery('access_by_asset', WINDOW);
  const chart = (data ?? []).map((r) => ({
    who: `${shortAsset(r.asset_full_name)} · ${r.department}`,
    queries: num(r.queries),
    outside_workflow: num(r.outside_workflow_queries),
    off_hours: num(r.off_hours_queries),
  })).slice(0, 12);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Who reads which governed asset — and how much happens outside an approved workflow</CardTitle>
        <CardDescription>Queries on sensitive financial assets by department, since 2026-09-16</CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        {loading && <LoadingBlock rows={6} />}
        {error && <ErrorBlock message={error} />}
        {data && data.length === 0 && <EmptyBlock title="No sensitive access in window" />}
        {data && data.length > 0 && (
          <BarChart data={chart} xKey="who" yKey={['queries', 'outside_workflow', 'off_hours']} orientation="horizontal"
            colorPalette="categorical" height={380} ariaLabel="Sensitive queries by asset and department" />
        )}
        <SourceNote>Source: capmarkets_stg.febar_e2e.silver_sensitive_access (query history ⋈ lineage ⋈ audit ⋈ HR ⋈ IdP)</SourceNote>
      </CardContent>
    </Card>
  );
}

function RestrictedAccessors() {
  const { data, loading, error } = useAnalyticsQuery('restricted_accessors', WINDOW);
  return (
    <Card>
      <CardHeader>
        <CardTitle>Who touched restricted assets</CardTitle>
        <CardDescription>Unpublished research and pending block orders, ranked by volume vs the employee&apos;s own baseline</CardDescription>
      </CardHeader>
      <CardContent>
        {loading && <LoadingBlock rows={8} />}
        {error && <ErrorBlock message={error} />}
        {data && data.length === 0 && <EmptyBlock title="No restricted access in window" />}
        {data && data.length > 0 && (
          <div className="overflow-x-auto">
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Employee</TableHead>
                  <TableHead>Asset</TableHead>
                  <TableHead className="text-right">Rows</TableHead>
                  <TableHead className="text-right">× self</TableHead>
                  <TableHead className="text-right">× peers</TableHead>
                  <TableHead>Context</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.map((r) => (
                  <TableRow key={`${r.employee_id}-${r.asset_full_name}`}>
                    <TableCell><div className="font-medium">{r.full_name}</div><div className="text-xs text-muted-foreground">{r.role} · {r.department}</div></TableCell>
                    <TableCell className="font-mono text-xs">{shortAsset(r.asset_full_name)}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmtInt(r.rows_returned)}</TableCell>
                    <TableCell className={`text-right tabular-nums ${num(r.max_ratio_vs_self) >= 10 ? 'text-destructive font-medium' : ''}`}>{r.max_ratio_vs_self ?? '—'}</TableCell>
                    <TableCell className={`text-right tabular-nums ${num(r.max_ratio_vs_peers) >= 20 ? 'text-destructive font-medium' : ''}`}>{r.max_ratio_vs_peers ?? '—'}</TableCell>
                    <TableCell>
                      <div className="flex flex-wrap gap-1">
                        {isTrue(r.first_access) && <Badge className="bg-warning text-warning-foreground">first access</Badge>}
                        {isTrue(r.unassigned_device) && <Badge className="bg-destructive text-destructive-foreground">unassigned device</Badge>}
                        {num(r.off_hours_queries) > 0 && <Badge variant="secondary">off-hours</Badge>}
                        {r.exception_ticket ? <Badge variant="outline">{r.exception_ticket}</Badge> : isTrue(r.approved_workflow) ? <Badge variant="outline">approved workflow</Badge> : <Badge variant="outline">no workflow</Badge>}
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function GovernedView() {
  const me = useAnalyticsQuery('policy_me', {});
  const research = useAnalyticsQuery('governed_research_sample', {});
  const orders = useAnalyticsQuery('governed_orders_visible', {});
  const p = me.data?.[0];
  const f = orders.data?.[0];
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><Lock className="h-4 w-4" /> The governed assets, as you are allowed to see them</CardTitle>
        <CardDescription>These queries run <strong>on behalf of you</strong>: Unity Catalog masks and row filters apply to your identity.</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {me.error && <ErrorBlock message={me.error} title="Could not read your policy" />}
        {p && (
          <div className="flex flex-wrap items-center gap-2 text-sm">
            <ShieldCheck className="h-4 w-4 text-muted-foreground" />
            <span className="font-mono text-xs">{p.principal}</span>
            <Badge variant={isTrue(p.can_view_unpublished) ? 'default' : 'secondary'}>Unpublished ratings: {isTrue(p.can_view_unpublished) ? 'unmasked' : 'masked'}</Badge>
            <Badge variant="outline">Pending block orders: {isTrue(p.can_view_block_orders) ? 'visible' : 'filtered'}</Badge>
          </div>
        )}
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
          <div className="lg:col-span-2">
            <div className="text-xs font-medium text-muted-foreground mb-2">research_unpublished_ratings · column masks on new_rating, new_price_target</div>
            {research.loading && <LoadingBlock rows={4} />}
            {research.error && <ErrorBlock message={research.error} />}
            {research.data && (
              <Table>
                <TableHeader><TableRow><TableHead>Ticker</TableHead><TableHead>Current</TableHead><TableHead>New rating</TableHead><TableHead className="text-right">New target</TableHead><TableHead>Publish</TableHead><TableHead>Status</TableHead></TableRow></TableHeader>
                <TableBody>
                  {research.data.map((v) => (
                    <TableRow key={v.rating_id}>
                      <TableCell className="font-mono text-sm">{v.ticker}</TableCell>
                      <TableCell className="text-xs">{v.current_rating} · {v.current_price_target}</TableCell>
                      <TableCell className="font-mono text-xs">{v.new_rating}</TableCell>
                      <TableCell className="font-mono text-xs text-right">{v.new_price_target ?? 'masked'}</TableCell>
                      <TableCell className="text-xs">{v.planned_publish_date}</TableCell>
                      <TableCell className="text-xs">{v.status}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </div>
          <div>
            <div className="text-xs font-medium text-muted-foreground mb-2">trading_pending_block_orders · row filter (trading desk only)</div>
            {orders.loading && <LoadingBlock rows={2} />}
            {orders.error && <ErrorBlock message={orders.error} />}
            {f && (
              <div className="rounded-md border p-4">
                <div className="text-3xl font-semibold tabular-nums">{fmtInt(f.visible_rows)}</div>
                <div className="text-xs text-muted-foreground">rows visible to you · {fmtInt(f.visible_funds)} funds</div>
                <p className="text-xs text-muted-foreground mt-2">UC removes rows you aren&apos;t entitled to; the app never sees them.</p>
              </div>
            )}
          </div>
        </div>
        <SourceNote>Policy: capmarkets_stg.febar_e2e.gov_access_policy → mask_unpublished_rating, mask_price_target, filter_block_orders</SourceNote>
      </CardContent>
    </Card>
  );
}

function LiveEvidence() {
  const audit = useAnalyticsQuery('live_audit', {});
  const qe = useAnalyticsQuery('live_query_evidence', {});
  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2"><Radio className="h-4 w-4" /> Live Databricks evidence on the governed stand-ins</CardTitle>
        <CardDescription>
          Real <span className="font-mono">system.access.audit</span>, <span className="font-mono">system.query.history</span> and <span className="font-mono">system.access.table_lineage</span> rows —
          including the reads this page just made. System tables can lag by minutes to hours.
        </CardDescription>
      </CardHeader>
      <CardContent className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div>
          <div className="text-xs font-medium text-muted-foreground mb-2">system.access.audit</div>
          {audit.loading && <LoadingBlock rows={4} />}
          {audit.error && <ErrorBlock message={audit.error} title="Audit log unavailable" />}
          {audit.data && audit.data.length === 0 && <EmptyBlock title="No audit rows yet" description="Recent reads appear after system-table latency." />}
          {audit.data && audit.data.length > 0 && (
            <Table>
              <TableHeader><TableRow><TableHead>Time (UTC)</TableHead><TableHead>Who</TableHead><TableHead>Action</TableHead><TableHead>Table</TableHead></TableRow></TableHeader>
              <TableBody>
                {audit.data.map((r, idx) => (
                  <TableRow key={`${r.event_time}-${r.action_name}-${idx}`}>
                    <TableCell className="text-xs whitespace-nowrap">{r.event_time}</TableCell>
                    <TableCell className="text-xs">{r.user_email}</TableCell>
                    <TableCell className="text-xs">{r.action_name}</TableCell>
                    <TableCell className="font-mono text-xs">{r.governed_table}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
        <div>
          <div className="text-xs font-medium text-muted-foreground mb-2">system.query.history ⋈ system.access.table_lineage</div>
          {qe.loading && <LoadingBlock rows={4} />}
          {qe.error && <ErrorBlock message={qe.error} title="Query history unavailable" />}
          {qe.data && qe.data.length === 0 && <EmptyBlock title="No lineage-linked queries yet" description="Lineage typically lands within a few hours." />}
          {qe.data && qe.data.length > 0 && (
            <Table>
              <TableHeader><TableRow><TableHead>Start (UTC)</TableHead><TableHead>Who</TableHead><TableHead>Client</TableHead><TableHead>Table</TableHead><TableHead className="text-right">Rows</TableHead></TableRow></TableHeader>
              <TableBody>
                {qe.data.map((r) => (
                  <TableRow key={r.statement_id}>
                    <TableCell className="text-xs whitespace-nowrap">{r.start_time}</TableCell>
                    <TableCell className="text-xs">{r.executed_by}</TableCell>
                    <TableCell className="text-xs">{r.client_application}</TableCell>
                    <TableCell className="font-mono text-xs">{r.governed_table}</TableCell>
                    <TableCell className="text-right tabular-nums">{fmtInt(r.produced_rows)}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

export function AccessPage() {
  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold">Sensitive financial data access</h2>
        <p className="text-sm text-muted-foreground mt-1">Question 1 across the company, plus Unity Catalog governance and live system-table evidence.</p>
      </div>
      <RestrictedAccessors />
      <ByAsset />
      <GovernedView />
      <LiveEvidence />
    </div>
  );
}
