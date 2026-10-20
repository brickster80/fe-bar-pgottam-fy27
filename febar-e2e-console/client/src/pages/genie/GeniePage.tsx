import { useEffect, useState } from 'react';
import { Alert, AlertDescription, AlertTitle, Badge, GenieChat } from '@databricks/appkit-ui/react';
import { Info, ShieldCheck, User } from 'lucide-react';

interface WhoAmI {
  email: string | null;
  user: string | null;
}

// Opening of the threat hunt (THREAT_HUNT_DEMO.md): broad first, no names; ask in order, in one conversation from step 4
const TRY = [
  'How is our financial data being used this quarter? For each governed financial asset show the departments using it, number of employees, queries and rows read.',
  'Show the weekly rows read from each restricted financial asset over the quarter. Does any week stand out?',
  "Which department drove that week's volume on that asset, compared with its usual weekly volume?",
  'Which client tools are used to query restricted financial assets, and how many employees use each one?',
  'How many queries against restricted assets ran outside business hours, and how many rows did they return?',
  'Do the unusual tool, the off-hours queries and that spike point to the same people? Show who is behind them.',
];

export function GeniePage() {
  const [me, setMe] = useState<WhoAmI | null>(null);
  useEffect(() => {
    fetch('/api/whoami')
      .then((r) => (r.ok ? r.json() : null))
      .then((d: WhoAmI | null) => setMe(d))
      .catch(() => setMe(null));
  }, []);

  return (
    <div className="space-y-4 w-full max-w-5xl mx-auto">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="text-2xl font-bold">Ask the investigation assistant</h2>
          <p className="text-sm text-muted-foreground mt-1">
            Plain-English questions over the fusion tables: access, baselines, file and upload chains, evidence. Expand any answer to inspect the SQL Genie ran.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant="secondary" className="gap-1"><User className="h-3 w-3" />{me?.email ?? 'Signed in'}</Badge>
          <Badge variant="outline" className="gap-1"><ShieldCheck className="h-3 w-3" />Runs as you (OBO)</Badge>
        </div>
      </div>

      <Alert>
        <Info className="h-4 w-4" />
        <AlertTitle>AI-generated — verify before acting</AlertTitle>
        <AlertDescription>
          Answers come from the Genie space &ldquo;Authorized Access, Unauthorized Movement&rdquo; and run on your behalf, so Unity Catalog permissions,
          masks and row filters apply to <strong>you</strong>. Review the generated SQL and results before using them in an investigation.
        </AlertDescription>
      </Alert>

      <div className="flex flex-wrap gap-2 text-xs">
        <span className="text-muted-foreground">Start the hunt:</span>
        {TRY.map((q, i) => <Badge key={q} variant="outline" className="font-normal text-left whitespace-normal">{i + 1}. {q}</Badge>)}
      </div>

      <div className="h-[min(640px,66vh)] border rounded-lg overflow-hidden bg-card">
        <GenieChat alias="e2e" placeholder="e.g. How is our financial data being used this quarter?" />
      </div>
    </div>
  );
}
