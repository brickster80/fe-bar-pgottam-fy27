# Genie investigation storyline: "Is anyone moving our financial data?"

**Use it in:** the Genie space "Authorized Access, Unauthorized Movement" (`01f1cbe0c38c1d129f67a95d56d9ac69`) or the app's **Ask Genie** tab · **Runtime:** ~12 min

**The rule of this storyline:** nobody is named in advance. The analyst starts with a business question, not an alert or a suspect. Each answer narrows the field, and the data, not the presenter, surfaces who to look at. After that, every prompt says "that employee", "the incident device" or "that file", never a name.

**Conversations:** start a **new chat for each act**, except Acts 5 and 6, which run as one continuous conversation so the follow-ups keep their context. Every prompt below was run against the live space in this grouping and order.

---

## Opening (30 s)
> "Our CFO asks a simple question: *is anyone moving our financial data somewhere it shouldn't go?* We have no alert and no suspect, just the governed data, the Databricks audit trail, and our identity, endpoint and DLP feeds. Let's ask."

## Act 1: Scope the problem (new chat)
**1.** `Which governed financial assets do we have, how sensitive is each one, and what is its expected use?`
- *Shows:* the three `finance_prod` assets. Monthly summary is confidential (routine reporting), vendor bank accounts are restricted (approved treasury workflows), the acquisition forecast is highly restricted (corporate development only). Two non-finance assets also appear.
- *Say:* "Expected use comes from the asset registry. That's the business context that will tell us later what's normal."

**2.** `Give me the quarter at a glance: how many sensitive-data queries were there, how many employees touched restricted assets, how many files were created from sensitive queries, and how many of those were uploaded to an unapproved destination?`
- *Shows:* **21,012** sensitive queries · **134** employees on restricted assets · ~**1,583** files created · **1** upload to an unapproved destination.
- *Say:* "Twenty-one thousand queries and one file that left. That's the needle. Now let's find it the way an analyst would, not by jumping to the answer."

## Act 2 (Q1): Who accessed sensitive financial data? (new chat)
**3.** `Who accessed restricted financial data in the last two weeks? Show employee, department, role, asset, number of queries and total rows.`
- *Shows:* mostly Treasury analysts with ~20+ queries each (their job). Two non-Treasury employees sit at the top by **rows**, one from Finance and one from Accounting.
- *Say:* "Everyone here had a legitimate grant. UC allowed every read. Access alone isn't the question. *Unusual* access is."

## Act 3 (Q2): Was it unusual for the employee and their peers? (new chat)
**4.** `Which restricted-data accesses were most unusual compared with the employee's own baseline and their department peers? Rank by the larger of the two ratios.`
- *Shows:* one access stands far apart, **~1,034× department peers and ~68× the employee's own baseline** (480,000 rows). The runner-up is ~104× peers.
- *Say:* "Note the top row. From here on we follow the evidence, and we don't assume anything about the person."

**5.** *(follow-up)* `Of those, which were a first-ever access to the asset, happened outside business hours, or came from a device not assigned to the employee?`
- *Shows:* the top access is the only one that is all three: a **first-ever** access, **off-hours**, from a device **not assigned** to the employee. Other rows are low-volume first accesses.
- *Say:* "Unusual volume, unusual time, unusual device. That's still not proof that anything left the building."

## Act 4 (Q3): Did the data move to an unauthorized destination? (new chat)
**6.** `Did any sensitive data move off an endpoint? Summarise the query-to-file-to-upload chains by stage, then show any that went to an unapproved destination.`
- *Shows:* **796** materialized only, **793** uploaded to the corporate SharePoint (approved), and **1 chain uploaded to a personal Dropbox account**: 480,000 rows of vendor bank accounts. The name on that chain matches the top row of Act 3.
- *Say:* "The chain links the query to a file created by the same client process on the same device, and that file to an upload with the same SHA-256. Three systems, one story."

**7.** *(follow-up)* `Were there uploads to personal cloud storage that do not trace back to any governed financial data?`
- *Shows:* one engineer's ~420 MB personal Dropbox upload with **no lineage to governed data**, rated P3.
- *Say:* "A DLP-only tool would have put this at the top of the queue. Without lineage it's a policy conversation, not a financial-data incident."

