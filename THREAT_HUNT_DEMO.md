# Demo script: hunting for suspicious access to financial data

**Format:** live threat hunt in Genie ("Authorized Access, Unauthorized Movement", `01f1cbe0c38c1d129f67a95d56d9ac69`, or the app's **Ask Genie** tab) · **Runtime:** ~15 min
**Premise:** no alert, no suspect, no name. We start with a broad question about how financial data is used and follow whatever looks odd. The person behind the activity first appears in answer **8**, when three independent signals converge on them.

**Conversations:** prompts 1–3 are **Chat A**. Prompts 4–16 are **Chat B**, one continuous conversation, so "that employee", "that device" and "that file" keep their meaning. Every prompt was run against the live space in this order and grouping.

---

## Opening (1 min)
> "Here's a question every CFO and CISO has asked: *how is our financial data actually being used?* Not 'show me the alerts'. Just: what's normal, and is anything off? We have Unity Catalog's audit trail, query history and lineage, plus our identity, endpoint and DLP feeds. Let's poke around."

## Part 1: What does normal look like? (Chat A, 3 min)

**1.** `How is our financial data being used this quarter? For each governed financial asset show the departments using it, number of employees, queries and rows read.`
- *Look for:* the monthly summary is used broadly (Finance, Accounting, Treasury, Corp Dev); the acquisition forecast only by Corporate Development; vendor bank accounts mostly by Treasury, but also by Finance and Accounting.
- *Say:* "This is the baseline. Who uses what is business context, and it's what makes 'unusual' measurable."

**2.** `Show the weekly rows read from each restricted financial asset over the quarter. Does any week stand out?`
- *Look for:* vendor bank accounts in the **week of Sep 21: ~608,000 rows**, against a normal range of ~72,000–143,000. The acquisition forecast is flat.
- *Say:* "One spike in a whole quarter, on the vendor *banking* table. Worth a look."

**3.** `Which department drove that week's volume on that asset, compared with its usual weekly volume?`
- *Look for:* **Finance, ~484,000 rows vs ~40,000 usual (~12×)**. Treasury, whose job this is, is at ~1.1×.
- *Say:* "The spike isn't Treasury doing treasury work. It's Finance. Let's pull some threads."

## Part 2: Pull the threads (Chat B, 4 min)

**4.** `Vendor bank accounts are meant for approved treasury workflows. How much access happened outside an approved workflow, by department?`
- *Look for:* **only Finance**: 146 queries by 62 employees, ~554,000 rows. Most of those rows sit in that spike.
- *Say:* "Every one of these reads was *authorized*: UC granted them. 'Authorized' isn't the same as 'expected'."

**5.** `Which client tools are used to query restricted financial assets, and how many employees use each one?`
- *Look for:* SQL Editor, Excel and Power BI, each used by 100+ employees, and **DBeaver 24.1: 1 employee, 2 queries**.

**6.** `How many queries against restricted assets ran outside business hours, and how many rows did they return?`
- *Look for:* **2 queries, ~480,000 rows** in the whole quarter.
- *Say:* "Three separate oddities: a volume spike, a tool nobody uses, and two off-hours queries. Are they the same thing?"

**7.** `Do the unusual tool, the off-hours queries and that spike point to the same people? Show who is behind them.`
- *Look for:* **one employee, a Finance analyst, tied to all three signals**. The two DBeaver queries ran at 21:43 and 21:46 local on Sep 24. A second employee appears in the spike group only. Remember that name; we come back to it at prompt 13.
- *Say:* "This is the first time we've seen a name, and the data gave it to us. We still don't know *what happened*. We only know where to look."

## Part 3: Is it unusual for that employee? (Chat B, 3 min)

**8.** `For that employee, how does the volume compare with their own normal daily volume and with their department peers on that asset?`
- *Look for:* **~480,000 rows: ~68× their own normal day and ~1,034× the Finance peer median**, and it's their first access to the asset.

**9.** `Was that their first-ever access to vendor bank accounts, and which device were they signed in from?`
- *Look for:* first-ever access: yes. Device **LOANER-NYC-07**, not assigned to them.
- *Note:* Genie may quote the session time as 21:46, which is the query. The sign-in was at **21:40** (prompt 14 shows it).

**10.** `Was the incident sign-in the first time that employee ever used that loaner device? Who is the device assigned to?`
- *Look for:* **yes, first time** (0 earlier sign-ins on that device). It's a managed **pool loaner** with no assigned owner.
- *Say:* "Unusual volume, unusual time, unusual tool, unfamiliar device. Still all inside Databricks and Okta. Did anything *leave*?"

## Part 4: Did it move? (Chat B, 3 min)

**11.** `Did the data that employee pulled end up in a file and leave the endpoint? Show the file, the destination and whether it was approved.`
- *Look for:* `vendor_master_full.csv` written by DBeaver on the loaner, then uploaded to a **personal Dropbox** account (`dropbox-personal:dbid:AAD7Kx2mQ9`). Destination **not approved**.
- *Say:* "The query → file → upload chain uses three systems. Lineage gives us the statement, EDR gives us the file written by the same client process on the same device, and DLP gives us an upload of the *same SHA-256*."

**12.** `Was the personal Dropbox account that received that file used by any other employee?`
- *Look for:* that account appears only once, for this one employee.

**13.** `Is anyone else doing something similar? Show other large restricted extracts and whether an exception ticket explains them.`
- *Look for:* the other spike-group name from prompt 7: a **52,000-row** extract explained by approved exception **EXC-4471** (Q3 vendor master audit, approved by the Controller). The other candidates have no exception.
- *Say:* "Big and unusual, but approved and kept in the corporate tenant. Business context clears it in seconds."

## Part 5: Evidence and hypotheses (Chat B, 2 min)

**14.** `Show the evidence timeline for that employee's incident in local time.`
- *Look for:* **21:40** loaner sign-in → **21:43** first touch (25 rows) → **21:46** 480,000 rows → **21:49** CSV on the endpoint → **21:53** personal Dropbox upload → **21:55** correlated incident.

**15.** `Is this more consistent with insider misuse or with a compromised account or device, and what evidence would separate the two?`
- *Look for:* **"Undetermined – needs more evidence"**.
  - *Compromise:* never-seen device, unfamiliar tool, off-hours, first-ever access.
  - *Misuse:* a legitimate grant, MFA passed, and a personal account used by no one else.
  - *Would separate them:* device forensics, the loaner checkout record, Okta session details and Dropbox account ownership.
- *Say:* "We went looking for 'who', and the honest answer is 'whose session'. We don't accuse anyone. We preserve, contain and investigate."

**16.** `What response should the analyst approve first, and why?`
- *Look for:* containment that preserves evidence first: preserve logs, revoke sessions and tokens, isolate the loaner, request preservation of the Dropbox content, and contact the employee only after that.
- *Hand-off:* switch to the app's incident page and approve those actions. They're written to Lakebase with your identity, and nothing executes automatically.

## Close (1 min)
> "We started with 'how is our financial data used?' and never typed a name. A quarter-long trend showed one spike. Three independent oddities (volume, tool, time) pointed to one session. Endpoint and DLP evidence showed the file left to a personal account. A look-alike was cleared by an exception ticket. And the assessment keeps two hypotheses open instead of jumping to blame. Every answer is SQL you can inspect, over Unity Catalog–governed tables, running as you."

---

## Presenter notes
- **Clarifying suggestions:** Genie often ends with "Would you prefer…?". Ignore it and move to the next prompt.
- **Show the code:** open **Show code** on prompts 3, 7 and 11 to prove the joins (weekly baseline, the three-signal overlap, and the statement → file → hash → upload chain).
- **Keep follow-ups anchored:** if you improvise, say "that employee", "that device" or "that file". Avoid "personal destination", which matches an unrelated DLP-only case.
- **Prompts 10, 12 and 16 wording:** keep them as written. Looser versions gave inconsistent answers in testing: "before that day" sometimes counted the incident sign-in as earlier use of the device, "the cloud account" sometimes checked the corporate SharePoint account instead, and "What should the analyst approve first?" is read as "which *incident* first".
- **Short version (~7 min):** Chat A: 2 → 3. Chat B: 5 → 6 → 7 → 11 → 14 → 15.
- **Back-up proof outside Genie:** the dashboard's Q2 page (unusual vs self and peers) and Q3 page (chains by stage) show the same numbers.
- **All data is synthetic:** Halcyon Financial and every employee are fictional. The incident was planted in the generator to demonstrate the method; the pipeline finds it with general rules, not by name.
