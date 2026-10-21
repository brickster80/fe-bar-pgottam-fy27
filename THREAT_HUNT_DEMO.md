# Demo script: hunting for insider threats in investment data

**Customer framing:** capital markets / investment management. **Fictional firm:** Harborview Investment Management, a fund and portfolio manager.
**Format:** live threat hunt in Genie ("Authorized Access, Unauthorized Movement (Harborview IM)", `01f1cbe0c38c1d129f67a95d56d9ac69`, or the app's **Ask Genie** tab) · **Runtime:** ~15 min

**Premise:** no alert, no suspect, no name. We start with "who has access to our investment data?" and follow unusual data volume wherever it leads. The person behind the activity first appears in the answer to prompt **7**, when three independent signals point to the same person.

**Conversations:** prompts 1–3 are **Chat A**. Prompts 4–16 are **Chat B**, one continuous conversation, so "that employee", "that device" and "that file" keep their meaning. Every prompt was run against the live space on the Harborview data in this order and grouping.

| Governed asset | Sensitivity | Expected use | UC control |
|---|---|---|---|
| `invest_prod.portfolio.fund_holdings` | confidential | Portfolio and fund reporting | tags |
| `invest_prod.research.unpublished_ratings` | **restricted** (FINRA 2241, Reg FD) | Research publishing workflow (Equity Research); surveillance (Compliance) | tags + masks on the new rating and price target |
| `invest_prod.trading.pending_block_orders` | **highly restricted** (MNPI) | Trading desk only | tags + row filter |

---

## Opening (1 min)
> "Every asset manager's crown jewels are three things: what the funds hold, what research is about to say, and what the desk is about to trade. If research leaks before publication, that's front-running and selective disclosure. So the CCO and the CISO ask: *who has access to this data, and is anyone using it in a way we wouldn't expect?* We have no alert. Let's look."

## Part 1: Who has access, and what does normal look like? (Chat A, 3 min)

**1.** `Who has access to our governed investment data, and who actually used it this quarter? For each asset show the departments entitled, number of employees entitled, employees who used it, queries and rows read.`
- *Look for:*
  - **Holdings:** entitled to and used by all four investment teams.
  - **Unpublished research:** entitled to Equity Research, Compliance and Portfolio Management. **62 of 70** entitled portfolio staff used it (~554,000 rows).
  - **Block orders:** Trading only (12 of 12).
- *Say:* "Entitlement comes from the asset registry; actual use comes from Unity Catalog query history and lineage. Lots of people *can*. The question is who *did*, and how much."

**2.** `Show the weekly rows read from each restricted investment asset over the quarter. Does any week stand out?`
- *Look for:* unpublished research in the **week of Sep 21: ~608,000 rows**, against a normal ~112,000–143,000. Block orders are flat.
- *Say:* "One spike in a whole quarter, on pre-publication research. That's the data that can move a stock."

**3.** `Which department drove that week's volume on that asset, compared with its usual weekly volume?`
- *Look for:* **Portfolio Management, ~484,000 rows vs ~6,000 in a usual week (~80×)**. Equity Research, whose job this is, is near normal.
- *Say:* "It isn't the analysts writing the research. It's the people who trade on it. Let's pull some threads."

## Part 2: Pull the threads (Chat B, 4 min)

**4.** `Unpublished research ratings are meant for the research publishing workflow. How much access happened outside an approved workflow, by department?`
- *Look for:* **only Portfolio Management**: 146 queries by 62 employees, ~554,000 rows. Most of those rows sit in that spike.
- *Say:* "Every one of these reads was *authorized*: Unity Catalog granted them. Authorized isn't the same as expected."

**5.** `Which client tools are used to query restricted investment assets, and how many employees use each one?`
- *Look for:* SQL Editor, Excel and Power BI, each used by 100+ employees, and **DBeaver 24.1: 1 employee, 2 queries**.

**6.** `How many queries against restricted assets ran outside business hours, and how many rows did they return?`
- *Look for:* **2 queries, ~480,000 rows** in the whole quarter.
- *Say:* "Three separate oddities: a volume spike, a tool nobody uses, and two off-hours queries. Same thing?"

**7.** `Do the unusual tool, the off-hours queries and that spike point to the same people? Show who is behind them.`
- *Look for:* **one portfolio analyst tied to all three signals**. Other names appear only in the spike group; remember the Compliance analyst, who comes back in prompt 13.
- *Say:* "This is the first time we've seen a name, and the data gave it to us. We know where to look, not what happened."

## Part 3: Is it unusual for that employee? (Chat B, 3 min)

**8.** `For that employee, how does the volume compare with their own normal daily volume and with their department peers on that asset?`
- *Look for:* **480,025 rows: ~68× their own normal day (~7,000) and ~1,034× the Portfolio Management peer median (~460)**.

**9.** `Was that their first-ever access to unpublished research ratings, and which device were they signed in from?`
- *Look for:* first-ever access: yes. Device **LOANER-NYC-07**, not assigned to them.
- *Note:* Genie may quote the session time as 21:46, which is the query. The sign-in was at **21:40** (prompt 14 shows it).

**10.** `Was the incident sign-in the first time that employee ever used that loaner device? Who is the device assigned to?`
- *Look for:* **yes, first time** (0 earlier sign-ins). It's a managed **pool loaner** with no assigned owner.
- *Say:* "Unusual volume, time, tool and device. All still inside Databricks and Okta. Did anything *leave*?"

## Part 4: Did it move? (Chat B, 3 min)

**11.** `Did the data that employee pulled end up in a file and leave the endpoint? Show the file, the destination and whether it was approved.`
- *Look for:* `research_pipeline_full.csv` written by DBeaver on the loaner, then uploaded to a **personal Dropbox** account (`dropbox-personal:dbid:AAD7Kx2mQ9`). Destination **not approved**.
- *Say:* "Lineage gives us the statement, EDR gives us the file written by the same client process on the same device, and DLP gives us an upload of the *same SHA-256*. Pre-publication ratings and price targets are now outside the firm."

**12.** `Was the personal Dropbox account that received that file used by any other employee?`
- *Look for:* that account appears once, for this one employee only.

**13.** `Is anyone else doing something similar? Show other large restricted extracts and whether an exception ticket explains them.`
- *Look for:* the Compliance analyst from prompt 7: a **52,000-row** extract explained by approved exception **EXC-4471** (Q3 research-publication surveillance review, approved by the Chief Compliance Officer). The other candidates have no exception.
- *Say:* "Big, unusual and on the same table, but approved, done by Compliance, and kept inside the corporate tenant. Business context clears it in seconds."

## Part 5: Evidence and hypotheses (Chat B, 2 min)

**14.** `Show the evidence timeline for that employee's incident in local time.`
- *Look for:* **21:40** loaner sign-in → **21:43** first touch of unpublished research (25 rows) → **21:46** 480,000 rows via DBeaver → **21:49** CSV on the endpoint → **21:53** personal Dropbox upload → **21:55** correlated incident.

**15.** `Is this more consistent with insider misuse or with a compromised account or device, and what evidence would separate the two?`
- *Look for:* **"Undetermined – needs more evidence"** (P1, fused risk 100).
  - *Compromise:* never-seen loaner, unfamiliar tool, off-hours, first-ever access.
  - *Misuse:* a legitimate grant, MFA passed, and a personal account no one else used.
  - *Would separate them:* device forensics, the loaner checkout record, Okta session details, and Dropbox account ownership.
- *Say:* "The job enforces 'don't assume malice': when indicators exist on both sides, the label stays Undetermined whatever the model leans toward."

**16.** `What response should the analyst approve first, and why?`
- *Look for:* containment that preserves evidence first: suspend the session and revoke tokens, isolate the loaner, preserve logs and the Dropbox content, and contact the employee only after that.
- *Hand-off:* in the app's incident page, approve those actions. They're written to Lakebase with your identity, and nothing executes automatically.

## Close (1 min)
> "We started with 'who has access to our investment data?' and never typed a name. A quarter-long trend showed one spike, on pre-publication research. Three independent oddities (volume, tool, time) pointed to one session. Endpoint and DLP evidence showed the file left to a personal account. A Compliance look-alike was cleared by an exception ticket. And the assessment keeps two hypotheses open instead of jumping to blame. Every answer is SQL you can inspect, over Unity Catalog–governed tables, running as you."

---

## Presenter notes
- **Clarifying suggestions:** Genie often ends with "Would you prefer…?". Ignore it and move to the next prompt.
- **Show the code:** open **Show code** on prompts 1, 3, 7 and 11 to prove the joins (entitlement vs usage, the weekly baseline, the three-signal overlap, and the statement → file → hash → upload chain).
- **Keep follow-ups anchored:** if you improvise, say "that employee", "that device" or "that file". Avoid "personal destination", which matches an unrelated DLP-only case.
- **Prompts 10, 12 and 16 wording:** keep them as written. Looser versions gave inconsistent answers in testing:
  - "before that day" sometimes counted the incident sign-in as earlier use of the device;
  - "the cloud account" sometimes checked the corporate SharePoint account instead;
  - "What should the analyst approve first?" is read as "which *incident* first".
- **One question at a time:** in testing, two Genie conversations running at once on this space hit API timeouts. Present from a single chat.
- **Short version (~7 min):** Chat A: 1 → 2 → 3. Chat B: 5 → 6 → 7 → 11 → 14 → 15.
- **Back-up proof outside Genie:** the dashboard's Q2 page (unusual vs self and peers) and Q3 page (chains by stage), and the app's **Sensitive access** tab, where the pre-publication rating shows as masked and block orders are filtered *for you*.
- **All data is synthetic:** Harborview Investment Management and every employee are fictional. The incident was planted in the generator to demonstrate the method; the pipeline finds it with general rules, not by name.