**8.** *(follow-up)* `Which large extracts are explained by an approved exception ticket?`
- *Shows:* the Act 3 runner-up: a 52,000-row extract under **EXC-4471** ("Q3 vendor master audit", approved by the Controller), uploaded to corporate SharePoint, rated P4.
- *Say:* "Big and unusual, but approved and kept inside the tenant. Business context clears it, so we don't waste analyst time."

## Act 5 (Q4): What evidence supports the threat assessment? (new chat; keep it open for Act 6)
**9.** `Rank the candidate incidents by priority and fused risk, with the chain stage for each.`
- *Shows:* 17 candidates. Exactly **one P1** (fused risk 100, `uploaded_unauthorized`), then a P2 that was `materialized_only` and several P3s.

**10.** `For the highest-priority incident, show the evidence timeline in local time.`
- *Shows:* **21:40** sign-in from a loaner laptop → **21:43** first touch of vendor bank accounts (25 rows) → **21:46** 480,000 rows via DBeaver → **21:49** EDR: `vendor_master_full.csv` (86.4 MB) → **21:53** DLP: same file to a personal Dropbox → **21:55** correlated incident.
- *Say:* "Fifteen minutes and four systems. Each step alone was a weak signal; together it's one explainable incident."

## Act 6: Misuse or compromise? (same chat as Act 5)
> "The tempting conclusion is 'the employee did it.' We don't know that. Let's test both hypotheses."

**11.** `For the highest-priority incident, before the incident had that employee ever signed in from the incident device? Which devices do they normally use?`
- *Shows:* **0** prior sign-ins from the loaner. The employee normally uses an assigned laptop (~56 sign-ins in the quarter).

**12.** `What do we know about the incident device: type, whether it is managed, and who it is assigned to?`
- *Shows:* a **managed loaner laptop** in the **pool**, assigned to no one.

**13.** `Did any other employee sign in from that device during the quarter?`
- *Shows:* **no one else** signed in from it.

**14.** `Was the cloud account that received that file used by any other employee?`
- *Shows:* the Dropbox account appears **once, for one employee only**.
- *Say:* "Questions 11–14 cut both ways. A never-before-used loaner points toward compromise. A managed device, MFA passed, and a destination no one else used point toward the employee's own session. The data narrows it but can't settle it."

**15.** `Given all of that, what is the leading hypothesis and what evidence would separate insider misuse from account or device compromise?`
- *Shows:* **"Undetermined – needs more evidence"**, with the indicators for each side and the evidence that would separate them: device forensics on the loaner, the loaner checkout record, Okta MFA and session details, and Dropbox account ownership.

**16.** `What response should the analyst approve first, and why?`
- *Shows:* containment proportionate to a P1 that preserves evidence: preserve evidence and logs, revoke sessions and tokens, isolate the loaner, and request preservation of the Dropbox content, all **before** contacting the employee.
- *Hand-off:* "Genie recommends; it doesn't act. The analyst approves these actions in the app, and that decision is written to Lakebase with the analyst's identity."

## Close (30 s)
> "We never typed a name. We asked four business questions: who accessed the data, was it unusual, did it move, and what's the evidence. 21,012 queries narrowed to one incident, two decoys were cleared with evidence, and two hypotheses stay open until forensics settles them. Every answer above is an inspectable SQL query over Unity Catalog–governed tables, running as you."

---

## Presenter notes
- **Clarifying suggestions:** Genie sometimes ends with "Would you prefer…?". Ignore it and ask the next prompt.
- **Re-wording:** if you improvise, keep anchoring follow-ups to "the highest-priority incident" or "that file". Avoid "personal destination" in Act 6: Genie maps that phrase to a column that also matches the DLP-only case and can switch incidents.
- **Show the SQL:** in Acts 4 and 6, open **Show code** on at least one answer to prove the joins (lineage `statement_id`, same `device_id`, same `sha256`).
- **Space settings that make this work** (in `src/genie/build_space.py`):
  - The sample questions and example SQL name no one.
  - "Highest-priority" is defined as `ORDER BY priority, fused_risk DESC`.
  - Data-movement answers are summarised by chain stage, with unauthorized chains first.
  - "Before the incident" excludes the incident's own events.
  - Two example SQLs, both anchored on the highest-priority incident, cover device history and reuse of the destination account.
  - Answers are always in English. In testing, Genie once switched to German mid-conversation.
