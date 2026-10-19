// Investigation console API over Lakebase Postgres.
//
// Reads (operational serving): synced schema `e2e` (from capmarkets_stg.febar_e2e gold tables) -
//   incidents, assessments, incident_timeline, exfil_chains, access_anomalies.
// Writes (analyst review -> approved response): app-owned schema `e2e_response`, created by the
// app's service principal on startup - reviews, actions, events (append-only audit trail).

import { z } from 'zod';
import { Application, Request } from 'express';

interface AppKitWithLakebase {
  lakebase: {
    query(text: string, params?: unknown[]): Promise<{ rows: Record<string, unknown>[] }>;
  };
  server: {
    extend(fn: (app: Application) => void): void;
  };
}

/** Response playbook offered for analyst approval. Nothing executes automatically. */
export const RESPONSE_ACTIONS = [
  { key: 'preserve_evidence', label: 'Preserve evidence', detail: 'Legal hold on Databricks audit, query history, lineage, IdP, EDR and DLP records for this incident', system: 'Databricks / SIEM' },
  { key: 'revoke_sessions', label: 'Revoke sessions and tokens', detail: 'Terminate IdP sessions and revoke Databricks personal access tokens for the account', system: 'Okta / Databricks' },
  { key: 'isolate_device', label: 'Isolate device', detail: 'Network-contain the device via EDR while preserving memory and disk', system: 'CrowdStrike' },
  { key: 'block_destination', label: 'Block destination', detail: 'Block uploads to the personal cloud instance and request takedown of the uploaded file', system: 'Netskope' },
  { key: 'reset_credentials', label: 'Reset credentials', detail: 'Force password reset and MFA re-enrollment before access is restored', system: 'Okta' },
  { key: 'notify_insider_risk', label: 'Engage insider-risk process', detail: 'Notify manager, HR and Legal; schedule employee interview after containment', system: 'Case management' },
] as const;

const ACTION_KEYS = RESPONSE_ACTIONS.map((a) => a.key) as [string, ...string[]];
const DISPOSITIONS = ['under_review', 'true_positive_misuse', 'true_positive_compromise', 'benign_explained', 'needs_more_evidence'] as const;

const SETUP_SQL = [
  `CREATE SCHEMA IF NOT EXISTS e2e_response`,
  `CREATE TABLE IF NOT EXISTS e2e_response.reviews (
     incident_id TEXT PRIMARY KEY,
     disposition TEXT NOT NULL DEFAULT 'under_review',
     reviewer    TEXT,
     updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
   )`,
  `CREATE TABLE IF NOT EXISTS e2e_response.actions (
     incident_id TEXT NOT NULL,
     action_key  TEXT NOT NULL,
     decision    TEXT NOT NULL,
     decided_by  TEXT,
     decided_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
     PRIMARY KEY (incident_id, action_key)
   )`,
  `CREATE TABLE IF NOT EXISTS e2e_response.events (
     id          BIGSERIAL PRIMARY KEY,
     incident_id TEXT NOT NULL,
     action      TEXT NOT NULL,
     detail      TEXT,
     actor       TEXT,
     created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
   )`,
  `CREATE INDEX IF NOT EXISTS events_incident_idx ON e2e_response.events (incident_id, created_at DESC)`,
];

const ReviewBody = z.object({ disposition: z.enum(DISPOSITIONS) });
const DecisionBody = z.object({ decision: z.enum(['approved', 'rejected', 'pending']) });
const NoteBody = z.object({ note: z.string().min(1).max(2000) });
const INCIDENT_ID = /^INC-\d{8}-E-\d{4}$/;

function actor(req: Request): string {
  return req.header('x-forwarded-email') ?? req.header('x-forwarded-user') ?? 'local-developer';
}

function queryInt(value: unknown, fallback: number, max: number): number {
  const n = typeof value === 'string' ? parseInt(value, 10) : NaN;
  return Number.isFinite(n) && n > 0 ? Math.min(n, max) : fallback;
}

