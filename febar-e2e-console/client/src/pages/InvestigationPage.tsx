import { useState } from 'react';
import { Link, useParams } from 'react-router';
import {
  Badge, BarChart, Button, Card, CardContent, CardDescription, CardHeader, CardTitle,
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow, Textarea,
} from '@databricks/appkit-ui/react';
import { ArrowDown, ArrowLeft, CheckCircle2, CircleSlash, FileText, Fingerprint, Sparkles, UploadCloud, Database } from 'lucide-react';
import {
  fetchJson, fmtDate, fmtInt, fmtLocal, fmtMb, fmtUtc, shortAsset, useApi,
  type ActionDecision, type IncidentDetail, type PlaybookAction,
} from '../lib/api';
import {
  EmptyBlock, ErrorBlock, LoadingBlock, PriorityBadge, RiskMeter, SourceNote, StageBadge, DISPOSITIONS, dispositionLabel,
} from '../components/common';

/** Renders the LLM assessment: **bold** sections + bullet lines, no HTML injection. */
function AssessmentText({ text }: { text: string }) {
  const lines = text.split('\n').filter((l) => l.trim() !== '' && !/^-{3,}$/.test(l.trim()));
  return (
    <div className="space-y-1.5 text-sm leading-relaxed">
      {lines.map((line, i) => {
        const clean = line.replace(/^#+\s*/, '');
        const isBullet = /^\s*([-*•]|\d+\.)\s/.test(clean);
        const parts = clean.replace(/^\s*[-*•]\s/, '• ').split(/\*\*(.+?)\*\*/g);
        return (
          <p key={`${i}-${clean.slice(0, 12)}`} className={isBullet ? 'pl-4' : ''}>
            {parts.map((p, j) => (j % 2 === 1 ? <strong key={`b${j}`}>{p}</strong> : <span key={`s${j}`}>{p.replace(/`/g, '')}</span>))}
          </p>
        );
      })}
    </div>
  );
}

function QuestionCard({ n, title, answer, children }: { n: number; title: string; answer: string; children: React.ReactNode }) {
  return (
    <Card>
      <CardHeader>
        <div className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Question {n}</div>
        <CardTitle>{title}</CardTitle>
        <CardDescription className="text-foreground">{answer}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">{children}</CardContent>
    </Card>
  );
}

function IndicatorList({ title, items, tone }: { title: string; items: string[] | null; tone: 'destructive' | 'warning' | 'muted' }) {
  const border = tone === 'destructive' ? 'border-destructive/60' : tone === 'warning' ? 'border-warning' : 'border-border';
  return (
    <div className={`rounded-md border ${border} p-3`}>
      <div className="text-sm font-semibold mb-2">{title}</div>
      {!items || items.length === 0 ? <p className="text-xs text-muted-foreground">None observed</p> : (
        <ul className="space-y-1 text-sm">{items.map((x) => <li key={x}>• {x}</li>)}</ul>
      )}
    </div>
  );
}

function ResponsePanel({ id, playbook, actions, disposition, onSaved }: {
  id: string; playbook: PlaybookAction[]; actions: ActionDecision[]; disposition: string; onSaved: () => void;
}) {
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [note, setNote] = useState('');
  const decided = new Map(actions.map((a) => [a.action_key, a]));

  const call = async (key: string, url: string, method: string, body: unknown) => {
    setBusy(key);
    setErr(null);
    try {
      await fetchJson(url, { method, body: JSON.stringify(body) });
      onSaved();
    } catch (e) {
      setErr((e as Error).message);
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="space-y-4">
      <div className="space-y-1">
        <label className="text-xs text-muted-foreground" htmlFor="disposition">Analyst disposition</label>
        <Select value={disposition} onValueChange={(v) => void call('disposition', `/api/e2e/incident/${id}/review`, 'PUT', { disposition: v })}>
          <SelectTrigger id="disposition"><SelectValue /></SelectTrigger>
          <SelectContent>{DISPOSITIONS.map((d) => <SelectItem key={d} value={d}>{dispositionLabel(d)}</SelectItem>)}</SelectContent>
        </Select>
      </div>
      <div className="space-y-2">
        {playbook.map((a) => {
          const d = decided.get(a.key);
          return (
            <div key={a.key} className={`rounded-md border p-3 ${d?.decision === 'approved' ? 'border-success' : ''}`}>
              <div className="flex items-start justify-between gap-2">
                <div>
                  <div className="text-sm font-medium">{a.label} <span className="text-xs text-muted-foreground">· {a.system}</span></div>
                  <div className="text-xs text-muted-foreground">{a.detail}</div>
                  {d && d.decision !== 'pending' && (
                    <div className="text-xs mt-1">
                      {d.decision === 'approved' ? <span className="text-success">Approved</span> : <span className="text-muted-foreground">Rejected</span>} by {d.decided_by} · {fmtUtc(d.decided_at)}
                    </div>
                  )}
                </div>
                <div className="flex gap-1 shrink-0">
                  <Button size="sm" variant={d?.decision === 'approved' ? 'default' : 'outline'} disabled={busy !== null}
                    onClick={() => void call(a.key, `/api/e2e/incident/${id}/actions/${a.key}`, 'PUT', { decision: 'approved' })}>
                    <CheckCircle2 className="h-4 w-4" /><span className="sr-only">Approve</span>
                  </Button>
                  <Button size="sm" variant={d?.decision === 'rejected' ? 'default' : 'outline'} disabled={busy !== null}
                    onClick={() => void call(a.key, `/api/e2e/incident/${id}/actions/${a.key}`, 'PUT', { decision: 'rejected' })}>
                    <CircleSlash className="h-4 w-4" /><span className="sr-only">Reject</span>
                  </Button>
                </div>
              </div>
            </div>
          );
        })}
      </div>
      <Textarea value={note} rows={3} placeholder="Investigation note (e.g. called manager, device recovered from loaner pool)…" onChange={(e) => setNote(e.target.value)} />
      <Button disabled={busy !== null || !note.trim()} onClick={() => void call('note', `/api/e2e/incident/${id}/notes`, 'POST', { note }).then(() => setNote(''))}>
        Add note
      </Button>
      {err && <ErrorBlock message={err} title="Save failed" />}
      <p className="text-xs text-muted-foreground">Approvals are recorded in Lakebase (e2e_response) with your identity. Execution is handed to SOAR; nothing runs automatically.</p>
    </div>
  );
}

export function InvestigationPage() {
  const { id = '' } = useParams();
  const { data, loading, error, reload } = useApi<IncidentDetail>(`/api/e2e/incident/${id}`);

  if (loading && !data) return <div className="max-w-7xl mx-auto"><LoadingBlock rows={12} /></div>;
  if (error) return <div className="max-w-7xl mx-auto space-y-4"><Link to="/" className="text-sm text-primary">← Back</Link><ErrorBlock message={error} /></div>;
  if (!data) return null;
  const i = data.incident;
  const c = data.chain;
  const primary = data.baseline.filter((b) => b.asset_full_name === i.primary_asset);
  const incidentDay = primary.length > 0 ? primary[primary.length - 1] : null;
  const dailyTotals = Object.values(
    data.baseline.reduce<Record<string, { day: string; rows: number }>>((acc, b) => {
      acc[b.day] = { day: b.day, rows: (acc[b.day]?.rows ?? 0) + Number(b.rows_returned) };
      return acc;
    }, {}),
  );
  const compareData = incidentDay ? [
    { measure: 'This day', rows: Number(incidentDay.rows_returned) },
    { measure: 'Employee median day', rows: Number(i.user_median_daily_rows ?? 0) },
    { measure: 'Peer median day (asset)', rows: Number(incidentDay.peer_median_daily_rows) },
  ] : [];

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <Link to="/" className="inline-flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"><ArrowLeft className="h-4 w-4" /> Incident queue</Link>

      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2 flex-wrap">
            <h2 className="text-2xl font-bold">{i.full_name}</h2>
            <PriorityBadge priority={i.priority} />
            <StageBadge stage={i.chain_stage} />
          </div>
          <p className="text-sm text-muted-foreground mt-1">
            {i.incident_id} · {i.role} · {i.department} · {fmtDate(i.incident_date)} ({i.timezone}) · review: {dispositionLabel(data.review.disposition)}
          </p>
        </div>
        <div className="w-64">
          <div className="text-xs text-muted-foreground mb-1">Fused risk (rules {i.rules_risk_score} · ML {i.anomaly_score !== null ? Number(i.anomaly_score).toFixed(2) : '—'})</div>
          <RiskMeter value={i.fused_risk} />
          <div className="text-xs text-muted-foreground mt-1">{(i.attack_techniques ?? []).join(' · ')}</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <QuestionCard n={1} title="Who accessed sensitive financial data?"
            answer={`${i.full_name} (${i.role}, ${i.department}) read ${shortAsset(i.primary_asset)}${i.produced_rows ? ` — ${fmtInt(i.produced_rows)} rows` : ''}${i.client_application ? ` via ${i.client_application}` : ''}.`}>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <div><div className="text-xs text-muted-foreground">Governed asset</div><div className="font-mono text-xs">{i.primary_asset ?? '—'}</div></div>
              <div><div className="text-xs text-muted-foreground">Sensitivity</div><div>{c?.sensitivity ?? (i.max_sensitivity_rank ?? '—')}</div></div>
              <div><div className="text-xs text-muted-foreground">Entitlement</div><div>Legitimate read grant{i.restricted_workflow_ok ? ' + approved workflow' : ', outside approved workflow'}</div></div>
              <div><div className="text-xs text-muted-foreground">Exception ticket</div><div>{i.exception_ticket ?? 'None'}</div></div>
              <div><div className="text-xs text-muted-foreground">Query (local)</div><div>{fmtLocal(i.query_local)}</div></div>
              <div><div className="text-xs text-muted-foreground">Device</div><div className={i.unassigned_device ? 'text-destructive font-medium' : ''}>{i.device_hostname ?? '—'}{i.unassigned_device ? ' (never assigned to employee)' : ''}</div></div>
              <div><div className="text-xs text-muted-foreground">Statement</div><div className="font-mono text-xs break-all">{i.statement_id ?? '—'}</div></div>
              <div><div className="text-xs text-muted-foreground">Regulation</div><div>{c?.regulation ?? '—'}</div></div>
            </div>
            <SourceNote>Evidence: system.access.audit (identity, source IP) · system.query.history (statement, rows, client) · system.access.table_lineage (statement → governed table)</SourceNote>
          </QuestionCard>

          <QuestionCard n={2} title="Was the access unusual for that employee and their peers?"
            answer={incidentDay
              ? `${fmtInt(incidentDay.rows_returned)} rows vs ~${fmtInt(i.user_median_daily_rows)} on a normal day (${i.max_ratio_vs_self ?? '—'}× self) and ${i.max_ratio_vs_peers ?? '—'}× the ${i.department} peer median for this asset${i.first_access_restricted ? '; first-ever access to this restricted asset' : ''}.`
              : 'No baseline for this asset.'}>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <div className="text-xs font-medium text-muted-foreground mb-1">Rows returned: incident day vs baselines</div>
                {compareData.length > 0
                  ? <BarChart data={compareData} xKey="measure" yKey="rows" height={220} colorPalette="categorical" ariaLabel="Incident rows versus self and peer baselines" />
                  : <EmptyBlock title="No comparison available" />}
              </div>
              <div>
                <div className="text-xs font-medium text-muted-foreground mb-1">Daily rows on governed financial assets, last 30 days</div>
                {dailyTotals.length > 0
                  ? <BarChart data={dailyTotals} xKey="day" yKey="rows" height={220} colorPalette="sequential" ariaLabel="Employee daily rows on governed financial assets" />
                  : <EmptyBlock title="No history" />}
              </div>
            </div>
            <div className="flex flex-wrap gap-2 text-xs items-center">
              <span className="text-muted-foreground">ML (Isolation Forest) drivers vs peers:</span>
              {(i.top_drivers ?? []).length === 0 ? <span className="text-muted-foreground">none</span> : (i.top_drivers ?? []).map((d) => <Badge key={d} variant="secondary">{d}</Badge>)}
              {incidentDay && <span className="text-muted-foreground">· {incidentDay.peers_using_asset} of {incidentDay.dept_headcount} {i.department} peers ever used this asset</span>}
            </div>
          </QuestionCard>

          <QuestionCard n={3} title="Did the data move to an unauthorized destination?"
            answer={!c ? (i.unlinked_personal_bytes ? `A ${fmtMb(i.unlinked_personal_bytes)} personal upload occurred, but it has no lineage to any governed financial asset.` : 'No file or upload linked to the query.')
              : c.chain_stage === 'uploaded_unauthorized' ? `Yes — ${c.file_name} (same SHA-256) was uploaded to ${c.upload_app} ${c.instance_type} account ${c.destination_account}.`
              : c.chain_stage === 'uploaded_approved' ? `It moved, but to the approved corporate tenant (${c.destination}).` : 'The result was saved locally; no upload observed.'}>
            {c ? (
              <div className="grid grid-cols-1 md:grid-cols-[1fr_auto_1fr_auto_1fr] items-stretch gap-2 text-sm">
                <div className="rounded-md border p-3">
                  <div className="flex items-center gap-1 font-medium"><Database className="h-4 w-4" /> Query</div>
                  <div className="text-xs mt-1">{fmtLocal(c.query_local)}</div>
                  <div className="text-xs">{fmtInt(c.produced_rows)} rows · {fmtMb(c.read_bytes)}</div>
                  <div className="text-xs text-muted-foreground">{c.client_application} on {c.device_hostname}</div>
                </div>
                <ArrowDown className="h-4 w-4 self-center md:-rotate-90 text-muted-foreground mx-auto" />
                <div className="rounded-md border p-3">
                  <div className="flex items-center gap-1 font-medium"><FileText className="h-4 w-4" /> File (EDR)</div>
                  <div className="text-xs mt-1 font-mono break-all">{c.file_name}</div>
                  <div className="text-xs">{c.process_name} · {fmtMb(c.size_bytes)} (size ratio {c.size_ratio})</div>
                  <div className="text-xs text-muted-foreground">+{Math.round(c.seconds_query_to_file / 60)} min after query</div>
                </div>
                <ArrowDown className="h-4 w-4 self-center md:-rotate-90 text-muted-foreground mx-auto" />
                <div className={`rounded-md border p-3 ${c.chain_stage === 'uploaded_unauthorized' ? 'border-destructive' : ''}`}>
                  <div className="flex items-center gap-1 font-medium"><UploadCloud className="h-4 w-4" /> Destination (DLP)</div>
                  {c.upload_app ? (
                    <>
                      <div className="text-xs mt-1">{c.upload_app} · <span className={c.instance_type === 'personal' ? 'text-destructive font-medium' : ''}>{c.instance_type}</span></div>
                      <div className="text-xs font-mono break-all">{c.destination_account}</div>
                      <div className="text-xs text-muted-foreground">{c.dlp_profile ?? 'no DLP profile'} · {c.dlp_action} · +{Math.round((c.seconds_file_to_upload ?? 0) / 60)} min</div>
                    </>
                  ) : <div className="text-xs text-muted-foreground mt-1">No upload observed</div>}
                </div>
              </div>
            ) : <EmptyBlock title="No access → file → destination chain" />}
            {c && <div className="flex items-center gap-1 text-xs text-muted-foreground"><Fingerprint className="h-3 w-3" /> SHA-256 {c.sha256.slice(0, 16)}… matches across EDR and DLP</div>}
          </QuestionCard>

          <QuestionCard n={4} title="What evidence supports the threat assessment?"
            answer={data.assessment ? `Leading hypothesis: ${data.assessment.leading_hypothesis}.` : 'No GenAI assessment for this incident (low priority).'}>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-16">Local</TableHead>
                  <TableHead>Source</TableHead>
                  <TableHead>Observation</TableHead>
                  <TableHead>Why it matters</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.timeline.map((t) => (
                  <TableRow key={t.step}>
                    <TableCell className="tabular-nums font-medium">{t.local_hhmm}</TableCell>
                    <TableCell className="text-xs">{t.source}</TableCell>
                    <TableCell className="text-xs">{t.observation}</TableCell>
                    <TableCell className="text-xs text-muted-foreground">{t.why_it_matters}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
            <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
              <IndicatorList title="H2 · Account or device compromise" items={i.compromise_indicators} tone="destructive" />
              <IndicatorList title="H1 · Insider misuse of legitimate access" items={i.misuse_indicators} tone="warning" />
              <IndicatorList title="Mitigating context" items={i.mitigating_factors} tone="muted" />
            </div>
          </QuestionCard>
        </div>

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2"><Sparkles className="h-4 w-4" /> Threat assessment</CardTitle>
              <CardDescription>{data.assessment ? `Leading hypothesis: ${data.assessment.leading_hypothesis}` : 'Not generated'}</CardDescription>
            </CardHeader>
            <CardContent className="space-y-3">
              {data.assessment ? <AssessmentText text={data.assessment.assessment} /> : <EmptyBlock title="No assessment" description="Only P1/P2, exception-covered and DLP-only incidents are assessed." />}
              <p className="text-xs text-muted-foreground border-t pt-2">
                AI-generated with ai_query (Claude Sonnet) from the evidence on this page. It weighs both hypotheses and does not assume intent — verify before acting.
                {data.assessment && <> Generated {fmtUtc(data.assessment.generated_at)}.</>}
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Analyst review → approved response</CardTitle>
              <CardDescription>Approve or reject each proportionate action. Decisions are written to Lakebase.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <ResponsePanel id={i.incident_id} playbook={data.playbook} actions={data.actions} disposition={data.review.disposition} onSaved={reload} />
              <div className="space-y-2 max-h-64 overflow-y-auto">
                {data.events.length === 0 && <p className="text-xs text-muted-foreground">No review activity yet.</p>}
                {data.events.map((e) => (
                  <div key={e.id} className="text-xs border-l-2 pl-2">
                    <div className="text-muted-foreground">{fmtUtc(e.created_at)} · {e.actor}</div>
                    <div>{e.action === 'note' ? e.detail : `${e.action}: ${e.detail}`}</div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
      <SourceNote>Source: Lakebase e2e.incidents, e2e.incident_timeline, e2e.exfil_chains, e2e.access_anomalies, e2e.assessments (synced from capmarkets_stg.febar_e2e)</SourceNote>
    </div>
  );
}
