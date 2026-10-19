import { useCallback, useEffect, useState } from 'react';

// ---- Row shapes returned by server/routes/e2e-routes.ts (Lakebase) -----------
export interface Kpis {
  incidents: number;
  p1: number;
  unauthorized_movements: number;
  approved_movements: number;
  explained_by_exception: number;
  approved_actions: number;
  data_through: string | null;
}

export interface IncidentRow {
  incident_id: string;
  employee_id: string;
  full_name: string;
  department: string;
  role: string;
  incident_date: string;
  priority: string;
  fused_risk: number;
  rules_risk_score: number;
  anomaly_score: number | null;
  chain_stage: string;
  primary_asset: string | null;
  produced_rows: number | null;
  max_ratio_vs_self: number | null;
  max_ratio_vs_peers: number | null;
  exception_ticket: string | null;
  triage_recommendation: string;
  attack_techniques: string[] | null;
  leading_hypothesis: string | null;
  disposition: string;
  approved_actions: number;
}

export interface IncidentFull extends IncidentRow {
  email: string;
  manager_id: string;
  timezone: string;
  max_sensitivity_rank: number | null;
  user_median_daily_rows: number | null;
  peer_median_restricted: number | null;
  first_access_restricted: boolean;
  off_hours_sensitive: boolean;
  unassigned_device: boolean;
  close_period: boolean;
  restricted_workflow_ok: boolean;
  chain_id: string | null;
  statement_id: string | null;
  query_local: string | null;
  client_application: string | null;
  device_hostname: string | null;
  file_name: string | null;
  sha256: string | null;
  size_bytes: number | null;
  upload_app: string | null;
  instance_type: string | null;
  destination: string | null;
  destination_account: string | null;
  dlp_profile: string | null;
  is_unauthorized_destination: boolean;
  unlinked_personal_bytes: number | null;
  compromise_indicators: string[] | null;
  misuse_indicators: string[] | null;
  mitigating_factors: string[] | null;
  top_drivers: string[] | null;
  is_anomaly: boolean | null;
}

export interface TimelineRow {
  step: number;
  local_hhmm: string;
  event_time_local: string;
  source: string;
  observation: string;
  why_it_matters: string;
  evidence_ref: string;
}

export interface ChainRow {
  chain_id: string;
  asset_full_name: string;
  sensitivity: string;
  regulation: string | null;
  query_local: string;
  produced_rows: number;
  read_bytes: number;
  client_application: string;
  device_hostname: string;
  device_assigned_to_user: boolean;
  process_name: string;
  file_path: string;
  file_name: string;
  sha256: string;
  size_bytes: number;
  size_ratio: number;
  seconds_query_to_file: number;
  upload_app: string | null;
  instance_type: string | null;
  destination: string | null;
  destination_account: string | null;
  upload_bytes: number | null;
  dlp_profile: string | null;
  dlp_action: string | null;
  seconds_file_to_upload: number | null;
  chain_stage: string;
}

export interface BaselineRow {
  day: string;
  asset_full_name: string;
  rows_returned: number;
  user_median_daily_rows: number | null;
  peer_median_daily_rows: number;
  ratio_vs_self: number | null;
  ratio_vs_peers: number;
  is_first_access_to_asset: boolean;
  peers_using_asset: number;
  dept_headcount: number;
}

export interface PlaybookAction {
  key: string;
  label: string;
  detail: string;
  system: string;
}

export interface ActionDecision {
  action_key: string;
  decision: string;
  decided_by: string | null;
  decided_at: string;
}

export interface ResponseEvent {
  id: number;
  action: string;
  detail: string | null;
  actor: string | null;
  created_at: string;
}

export interface IncidentDetail {
  incident: IncidentFull;
  assessment: { assessment: string; leading_hypothesis: string; generated_at: string } | null;
  timeline: TimelineRow[];
  chain: ChainRow | null;
  baseline: BaselineRow[];
  review: { incident_id: string; disposition: string; reviewer: string | null; updated_at?: string };
  playbook: PlaybookAction[];
  actions: ActionDecision[];
  events: ResponseEvent[];
}

export async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const res = await fetch(url, { ...init, headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) } });
  const body: unknown = await res.json().catch(() => null);
  if (!res.ok) {
    const msg = body && typeof body === 'object' && 'error' in body ? String(body.error) : res.statusText;
    throw new Error(msg);
  }
  return body as T;
}

/** Minimal fetch hook with loading / error / reload for the Lakebase routes. */
export function useApi<T>(url: string | null) {
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState<boolean>(url !== null);
  const [tick, setTick] = useState(0);

  useEffect(() => {
    if (!url) return;
    let cancelled = false;
    fetchJson<T>(url)
      .then((d) => { if (!cancelled) { setData(d); setError(null); } })
      .catch((e: Error) => { if (!cancelled) setError(e.message); })
      .finally(() => { if (!cancelled) setLoading(false); });
    return () => { cancelled = true; };
  }, [url, tick]);

  const reload = useCallback(() => { setLoading(true); setTick((t) => t + 1); }, []);
  return { data, error, loading, reload };
}

export const fmtInt = (n: number | string | null | undefined) =>
  n === null || n === undefined || n === '' ? '—' : Math.round(Number(n)).toLocaleString('en-US');
export const fmtDate = (s: string | null | undefined) => (s ? String(s).slice(0, 10) : '—');
/** UTC instant -> "YYYY-MM-DD HH:mm UTC" */
export const fmtUtc = (s: string | null | undefined) =>
  s ? new Date(s).toISOString().replace('T', ' ').slice(0, 16) + ' UTC' : '—';
/** Columns named *_local hold the employee's wall-clock time; render without timezone conversion. */
export const fmtLocal = (s: string | null | undefined) => (s ? String(s).replace('T', ' ').slice(0, 16) + ' local' : '—');
export const fmtMb = (bytes: number | null | undefined) => (bytes ? `${(Number(bytes) / 1e6).toFixed(1)} MB` : '—');
export const shortAsset = (a: string | null | undefined) => (a ? a.replace('finance_prod.', '').replace('sales_prod.', '').replace('analytics_prod.', '') : '—');
/** Analytics (warehouse) results serialize numbers/booleans as strings; coerce explicitly. */
export const num = (v: unknown): number => (typeof v === 'number' ? v : Number(v ?? 0));
export const isTrue = (v: unknown): boolean => v === true || v === 'true';