export async function setupE2eRoutes(appkit: AppKitWithLakebase) {
  try {
    for (const stmt of SETUP_SQL) await appkit.lakebase.query(stmt);
    console.log('[e2e] response schema ready');
  } catch (err) {
    console.warn('[e2e] response schema setup failed:', (err as Error).message);
  }

  const logEvent = (incidentId: string, action: string, detail: string, who: string) =>
    appkit.lakebase.query(
      `INSERT INTO e2e_response.events (incident_id, action, detail, actor) VALUES ($1, $2, $3, $4)`,
      [incidentId, action, detail, who],
    );

  appkit.server.extend((app) => {
    app.get('/api/whoami', (req, res) => {
      res.json({ email: req.header('x-forwarded-email') ?? null, user: req.header('x-forwarded-user') ?? null });
    });

    app.get('/api/config', (_req, res) => {
      const id = process.env.E2E_DASHBOARD_ID ?? '';
      const host = (process.env.E2E_WORKSPACE_HOST ?? '').replace(/\/$/, '');
      const ws = process.env.E2E_WORKSPACE_ID ?? '';
      res.json({
        dashboardEmbedUrl: id && host ? `${host}/embed/dashboardsv3/${id}?o=${ws}` : null,
        dashboardUrl: id && host ? `${host}/dashboardsv3/${id}/published?o=${ws}` : null,
      });
    });

    // ---- KPI strip ---------------------------------------------------------
    app.get('/api/e2e/kpis', async (_req, res) => {
      try {
        const { rows } = await appkit.lakebase.query(`
          SELECT
            (SELECT COUNT(*) FROM e2e.incidents)::int                                                   AS incidents,
            (SELECT COUNT(*) FROM e2e.incidents WHERE priority = 'P1')::int                             AS p1,
            (SELECT COUNT(*) FROM e2e.exfil_chains WHERE chain_stage = 'uploaded_unauthorized')::int    AS unauthorized_movements,
            (SELECT COUNT(*) FROM e2e.exfil_chains WHERE chain_stage = 'uploaded_approved')::int        AS approved_movements,
            (SELECT COUNT(*) FROM e2e.incidents WHERE exception_ticket IS NOT NULL)::int                AS explained_by_exception,
            (SELECT COUNT(*) FROM e2e_response.actions WHERE decision = 'approved')::int                AS approved_actions,
            (SELECT MAX(incident_date) FROM e2e.incidents)                                              AS data_through
        `);
        res.json(rows[0]);
      } catch (err) {
        res.status(500).json({ error: (err as Error).message });
      }
    });

    // ---- Incident queue ----------------------------------------------------
    app.get('/api/e2e/incidents', async (req, res) => {
      try {
        const limit = queryInt(req.query.limit, 50, 200);
        const { rows } = await appkit.lakebase.query(
          `SELECT i.incident_id, i.employee_id, i.full_name, i.department, i.role, i.incident_date, i.priority,
                  i.fused_risk, i.rules_risk_score, i.anomaly_score, i.chain_stage, i.primary_asset, i.produced_rows,
                  i.max_ratio_vs_self, i.max_ratio_vs_peers, i.exception_ticket, i.triage_recommendation,
                  i.attack_techniques, a.leading_hypothesis,
                  COALESCE(r.disposition, 'under_review') AS disposition,
                  (SELECT COUNT(*) FROM e2e_response.actions x WHERE x.incident_id = i.incident_id AND x.decision = 'approved')::int AS approved_actions
           FROM e2e.incidents i
           LEFT JOIN e2e.assessments a ON a.incident_id = i.incident_id
           LEFT JOIN e2e_response.reviews r ON r.incident_id = i.incident_id
           ORDER BY i.fused_risk DESC, i.incident_date DESC
           LIMIT $1`,
          [limit],
        );
        res.json(rows);
      } catch (err) {
        res.status(500).json({ error: (err as Error).message });
      }
    });

    // ---- Investigation: the four questions ----------------------------------
    app.get('/api/e2e/incident/:id', async (req, res) => {
      const id = req.params.id;
      if (!INCIDENT_ID.test(id)) {
        res.status(400).json({ error: 'invalid incident id' });
        return;
      }
      try {
        const inc = await appkit.lakebase.query(`SELECT * FROM e2e.incidents WHERE incident_id = $1`, [id]);
        if (inc.rows.length === 0) {
          res.status(404).json({ error: 'incident not found' });
          return;
        }
        const i = inc.rows[0];
        const [assessment, timeline, chain, baseline, review, actions, events] = await Promise.all([
          appkit.lakebase.query(`SELECT assessment, leading_hypothesis, generated_at FROM e2e.assessments WHERE incident_id = $1`, [id]),
          appkit.lakebase.query(
            `SELECT step, local_hhmm, event_time_local, source, observation, why_it_matters, evidence_ref
             FROM e2e.incident_timeline WHERE incident_id = $1 ORDER BY step`, [id]),
          appkit.lakebase.query(`SELECT * FROM e2e.exfil_chains WHERE chain_id = $1`, [i.chain_id ?? '']),
          appkit.lakebase.query(
            `SELECT to_char(access_date, 'MM-DD') AS day, asset_full_name, rows_returned, user_median_daily_rows,
                    peer_median_daily_rows, ratio_vs_self, ratio_vs_peers, is_first_access_to_asset, peers_using_asset, dept_headcount
             FROM e2e.access_anomalies
             WHERE employee_id = $1 AND sensitivity_rank >= 2 AND access_date BETWEEN ($2::date - 30) AND $2::date
             ORDER BY access_date, asset_full_name`, [i.employee_id, i.incident_date]),
          appkit.lakebase.query(`SELECT * FROM e2e_response.reviews WHERE incident_id = $1`, [id]),
          appkit.lakebase.query(`SELECT action_key, decision, decided_by, decided_at FROM e2e_response.actions WHERE incident_id = $1`, [id]),
          appkit.lakebase.query(
            `SELECT id, action, detail, actor, created_at FROM e2e_response.events WHERE incident_id = $1 ORDER BY created_at DESC LIMIT 50`, [id]),
        ]);
        res.json({
          incident: i,
          assessment: assessment.rows[0] ?? null,
          timeline: timeline.rows,
          chain: chain.rows[0] ?? null,
          baseline: baseline.rows,
          review: review.rows[0] ?? { incident_id: id, disposition: 'under_review', reviewer: null },
          playbook: RESPONSE_ACTIONS,
          actions: actions.rows,
          events: events.rows,
        });
      } catch (err) {
        res.status(500).json({ error: (err as Error).message });
      }
    });

    // ---- Analyst review -> approved response --------------------------------
    app.put('/api/e2e/incident/:id/review', async (req, res) => {
      const id = req.params.id;
      const parsed = ReviewBody.safeParse(req.body);
      if (!INCIDENT_ID.test(id) || !parsed.success) {
        res.status(400).json({ error: 'invalid review' });
        return;
      }
      try {
        const who = actor(req);
        const { rows } = await appkit.lakebase.query(
          `INSERT INTO e2e_response.reviews (incident_id, disposition, reviewer, updated_at) VALUES ($1, $2, $3, NOW())
           ON CONFLICT (incident_id) DO UPDATE SET disposition = $2, reviewer = $3, updated_at = NOW() RETURNING *`,
          [id, parsed.data.disposition, who],
        );
        await logEvent(id, 'disposition', parsed.data.disposition, who);
        res.json(rows[0]);
      } catch (err) {
        res.status(500).json({ error: (err as Error).message });
      }
    });

    app.put('/api/e2e/incident/:id/actions/:key', async (req, res) => {
      const { id, key } = req.params;
      const parsed = DecisionBody.safeParse(req.body);
      if (!INCIDENT_ID.test(id) || !ACTION_KEYS.includes(key) || !parsed.success) {
        res.status(400).json({ error: 'invalid action decision' });
        return;
      }
      try {
        const who = actor(req);
        const { rows } = await appkit.lakebase.query(
          `INSERT INTO e2e_response.actions (incident_id, action_key, decision, decided_by, decided_at) VALUES ($1, $2, $3, $4, NOW())
           ON CONFLICT (incident_id, action_key) DO UPDATE SET decision = $3, decided_by = $4, decided_at = NOW() RETURNING *`,
          [id, key, parsed.data.decision, who],
        );
        await logEvent(id, `action:${key}`, parsed.data.decision, who);
        res.json(rows[0]);
      } catch (err) {
        res.status(500).json({ error: (err as Error).message });
      }
    });

    app.post('/api/e2e/incident/:id/notes', async (req, res) => {
      const id = req.params.id;
      const parsed = NoteBody.safeParse(req.body);
      if (!INCIDENT_ID.test(id) || !parsed.success) {
        res.status(400).json({ error: 'note is required' });
        return;
      }
      try {
        await logEvent(id, 'note', parsed.data.note.trim(), actor(req));
        res.status(201).json({ ok: true });
      } catch (err) {
        res.status(500).json({ error: (err as Error).message });
      }
    });
  });
}
