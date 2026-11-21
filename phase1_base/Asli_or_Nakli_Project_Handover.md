# PROJECT HANDOVER DOCUMENT

## Asli-or-Nakli: Heterogeneous Database Integration for Medicine Authenticity Verification

**Document purpose:** Preserve the project context available in the
supplied files and project conversation history so another LLM can
continue without restarting discovery.\
**Evidence rule:** This document distinguishes confirmed project
statements, conversation-reported implementation details, and
unknown/unverified items. It does not claim that unprovided source code
or a live database was inspected.\
**Current context date:** 18 October 2026 (project conversation notes
include a Phase 2 evaluation scheduled for 21--23 October 2026).

------------------------------------------------------------------------

# 1. PROJECT IDENTITY AND OVERVIEW

## 1.1 Identity

-   **Working name:** "Asli-or-Nakli" / identification of fake items
    (medicine) while purchasing.
-   **Project category:** Academic database systems / heterogeneous data
    integration / data quality and entity matching / medicine
    authenticity verification.
-   **Stated project goal:** "From heterogeneous data to intelligent,
    trustworthy and decision-centric integration."
-   **Primary problem:** A purchaser needs a trustworthy view of a
    medicine/item's history---whether it appears genuine, when it was
    procured, and which distributor/supplier supplied it---despite the
    relevant information being stored in independently designed
    databases with differing schemas and attribute names.
-   **Core idea:** Integrate manufacturer, distributor, and vendor data
    through a mediator database, PostgreSQL Foreign Data Wrappers (FDW),
    and a global view; apply verification rules and return an outcome
    such as Genuine, Nakali, Suspicious, or Expired.

## 1.2 Intended use case

A user enters/scans or otherwise provides an item code while purchasing
a medicine. The system attempts to assemble the item's relevant history
across data sources and report: 1. Whether the item appears genuine or
not. 2. When it was procured/received. 3. Which distributor/supplier
supplied it. 4. Whether the result warrants reporting to the Ministry of
Consumer Affairs if the item is identified as "Nakali."

The original brief mentions capturing a unique item code and other item
description, distributor/supplier details and items supplied to vendors,
and manufacturer-side item details with a unique code.

## 1.3 Intended data sources

At least these independently designed structured sources are part of the
project concept: - **Manufacturer database:** Manufacturer/company-side
medicine/item details and manufacturer-specific unique code. -
**Distributor database:** Distributor details and the items
distributed/supplied to vendors. - **Vendor database:** Vendor
inventory/receipt/stock details and related item identifiers. -
**Mediator database:** The integration/query coordination layer,
described in project conversations as "Member 4." - **GUI:** Streamlit,
where the user enters an item code. - **Integrated/global view:**
Combines the remote sources. - **Verification rules:** Check consistency
and classify the result. - **Reporting/analytics:** A reporting outcome
for suspected fake items and analytics; actual Ministry submission
integration is not confirmed.

## 1.4 Core architecture flow (supplied project note)

``` text
User enters Item Code
        ↓
Streamlit GUI
        ↓
Mediator Database (Member 4)
        ↓
FDW → Manufacturer + Distributor + Vendor DBs
        ↓
Global View combines their data
        ↓
Verification rules check consistency
        ↓
Genuine / Nakali / Suspicious / Expired
        ↓
Report + Analytics
```

## 1.5 Distinctive/innovation angle

The project is not merely a single-database lookup. Its stated academic
focus is heterogeneous data integration: sources are designed in
isolation, and at least one matching value is shared across databases
even if the attribute names differ. Conversations explicitly explored
how `medicine_code` and `item_code` differ and how an item code should
be compared with manufacturer data. The innovation framing beyond
"heterogeneous" was discussed, but no final additional innovation
statement is recoverable. Potentially useful themes already implicit in
the project are noisy-data entity matching, consistency checks across
sources, explainable classification, provenance/history, and
decision-centric output; label these as framing options rather than
confirmed implemented innovations.

## 1.6 Scope and boundaries

**In scope** - Separate database schemas and sample data for
manufacturer, distributor, vendor, and mediator roles. - Integration of
independent data sources using PostgreSQL FDW. - Matching/normalization
across differently named attributes. - A global view and possibly a
materialized view. - Verification outcomes for genuine, fake ("Nakali"),
suspicious, expired, missing vendor record, and unapproved
vendor/distributor scenarios as discussed. - Streamlit GUI and
report/analytics flow as the documented target architecture. -
Demonstration under noisy data and entity matching, per Phase 2
instructions.

**Not confirmed / do not assume** - A live external API for Ministry of
Consumer Affairs. - Production deployment, public users, real
pharmaceutical data, real regulatory reporting, barcode/image scanning
implementation, or legally validated counterfeit detection. - Machine
learning model, OCR implementation, cryptographic supply-chain tracking,
or blockchain. - Final exact schemas and all business rules.

## 1.7 Development status (best available view)

This is an academic project with PostgreSQL and DBeaver used during
development, and PostgreSQL FDW, a mediator DB, global-view logic,
vendor/distributor/manufacturer records, and SQL testing discussed in
detail. There is evidence of SQL data and queries being created or
tested, but this handover does not contain a complete repository or
final source files, and no complete end-to-end verification evidence is
available. Treat individual features as "implemented or being tested,
but not independently verified" unless stated otherwise below.

## 1.8 Long-term vision

The original brief mentions reporting a Nakali item to the Ministry of
Consumer Affairs and presenting an item's complete history. A full
operational/regulatory deployment plan was not discussed.

------------------------------------------------------------------------

# 2. CONVERSATION HISTORY AND PROJECT EVOLUTION

Dates below are based on available project conversation metadata. The
shared project history is partial, so this is a reconstruction, not a
claim to have every conversation transcript.

## 2.1 Original project brief (date not available in the visible source)

The project was described as "Building Identification of fake items
(medicine) while purchasing." Requirements included: - Create multiple
structured data sources. - Store item unique code and description. -
Store distributor/supplier details and the items they distribute to
vendors. - Store manufacturer/company item details with a unique code. -
Report an item to the Ministry of Consumer Affairs if it is Nakali. -
Design a schema for each DB and populate data. - Assume at least one
shared value across isolated databases, even where the attribute names
differ. - Overall goal: "From heterogeneous data to intelligent,
trustworthy and decision-centric integration."

## 2.2 September 2026: Schema/data setup and database workflow

Available conversation summaries show the team worked on vendor,
distributor, and mediator database setup and test data. PostgreSQL and
DBeaver were used. The project included SQL for a `distributor_db`, and
the user asked for complete copy-paste SQL, approval queries, and
queries to add item codes such as `WXY` to a distributor. The exact
complete SQL blocks are not available in the current handover context,
so do not recreate them from memory or guess their schemas.

On 11 September 2026, a conversation titled "Vendor DB Schema" requested
vendor DB/schema and 10 records for vendor tables named `vendor`,
`medicine_stock`, and `medicine_sales`. The user later asked "where is
schema matching," indicating that cross-source schema/entity matching
was a key concern and should be made explicit in the system rather than
hidden in a plain lookup.

On 12 September 2026, the team was working with DBeaver and PostgreSQL.
A user reported that after opening the SQL editor, DBeaver showed that
no connection to PostgreSQL was established. Guidance was requested on
where to open the SQL editor and what the two tools were doing. Exact
connection settings are unknown.

## 2.3 Mid-September 2026: Verification cases and global view

Conversations around 15--16 September explored: - What vendor-side cases
should classify an item as fake or suspicious. - Other vendor cases,
including an unapproved vendor. - Whether the logic existed in the
global view versus an analysis step. - A requirement for a general
solution, not a one-off query for one test item. - Test cases with
several item IDs per case. - If an item is not present in the test data,
the output should say **"vendor record not found."** - Explanation of
global view versus materialized view. - How to see SQL logs in DBeaver
or PostgreSQL terminal. - What the project's scope and innovation are
beyond heterogeneous integration. - How to see logs when connected
databases are changed. - How to restart/keep PostgreSQL running without
manually starting it each time.

One explicit correction in this period was: the user did not want logic
that only tests one hard-coded item; they asked for general logic and to
test it through the GUI. Another important correction was that the user
wanted to know whether matching/classification logic was actually in the
global view, not merely in an analysis step.

## 2.4 September 2026: Item code versus medicine code

A conversation on 16 September asked why both `medicine_code` and
`item_code` existed. The concern was that manufacturer data has a
medicine code, so it was unclear what the system compares when a query
supplies an item code. This is a crucial unresolved data-model issue: -
The system must define whether `item_code` is a pack/stock/item-level
identifier, vendor-side identifier, distributor identifier, or a
cross-database shared identifier. - It must define how that identifier
maps to the manufacturer's `medicine_code`. - Do not silently treat the
two codes as equivalent unless the actual schema/business rules
establish that. - The project brief only says at least one value is
shared across isolated DBs, with possibly different attribute names. The
exact canonical-key strategy is not available in this handover.

## 2.5 September 2026: Distributor approvals and sample item codes

The team discussed approval queries and adding item codes to a
distributor. Specific strings mentioned include `WXY` and `WXT`; one
conversation requested a query for a mediator to approve medicine item
code `WXT`. Another asked to add `WXY` in the distributor. These appear
to be sample/test codes, but their exact role and final records are
unverified. Do not assume they are production medicine codes.

A list of item IDs and distributor IDs was supplied in a conversation:

``` text
ITEM000106  2
ITEM000108  2
ITEM000115  2
ITEM000119  2
ITEM000125  3
ITEM000126  3
ITEM000141  3
ITEM000143  3
ITEM000149  3
ITEM000155  3
ITEM000169  3
ITEM000189  4
ITEM000198  4
ITEM000210  [distributor value appears incomplete in the available excerpt]
```

The original prompt asked to "give this with actual distributor id."
Treat the list as test context only; the final row is incomplete in the
available excerpt and must not be filled in by guessing.

## 2.6 September 2026: Vendor inventory fields and expiry

A SQL fragment was discussed for inserting vendor inventory records:

``` sql
INSERT INTO vendor_inventory
    (vendor_id, item_identifier, received_date, expiry_date, vendor_distributor_id)
VALUES
    (1, 'ITEM000106', CURRENT_DATE, '2028-04-12', 2),
    ...
```

Only the beginning of the insert is available; the remainder of the
values is missing. This establishes that a vendor inventory table/field
set was discussed, but does not prove this is the final schema or that
the complete statement ran successfully.

## 2.7 September 2026: Runtime and performance concerns

A conversation on 13 September asked whether execution on Linux from
another laptop takes longer than on Windows, and reported that
processing 200 records was taking minutes. The root cause and measured
timings were not established. Potential areas to investigate later
include network latency, FDW query pushdown, join plans, indexes, remote
connections, materialized view refreshes, and inefficient per-row
lookups, but these are hypotheses, not established causes.

## 2.8 September 2026: PostgreSQL startup and logs

The user reported needing to start PostgreSQL repeatedly and asked how
to keep it running. A screenshot was shared, but its detailed contents
are not recoverable here; the user said the suggested approach was "not
happening." Therefore the startup issue should be treated as unresolved.
The user also asked how to see SQL logs in PostgreSQL terminal/DBeaver
and how to see logs after changes in connected DBs. The exact operating
system/service configuration is unknown.

## 2.9 October 2026: Phase 2 evaluation requirements

A conversation dated 12 October 2026 summarized the professor's Phase 2
instructions: - Phase 2 evaluation is **21--23 October 2026**. -
Evaluation will be in class on a random-selection basis, as in
Phase 1. - The project must demonstrate **data integration and entity
matching under noisy data**. - Example: if vehicle registration is not
an exact match, identify close candidates from a scanned registration
number. This is an example of the professor's general expectation, not a
change of this project from medicines to vehicles. - For this medicine
project, the analogous demonstration is likely noisy/mismatched item
identifiers and candidate matching across the
manufacturer/distributor/vendor sources. This analogy is an
interpretation; confirm the intended test cases with the course
instructions/team. - The professor's emphasis means exact-key matching
alone may be insufficient for the evaluation. Demonstrate how near
matches are identified and how uncertainty is reflected in "Suspicious"
rather than silently declaring an item genuine.

## 2.10 Latest known state

As of the available project history, the system's target flow is
Streamlit → mediator DB → FDW sources → global view → verification rules
→ classification → reporting/analytics. The team is working toward a
general GUI-tested solution, with explicit interest in schema matching,
vendor-not-found behavior, approvals, expiry, global/materialized views,
and noisy-data entity matching. The Phase 2 evaluation date is close. No
complete final repository, final DDL, test transcript, or verified
end-to-end output was supplied.

------------------------------------------------------------------------

# 3. REQUIREMENTS SPECIFICATION

Status vocabulary: - **Explicit** = directly stated in the project brief
or conversation. - **Derived** = reasonable engineering interpretation
needed to implement the stated goal. - **Unknown** = not established in
available evidence.

## 3A. Functional requirements

  ----------------------------------------------------------------------------------------------------
  ID             Requirement                Basis / motivation   Priority         Status /
                                                                                  dependencies
  -------------- -------------------------- -------------------- ---------------- --------------------
  FR-01          Accept an item code from a Explicit target      High             Streamlit GUI is in
                 user.                      flow; lookup begins                   architecture notes;
                                            with item code.                       actual GUI status
                                                                                  unverified.

  FR-02          Retrieve manufacturer-side Explicit brief.      High             Manufacturer DB
                 item/medicine information.                                       exists in target
                                                                                  architecture; exact
                                                                                  schema unknown.

  FR-03          Retrieve                   Explicit brief.      High             Distributor DB and
                 distributor/supplier                                             related queries
                 details and the items                                            discussed; final
                 distributed to vendors.                                          schema not
                                                                                  available.

  FR-04          Retrieve vendor            Explicit use case:   High             `vendor_inventory`
                 inventory/procurement      when procured and                     fields were
                 details.                   who supplied it.                      discussed; complete
                                                                                  implementation
                                                                                  unverified.

  FR-05          Integrate independent      Explicit             High             PostgreSQL FDW and
                 databases whose attribute  heterogeneous-data                    global view
                 names may differ.          requirement.                          discussed. Mapping
                                                                                  rules need explicit
                                                                                  documentation.

  FR-06          Apply general              Explicit target flow High             Exact final
                 consistency/verification   and repeated user                     predicates/rule
                 rules across sources.      requests.                             ordering unknown. Do
                                                                                  not use hard-coded
                                                                                  single-item logic.

  FR-07          Return a classification    Explicit supplied    High             Classification rule
                 such as Genuine, Nakali,   flow.                                 definitions and
                 Suspicious, or Expired.                                          precedence remain
                                                                                  unverified.

  FR-08          Return "vendor record not  Explicit user        High             Must distinguish
                 found" when the requested  request.                              missing vendor data
                 item has no vendor record                                        from proof of
                 in the test data.                                                counterfeiting.

  FR-09          Check approval status for  Approval queries and High/Medium      Exact approval
                 a distributor/vendor/item  "unapproved vendor"                   entities/columns and
                 where relevant.            cases discussed.                      final rules unknown.

  FR-10          Account for                Explicit use case    High             Expiry rule and date
                 received/procurement date  and                                   semantics need
                 and expiry date.           `vendor_inventory`                    verification.
                                            fields.                               

  FR-11          Support general test cases Explicit correction. High             GUI/SQL integration
                 via GUI, not only a                                              unverified
                 one-off SQL query.                                               end-to-end.

  FR-12          Report a Nakali item to    Explicit original    Medium           Actual report
                 Ministry of Consumer       brief.                                format, workflow,
                 Affairs.                                                         endpoint, and live
                                                                                  submission are not
                                                                                  discussed.

  FR-13          Provide                    Supplied flow note.  Medium           Specific
                 reporting/analytics after                                        metrics/reports are
                 classification.                                                  unknown.

  FR-14          Demonstrate noisy-data     Phase 2 instruction. High /           Need a matching
                 entity matching.                                time-sensitive   method, candidate
                                                                                  list,
                                                                                  threshold/score, and
                                                                                  tests;
                                                                                  implementation not
                                                                                  confirmed.

  FR-15          Explain item               Explicit "complete   High             Global view is
                 history/provenance in a    history (view)" use                   intended; exact
                 single view.               case.                                 output columns
                                                                                  unknown.
  ----------------------------------------------------------------------------------------------------

## 3B. Non-functional requirements

  ------------------------------------------------------------------------------
  ID                Requirement              Basis             Status
  ----------------- ------------------------ ----------------- -----------------
  NFR-01            Results should be        Stated project    Desired;
                    trustworthy and          goal.             verification
                    decision-centric, with                     criteria not
                    evidence from multiple                     formally
                    sources.                                   specified.

  NFR-02            Data integration must    Explicit.         FDW/global view
                    work across                                intended; mapping
                    independently designed                     completeness
                    sources.                                   unknown.

  NFR-03            Rules should be general  Explicit          Must be checked
                    rather than hard-coded   correction.       against actual
                    for one item.                              SQL/view
                                                               definitions.

  NFR-04            The system should expose Derived from      Recommended;
                    ambiguous/inconsistent   "Suspicious"      exact thresholds
                    cases as suspicious      outcome and trust not discussed.
                    rather than overstate    objective.        
                    certainty.                                 

  NFR-05            The system should be     Phase 2           Evaluation 21--23
                    demonstrable in class    instruction.      Oct 2026.
                    via random test cases.                     
  ------------------------------------------------------------------------------

## 3C. Technical requirements

  --------------------------------------------------------------------------
  ID                Requirement         Basis             Status
  ----------------- ------------------- ----------------- ------------------
  TR-01             Use PostgreSQL for  Directly          In use. Version
                    database work.      discussed.        unknown.

  TR-02             Use DBeaver for     Directly          In use; connection
                    database/SQL        discussed.        setup trouble
                    interaction.                          reported.

  TR-03             Use PostgreSQL FDW  Supplied          Discussed/target
                    to connect          architecture      design; exact FDW
                    manufacturer,       flow.             setup unknown.
                    distributor, and                      
                    vendor databases to                   
                    the mediator.                         

  TR-04             Build a global view Repeated          View discussed;
                    joining integrated  discussions.      exact final
                    source data.                          definition
                                                          unavailable.

  TR-05             Explain the         Explicit          Design explanation
                    difference and role discussion        needed; refresh
                    of global view and  request.          policy unknown.
                    materialized view.                    

  TR-06             Use Streamlit as    Supplied flow.    Target
                    the GUI.                              architecture;
                                                          exact app files
                                                          unknown.

  TR-07             Define cross-source User asked "where Important
                    schema/identifier   is schema         unresolved design
                    matching            matching?" and    item.
                    explicitly.         questioned        
                                        `medicine_code`   
                                        vs `item_code`.   
  --------------------------------------------------------------------------

## 3D. Performance requirements

-   **Explicit observed concern:** Processing 200 records was reported
    to take minutes in a Linux/remote-laptop context.
-   **No formal SLA or benchmark target** was set.
-   Need to measure query latency for the same dataset and environment,
    distinguish remote-network delay from query execution, inspect
    `EXPLAIN (ANALYZE, BUFFERS)` where appropriate, and compare global
    view versus materialized view. These are recommendations, not prior
    verified results.

## 3E. Security and privacy requirements

-   No authentication design, role matrix, secrets management,
    encryption policy, audit retention, or access-control scheme was
    discussed.
-   Because the project may report counterfeit medicines, a production
    implementation should not expose personal or commercial information
    unnecessarily and should distinguish suspicion from confirmed
    counterfeit status. This is a prudent recommendation, not a
    documented existing requirement.
-   Do not place database passwords or secrets in code or handover
    documents.

## 3F. User experience requirements

-   Streamlit GUI with item-code input is the intended flow.
-   The output should make the item's history and classification
    understandable.
-   Missing vendor record should be stated explicitly.
-   General logic should be exercised through the GUI rather than only
    using one test-specific query.
-   Exact UI layout, validation messages, loading states, and
    accessibility needs are unknown.

## 3G. Deployment requirements

-   Local/multi-machine database connectivity has been attempted or
    considered.
-   PostgreSQL startup persistence is an unresolved operational issue.
-   Hosting provider, production environment, domain, CI/CD, and
    production deployment commands are unknown.

## 3H. Constraints and limitations

-   The sources are heterogeneous and designed independently.
-   At least one shared value exists, but the attribute name may differ
    between databases.
-   Current record samples may be synthetic/test data; real-world data
    authenticity is unknown.
-   No complete repository or final schemas are available in this
    handover context.
-   Phase 2 evaluation is imminent relative to the handover date.

## 3I. Optional/future requirements

-   Real Ministry of Consumer Affairs report submission.
-   Rich analytics/dashboard.
-   OCR or barcode/QR scanning (the professor's scanned-registration
    example is not evidence that this project has implemented image
    scanning).
-   Stronger entity-resolution methods and explainable match confidence.
-   Audit trail of decisions and source provenance. These are
    possibilities, not confirmed commitments.

------------------------------------------------------------------------

# 4. TECHNICAL ARCHITECTURE

## 4.1 Known components

  --------------------------------------------------------------------------------------
  Component               Responsibility                         Evidence / status
  ----------------------- -------------------------------------- -----------------------
  Streamlit GUI           Collect item code; show                Explicit architecture
                          result/history.                        note; actual source
                                                                 file unknown.

  Mediator database       Query coordination/integration layer.  Explicit architecture
  ("Member 4")                                                   note; actual
                                                                 connection/schema
                                                                 unknown.

  Manufacturer DB         Manufacturer/company item details and  Explicit brief and
                          manufacturer-side code.                architecture note.

  Distributor DB          Distributor/supplier identity,         Explicit brief and
                          distributed items, approvals           conversations.
                          potentially relevant.                  

  Vendor DB               Inventory/receipt/procurement/expiry   Explicit brief and SQL
                          and supplier link.                     fragment.

  PostgreSQL FDW          Expose remote source tables to         Explicit architecture
                          mediator for integrated querying.      note. Exact foreign
                                                                 server/table names
                                                                 unknown.

  Global view             Combine data from the sources.         Repeated discussion.
                                                                 Definition unavailable.

  Materialized view       A cached/persisted result was          Exact implementation
                          discussed as a comparison/architecture and refresh policy
                          concept.                               unknown.

  Verification rules      Classify consistency, approval,        Target flow; exact
                          missing data, expiry, and authenticity rules unknown.
                          outcomes.                              

  Reporting/analytics     Present outcomes and support           Target flow; actual
                          reporting.                             features unknown.
  --------------------------------------------------------------------------------------

## 4.2 Data flow

1.  User submits an item identifier.
2.  GUI sends the value to the mediator query layer.
3.  Mediator uses FDW-exposed manufacturer, distributor, and vendor
    data.
4.  Global view assembles a cross-source record/history.
5.  Verification logic evaluates identifier matching and business
    conditions.
6.  UI returns a classification and supporting history/evidence.
7.  Reporting/analytics may present or record the result; actual report
    delivery to a ministry is not verified.

## 4.3 Architecture pattern and rationale

The design is a mediator-based heterogeneous database integration
system. It preserves separate source databases rather than forcing all
source data into one newly unified database. FDW provides a
PostgreSQL-native route for querying remote sources; a global view
provides a unified logical representation. A materialized view may
improve repeated-query performance but requires a refresh strategy and
can become stale. The view/materialized-view distinction was discussed,
but no final refresh policy is documented.

## 4.4 Schema matching and entity resolution

This is a critical project concern, not an optional detail. - The brief
requires at least one common value across separate DBs, potentially
under different column names. - The team questioned why both
`medicine_code` and `item_code` exist and how an item code is compared
with the manufacturer record. - The system needs an explicit
mapping/relationship between operational item identifier and
manufacturer medicine identifier. - For Phase 2, the professor expects
matching under noisy data. Exact equality alone may fail the
demonstration. - Do not assume all IDs are interchangeable. Separate: 1.
**Identifier mapping:** which fields represent the same concept across
sources. 2. **Entity resolution:** how to find likely same items when
identifiers differ or contain noise. 3. **Business verification:**
whether approvals, supplier links, dates, and other evidence are
consistent. - Candidate fuzzy matching approaches (e.g., normalized
strings, edit distance, similarity scores) are recommendations only; the
actual selected algorithm is unknown. If adopted, report candidate
matches and confidence, and do not silently auto-classify a
low-confidence match as genuine.

## 4.5 Authentication, API, infrastructure

-   Authentication/authorization: Not discussed.
-   External API integrations: None confirmed.
-   Ministry endpoint/report format: Unknown.
-   Hosting provider/domain: Unknown.
-   Exact operating systems: Windows and Linux were mentioned in
    performance context; which machine hosts which database is unknown.
-   PostgreSQL version, Streamlit version, Python version, and FDW
    extension/version: Unknown.

## 4.6 Known weaknesses/technical debt

-   Identifier semantics (`item_code` vs `medicine_code`) are unresolved
    in the available record.
-   Exact verification rules and precedence are not preserved.
-   Cross-database query performance is reportedly slow for 200 records.
-   PostgreSQL startup persistence has not been resolved in the
    available record.
-   No complete source repository, schema dump, view definitions, or
    test results are included here.
-   Source-of-truth and stale-data behavior for a materialized view are
    not documented.

------------------------------------------------------------------------

# 5. CODEBASE AND FILE STRUCTURE

## 5.1 Repository

-   Repository name: **Unknown**.
-   Git URL, branch, commit history: **Not discussed**.
-   Local project path: **Unknown**.
-   Full codebase available for inspection: **No**; only selected
    project notes, snippets, and conversation summaries are available.

## 5.2 Known files/resources

  --------------------------------------------------------------------------------
  Resource                What is known                    Confidence
  ----------------------- -------------------------------- -----------------------
  `Asli-or-Nakli.txt`     Project brief: fake medicine     Directly inspected.
                          identification, heterogeneous    
                          DBs, shared values, reporting    
                          goal.                            

  `pasted.txt`            Short architecture flow from     Directly inspected.
                          Streamlit to mediator/FDW/global 
                          view/classification/reporting.   

  `Pasted text.txt`       User's handover-document         Directly inspected.
                          request; not project             
                          implementation code.             

  SQL for                 Conversation says a complete SQL Conversation summary
  `distributor_db`        block was provided in prior      only.
                          project work; actual complete    
                          block is not available in        
                          current materials.               

  Vendor inventory INSERT Partial SQL shown below.         Direct excerpt.
  snippet                                                  

  Streamlit app source    Not supplied.                    Unknown.

  Global view SQL         Discussed, but definition not    Unknown.
                          supplied here.                   

  Materialized view SQL   Discussed, but definition not    Unknown.
                          supplied here.                   

  FDW setup SQL           Not supplied here.               Unknown.
  --------------------------------------------------------------------------------

## 5.3 Actual SQL snippet preserved

``` sql
INSERT INTO vendor_inventory
    (vendor_id, item_identifier, received_date, expiry_date, vendor_distributor_id)
VALUES
    (1, 'ITEM000106', CURRENT_DATE, '2028-04-12', 2),
    ...
```

This is an incomplete excerpt. Do not execute as-is; the ellipsis is a
placeholder and the complete rows are unavailable. It shows the
discussed column names but does not establish a final schema.

## 5.4 Table and field names mentioned

-   `vendor`
-   `medicine_stock`
-   `medicine_sales`
-   `vendor_inventory`
-   `vendor_id`
-   `item_identifier`
-   `received_date`
-   `expiry_date`
-   `vendor_distributor_id`
-   `medicine_code` (concept/field discussed)
-   `item_code` (concept/field discussed)
-   `distributor_db` (database name mentioned)
-   "Mediator Database" / "Member 4"
-   Manufacturer, Distributor, Vendor DBs These names are not a complete
    schema. Exact primary keys, foreign keys, data types, constraints,
    and indexes are unknown.

## 5.5 Commands, package versions, entry points

-   SQL is run through DBeaver/SQL Editor and/or PostgreSQL terminal,
    but exact commands and environment settings are not preserved.
-   Streamlit is the named GUI framework; launch command and entry-point
    filename are unknown.
-   Python package versions, dependency file
    (`requirements.txt`/`pyproject.toml`), Docker files, tests, and
    build scripts: Unknown.

------------------------------------------------------------------------

# 6. DATABASE, DATA MODELS, AND APIs

## 6.1 Database topology

Intended logical topology: - Separate Manufacturer DB - Separate
Distributor DB - Separate Vendor DB - Mediator DB with FDW connections
to the source DBs - Global view over integrated data -
Optional/considered materialized view - Streamlit application connecting
to mediator

Whether these are physically separate PostgreSQL instances, separate
databases on one instance, or a mix is unknown.

## 6.2 Known vendor inventory model (partial)

  -------------------------------------------------------------------------
  Field                     Meaning inferred from   Status
                            name                    
  ------------------------- ----------------------- -----------------------
  `vendor_id`               Vendor identifier       Mentioned in SQL;
                                                    type/constraints
                                                    unknown.

  `item_identifier`         Item/stock identifier   Mentioned in SQL;
                            held by vendor          mapping to manufacturer
                                                    `medicine_code`
                                                    unresolved.

  `received_date`           Date vendor             Mentioned in SQL.
                            received/procured the   
                            item                    

  `expiry_date`             Item expiry date        Mentioned in SQL.

  `vendor_distributor_id`   Distributor link        Mentioned in SQL;
                            associated with vendor  relationship details
                            inventory               unknown.
  -------------------------------------------------------------------------

The SQL fragment used `CURRENT_DATE` and the literal expiry date
`'2028-04-12'`. This is an example record, not proof of a final policy.

## 6.3 Other known model concepts

-   Manufacturer/company item details and unique code.
-   Distributor/supplier identity and item-to-vendor distribution.
-   Vendor stock, received/procurement date, expiry date, and
    distributor association.
-   Approval state was discussed (e.g., mediator approving `WXT`,
    distributor item `WXY`, and an unapproved vendor scenario), but the
    exact tables/columns representing approvals are unknown.
-   "Nakali," "Suspicious," "Genuine," "Expired," and "vendor record not
    found" are user-facing outcome labels discussed or shown in the
    architecture flow.

## 6.4 Test identifiers

Examples seen in conversation: - `ITEM000106` - `ITEM000108` -
`ITEM000115` - `ITEM000119` - `ITEM000125` - `ITEM000126` -
`ITEM000141` - `ITEM000143` - `ITEM000149` - `ITEM000155` -
`ITEM000169` - `ITEM000189` - `ITEM000198` - `ITEM000210` (associated
distributor value incomplete in available excerpt) - `WXY` - `WXT`

These are test/context identifiers, not verified real medicine codes.
Their final distribution across scenarios is not fully recoverable.

## 6.5 APIs and integrations

-   No HTTP API endpoints, payloads, API authentication, or rate limits
    were discussed.
-   PostgreSQL FDW is the known database integration mechanism.
-   No confirmed external Ministry API.
-   No confirmed OCR/barcode service.

## 6.6 Data quality and matching

Known concerns: - Independently designed schemas can use different
attribute names for semantically shared values. - Item code and medicine
code semantics are confusing/unresolved. - Phase 2 explicitly requires
demonstrating entity matching under noisy data. - Missing vendor record
must be distinguished from a known fake item. - A missing record is
absence of evidence, not proof of counterfeiting. - Approval status,
date validity, source agreement, and identifier match confidence should
be represented as separate evidence where possible. The last point is an
engineering recommendation.

------------------------------------------------------------------------

# 7. DEVELOPMENT ENVIRONMENT AND SETUP

This section deliberately avoids inventing setup commands that cannot be
verified.

## 7.1 Known tools

-   PostgreSQL: database system.
-   DBeaver: GUI SQL client.
-   Streamlit: intended user interface.
-   PostgreSQL FDW: intended source integration.
-   Windows and Linux were mentioned in a performance question.
-   Exact OS versions, PostgreSQL version, Python version, DBeaver
    version, Streamlit version, and FDW extension details: Unknown.

## 7.2 Reproduction checklist (verify against the actual environment)

1.  Install/start PostgreSQL on the machine hosting the relevant
    database(s).
2.  Confirm PostgreSQL is running and note the host, port, database
    name, username, and authentication method. Do not put passwords into
    shared documentation.
3.  Open DBeaver and create/verify a PostgreSQL connection using the
    actual settings.
4.  Open an SQL Editor attached to the intended connection. A previous
    issue occurred because the SQL editor showed no PostgreSQL
    connection.
5.  Create or restore the source databases (manufacturer, distributor,
    vendor) and mediator database using the actual project SQL files.
    Those complete files are not present in this handover.
6.  Configure FDW in the mediator to expose source tables. Exact
    extension, server, user mapping, and foreign-table statements are
    unknown and must be recovered from the project files.
7.  Create/check the global view and any materialized view using the
    actual saved SQL.
8.  Insert/load the agreed test data, including positive, negative,
    missing, unapproved, expiry, and noisy-identifier cases.
9.  Run the global-view query directly in DBeaver before connecting the
    GUI.
10. Start the Streamlit app using its actual entry-point filename and
    configured environment. The launch command cannot be stated safely
    until the filename/project setup is known.
11. Run the test matrix from the GUI and compare results with the
    expected classifications.
12. Measure performance with a fixed 200-record test and record the
    environment, query, and elapsed time.

## 7.3 Common setup/debug issues already reported

-   **DBeaver SQL editor has no PostgreSQL connection.** Check that a
    connection is created, connected, and that the editor is attached to
    the intended connection. This is a troubleshooting suggestion, not a
    confirmed resolution.
-   **PostgreSQL must be started repeatedly.** A persistence/service
    configuration was sought; the proposed solution was reported as not
    working. Exact OS/service setup and error are unknown. Revisit using
    the actual OS and PostgreSQL installation details rather than
    repeating an unverified generic fix.
-   **Queries across databases take minutes for 200 records.** Root
    cause unknown. Benchmark locally and remotely, inspect query plans
    and FDW pushdown, and compare regular versus materialized view
    behavior.
-   **Need to view SQL logs.** User asked how to inspect logs in
    DBeaver/PostgreSQL terminal and how changes in connected DBs can be
    observed. Exact logging configuration is unknown; do not assume
    query logging is enabled by default.

------------------------------------------------------------------------

# 8. IMPLEMENTATION STATUS MATRIX

Statuses below are conservative because complete code and test output
are not included.

  ------------------------------------------------------------------------------------------------------
  Feature                             Status               Evidence              Remaining work /
                                                                                 verification
  ----------------------------------- -------------------- --------------------- -----------------------
  Project brief and use case          Completed as a       `Asli-or-Nakli.txt`   Preserve wording and
                                      specification                              translate it into
                                                                                 testable acceptance
                                                                                 criteria.

  PostgreSQL/DBeaver development      Implemented/used,    Multiple setup/debug  Record versions,
  setup                               but environment not  conversations         connection settings
                                      fully verified                             (without secrets), and
                                                                                 reliable startup
                                                                                 method.

  Manufacturer DB                     Unknown / part of    Brief and             Recover DDL, sample
                                      target design        architecture flow     data, keys, and code
                                                                                 mapping.

  Distributor DB                      Discussed/SQL        `distributor_db`,     Recover complete SQL
                                      supplied in prior    approval/add-item     and inspect actual
                                      conversation, exact  discussions           schema/data.
                                      current state                              
                                      unknown                                    

  Vendor DB                           Partially documented `vendor`,             Recover DDL and
                                                           `medicine_stock`,     establish which tables
                                                           `medicine_sales`,     are current.
                                                           `vendor_inventory`    
                                                           mentioned             

  Mediator DB                         Part of target       Architecture note     Recover DDL, FDW
                                      design;              says "Member 4"       objects, and role
                                      implementation                             responsibilities.
                                      details unverified                         

  FDW links                           Planned/discussed;   Architecture flow     Verify connections and
                                      live status unknown                        foreign tables from
                                                                                 mediator.

  Global view                         Discussed/possibly   Repeated view logic   Retrieve exact
                                      implemented, not     questions             definition; test all
                                      verified here                              cases and missing
                                                                                 records.

  Materialized view                   Discussed; status    User asked            Confirm whether it
                                      unknown              difference/use        exists and how/when
                                                                                 refreshed.

  Schema matching                     Recognized as        User asked "where is  Document mapping and
                                      necessary; exact     schema matching?"     implement/test noisy
                                      implementation                             identifiers.
                                      unknown                                    

  General verification rules          Requested; actual    User rejected one-off Inspect view/queries;
                                      predicates unknown   logic                 test each rule
                                                                                 independently and in
                                                                                 combination.

  Genuine/Nakali/Suspicious/Expired   Target flow;         Supplied architecture Define exact conditions
  outputs                             implementation       note                  and precedence; show
                                      unverified                                 evidence behind each
                                                                                 result.

  "vendor record not found"           Explicit expected    Conversation request  Add a test with an item
                                      behavior;                                  absent from vendor
                                      implementation                             records.
                                      unverified                                 

  Approval checks                     Discussed;           `WXY`, `WXT`,         Recover approval schema
                                      implementation       unapproved vendor     and expected behavior.
                                      unknown                                    

  Expiry handling                     Fields discussed;    `expiry_date` in SQL  Test expired and
                                      rule unverified      fragment              non-expired items,
                                                                                 including boundary
                                                                                 date.

  Streamlit GUI                       Intended             Architecture flow     Recover app code and
                                      architecture; source                       test user input →
                                      unavailable                                output path.

  Report/analytics                    Planned target flow; Architecture note and Define report content;
                                      implementation       original brief        do not claim external
                                      unknown                                    submission.

  Ministry of Consumer Affairs        Planned in original  Project brief         Specify report
  integration                         brief; not verified                        format/process;
                                                                                 external API unknown.

  Noisy-data entity matching          Required for Phase   Professor's           Implement/demonstrate
                                      2; implementation    instructions summary  candidate matching and
                                      unknown                                    explain confidence.

  200-record performance              Reported slow;       User reported minutes Benchmark, inspect
                                      unresolved                                 plans, optimize only
                                                                                 after measurement.

  PostgreSQL persistent startup       Blocked/unresolved   User said fix was     Identify host
                                      in history           "not happening"       OS/service
                                                                                 configuration and
                                                                                 resolve.

  SQL logging                         Help requested;      Conversations about   Establish reliable
                                      configuration        logs                  query/change logging or
                                      unknown                                    audit method.
  ------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

# 9. BUGS, ERRORS, AND DEBUGGING HISTORY

## 9.1 DBeaver SQL editor has no connection

-   **Symptom:** After opening SQL Editor, it displayed that no
    connection to PostgreSQL was established.
-   **Exact error text:** Only the paraphrase is available; exact
    message unknown.
-   **Likely cause:** Editor not attached to an active PostgreSQL
    connection, or connection not configured/connected. This is a
    hypothesis.
-   **Attempt/result:** User sought instructions; no confirmed
    resolution preserved.
-   **Next step:** Inspect DBeaver connection status, connection
    properties, database selection, and editor association.

## 9.2 PostgreSQL must be started repeatedly

-   **Symptom:** User had to start PostgreSQL again and again.
-   **Exact OS/error:** Unknown; screenshot existed but its details are
    not recoverable here.
-   **Attempt/result:** User said the proposed approach was "not
    happening"; unresolved.
-   **Next step:** Confirm OS, installation method, PostgreSQL service
    name/status, and whether the server is local or remote. Do not
    assume Windows service commands apply to Linux or vice versa.

## 9.3 Slow query / remote execution

-   **Symptom:** Execution involving Linux/another laptop took minutes
    for 200 records.
-   **Exact query/timing/environment:** Not available.
-   **Root cause:** Unknown.
-   **Possible investigation:** Compare direct source query vs
    mediator/global view; test same query locally and remotely; inspect
    `EXPLAIN (ANALYZE, BUFFERS)`; verify join keys/indexes; determine
    whether FDW can push filters/joins down; check network latency;
    inspect materialized-view refresh strategy.
-   **Resolution:** None documented.

## 9.4 Schema matching unclear

-   **Symptom/question:** User asked "where is schema matching" and why
    both `medicine_code` and `item_code` exist.
-   **Root cause:** The documented design did not make the mapping
    explicit enough for the user.
-   **Resolution:** No final mapping specification available.
-   **Next step:** Create a field-mapping table and
    identifier-resolution rule before adding more query logic.

## 9.5 Missing item behavior

-   **Requirement:** If an item is not present in test data, output
    should be "vendor record not found."
-   **Status:** Requirement known; implementation/result unknown.
-   **Important distinction:** This output should mean no vendor record
    was found, not that the item was conclusively counterfeit.

## 9.6 Query/log visibility

-   **Symptom:** User wanted to see SQL logs in DBeaver or PostgreSQL
    terminal and understand changes in connected DBs.
-   **Status:** Exact logging setup and resolution unknown.
-   **Next step:** Separate application query history in DBeaver from
    PostgreSQL server logs and from data-change auditing; decide which
    one is needed and configure/test it.

------------------------------------------------------------------------

# 10. IMPORTANT DECISIONS AND RATIONALE

  ----------------------------------------------------------------------------------
  Decision / principle    Context and rationale              Status
  ----------------------- ---------------------------------- -----------------------
  Use heterogeneous data  Original brief explicitly requires Established
  sources                 isolated databases with at least   requirement.
                          one shared value despite different 
                          attribute names.                   

  Use a mediator DB and   Architecture flow explicitly       Established target
  FDW                     specifies mediator → FDW →         architecture; live
                          manufacturer/distributor/vendor.   state unverified.

  Use a global view for   Repeated discussion of global view Target/likely design;
  integrated history      and whether logic exists there.    exact SQL unknown.

  Consider a materialized User asked what global and         Considered; final
  view                    materialized views are and how     adoption/refresh policy
                          they differ.                       unknown.

  Provide general logic,  User explicitly rejected logic     Strong explicit
  not a one-item test     that tests only one item and asked preference.
                          for a general solution tested in   
                          the GUI.                           

  Return "vendor record   User explicitly requested this     Established expected
  not found" when no      case.                              behavior.
  vendor record exists                                       

  Keep item/medicine code User questioned why both codes     Unresolved design
  distinction explicit    exist and how one maps to          decision; must not
                          manufacturer data.                 assume equivalence.

  Include approval cases  Approval queries for `WXY`/`WXT`   Test/feature intent
                          and unapproved vendor scenarios    established;
                          were discussed.                    schema/rules unknown.

  Test expiry/procurement Original use case asks when        Requirement
  history                 procured; SQL fragment contains    established; exact
                          received and expiry dates.         classification rule
                                                             unknown.

  Demonstrate noisy       Professor's Phase 2 instruction    Current evaluation
  entity matching         requires data integration/entity   requirement.
                          matching under noisy data.         

  Use Streamlit for       Supplied architecture note names   Target architecture.
  user-facing flow        Streamlit GUI.                     

  Report Nakali to        Original brief states this goal.   Goal established;
  Ministry                                                   actual integration not
                                                             verified.
  ----------------------------------------------------------------------------------

No explicit record establishes a final decision to use a particular
fuzzy matching library/algorithm, exact threshold, schema, deployment
platform, or reporting API.

------------------------------------------------------------------------

# 11. TESTING AND VALIDATION

## 11.1 Known testing approach

-   Manual SQL testing through DBeaver and likely the PostgreSQL
    terminal.
-   General test cases were to be run through the GUI.
-   Test cases should include valid item codes and several different
    outcomes.
-   Phase 2 evaluation will select demonstrations randomly in class, so
    the project must not depend on one memorized happy-path item.
-   A list of item IDs and distributor IDs exists in conversation
    history (see Section 6.4).

## 11.2 Minimum test matrix to preserve project intent

The table below is a **recommended organization of known scenarios**,
not proof that every case was already implemented or passed.

  --------------------------------------------------------------------------------
  Test case            Input/data        Expected behavior       Current evidence
                       condition         grounded in project     
                                         context                 
  -------------------- ----------------- ----------------------- -----------------
  Valid consistent     Manufacturer,     Genuine (if all defined Exact data/result
  item                 distributor,      verification conditions not preserved.
                       vendor agree      pass)                   

  Identifier           Input differs     Surface likely          Required by Phase
  mismatch/noisy code  slightly from     candidates; classify    2 intent;
                       stored identifier cautiously, likely      implementation
                                         Suspicious if           unknown.
                                         unresolved              

  Item absent from     No vendor row for "vendor record not      Explicit expected
  vendor               input/candidate   found"                  behavior; test
                                                                 result unknown.

  Unapproved           Approval status   Flag/ classify          Scenario
  vendor/distributor   not approved      according to agreed     discussed; exact
                                         rule; likely Suspicious rule unknown.

  Expired item         `expiry_date`     Expired                 Outcome label
                       before current                            exists; test not
                       date                                      verified.

  Not expired          `expiry_date`     Continue other checks;  Boundary rule
                       today/future,     not expired             unknown.
                       subject to agreed                         
                       boundary rule                             

  Distributor mapping  Vendor's          Suspicious or other     Derived from
  inconsistent         distributor link  agreed inconsistency    consistency
                       conflicts with    result                  rules; exact
                       distributor                               outcome not
                       source                                    finalized.

  Manufacturer record  No matching       Do not label Genuine;   Derived
  missing              manufacturer item report missing          recommendation;
                                         manufacturer evidence   exact label
                                                                 unknown.

  Multiple candidate   Noisy identifier  Show ranked             Recommended for
  matches              matches several   candidates/ambiguity;   entity matching.
                       possible rows     avoid silent false      
                                         positive                

  Approved item        Sample item and   Match the intended      Exact
  (`WXT`/`WXY`)        approval record   approval workflow       rows/results
                                                                 unknown.
  --------------------------------------------------------------------------------

## 11.3 Actual measurements/results

-   200 records reportedly took "minutes"; no exact duration, query
    plan, hardware, or reproducible command is available.
-   No unit-test framework, test files, coverage, automated integration
    suite, or formal benchmark was discussed.
-   No successful end-to-end GUI test transcript is available in the
    current materials.
-   Do not claim tests passed without fresh evidence.

------------------------------------------------------------------------

# 12. DEPLOYMENT AND OPERATIONS

-   Hosting provider: Unknown.
-   Production/staging environment: Not discussed.
-   Local/multi-machine use: Another laptop/Linux/Windows context was
    mentioned, but exact topology is unknown.
-   PostgreSQL service startup: Problem reported; unresolved.
-   Database connections: DBeaver connection issue reported.
-   FDW configuration: Intended; exact server/user mapping settings
    unknown.
-   CI/CD: Not discussed.
-   Domain/routing: Not discussed.
-   Logging: User wants SQL logs; configuration unknown.
-   Monitoring/alerting: Not discussed.
-   Backup/restore/rollback: Not discussed.
-   Cost: Not discussed.
-   Ministry reporting endpoint: Unknown.
-   Operational recommendation: before any live deployment, add reliable
    database service management, backups, least-privilege credentials,
    clear logging, and explicit separation between "suspicious" and
    "confirmed counterfeit." These are recommendations, not current
    features.

------------------------------------------------------------------------

# 13. CURRENT STATE AND IMMEDIATE NEXT STEPS

## 13.1 What is already established

-   Project purpose, use case, and overall goal.
-   Source roles: manufacturer, distributor, vendor, and mediator.
-   Intended flow: Streamlit → mediator → FDW sources → global view →
    verification → classification → reporting/analytics.
-   PostgreSQL and DBeaver are in use.
-   Vendor inventory concepts include `vendor_id`, `item_identifier`,
    `received_date`, `expiry_date`, and `vendor_distributor_id`.
-   The need for general verification logic, missing-vendor behavior,
    approval scenarios, expiry, schema matching, and noisy-data entity
    matching is known.
-   Phase 2 evaluation is scheduled for 21--23 October 2026.

## 13.2 In progress or uncertain

-   Exact global view and whether it contains the intended business
    logic.
-   Exact global/materialized view relationship.
-   Streamlit-to-mediator integration.
-   Final approval and expiry rules.
-   Identifier mapping and noisy matching.
-   Query performance.
-   PostgreSQL persistent startup and SQL logging.

## 13.3 Recommended immediate sequence

These are next-step recommendations based on the existing project plan,
not claims that the team already accepted this exact sequence.

1.  **Recover the authoritative SQL/code artifacts.** Collect current
    DDL and data scripts for manufacturer, distributor, vendor,
    mediator, FDW objects, global view, materialized view, and Streamlit
    app.\
    **Verify:** Keep a versioned copy; run scripts against a clean test
    environment or inspect existing definitions without destructive
    changes.

2.  **Write down the cross-source key mapping.** Explicitly define
    `item_code`, `item_identifier`, and `medicine_code`, including which
    fields represent the same concept and how the mapping is
    stored/derived.\
    **Verify:** A field-mapping table names each source field,
    semantics, and join rule.

3.  **Inspect the actual global view.** Confirm it uses general
    joins/filters and not hard-coded test IDs.\
    **Verify:** Run it for several known test identifiers and inspect
    its definition.

4.  **Define classification precedence.** Decide how missing vendor,
    missing manufacturer, unapproved supplier, inconsistent links,
    expiry, exact match, and fuzzy/ambiguous match interact.\
    **Verify:** A written rule table with one expected output per
    scenario. Missing vendor must not automatically mean counterfeit.

5.  **Implement/verify noisy-data entity matching for Phase 2.** Use a
    small known test set with exact matches, typos, substitutions, and
    ambiguous candidates. Select the algorithm only after inspecting
    actual identifier formats.\
    **Verify:** Show input, normalized value, candidates,
    score/rationale, and final classification in the GUI or query
    output.

6.  **Build a robust demonstration matrix.** Include at least one case
    each for genuine/consistent, suspicious/mismatched, expired,
    unapproved, vendor-not-found, and noisy/ambiguous match.\
    **Verify:** Save expected and actual outputs and ensure tests are
    not tied to one hard-coded ID.

7.  **Test the Streamlit end-to-end flow.** Enter item code → mediator
    query → global view → classification → readable history.\
    **Verify:** Repeat using multiple test IDs and an absent ID.

8.  **Investigate the 200-record performance issue.** Measure the same
    query and environment, capture query plans, check FDW
    pushdown/indexes, and compare regular and materialized view
    behavior.\
    **Verify:** Record baseline and post-change timings; do not claim
    improvement without measurements.

9.  **Resolve database startup and logging.** Determine the exact host
    OS and PostgreSQL service installation, then configure persistent
    startup and appropriate query/server logging.\
    **Verify:** Restart the machine/service as applicable and confirm
    the database returns without manual intervention; run a test query
    and confirm the relevant log is visible.

10. **Prepare the Phase 2 explanation/demo.** Be able to explain source
    schemas, schema matching, global view, FDW, classification logic,
    edge cases, and why noisy matches are not automatically trusted.\
    **Verify:** Run a random item/case selected by another team member,
    not just a rehearsed case.

## 13.4 Dependencies

-   Steps 2--5 depend on recovering current schemas and view SQL.
-   GUI testing depends on working DB connections and the
    mediator/global view.
-   Performance optimization depends on a reproducible baseline.
-   The Phase 2 demo depends on the test matrix and the noisy-matching
    behavior being demonstrable before 21--23 October 2026.

## 13.5 Risks

-   Evaluation deadline is close.
-   Missing authoritative SQL could cause the receiving LLM to
    reconstruct the wrong schema.
-   Treating item and medicine codes as interchangeable can create false
    matches.
-   Exact-match-only logic may fail the noisy-data requirement.
-   Cross-database joins may be slow.
-   Stale materialized data could produce a result inconsistent with the
    source DB.
-   Classification rules may conflict unless precedence is defined.

------------------------------------------------------------------------

# 14. OPEN QUESTIONS AND UNRESOLVED ISSUES

  ---------------------------------------------------------------------------------------------------------------------
  Question / issue                    Why it matters                 Known          Missing information  Can work
                                                                     information                         continue?
  ----------------------------------- ------------------------------ -------------- -------------------- --------------
  What is the authoritative schema    Determines joins, keys, and    Table names    Full DDL,            Only
  for each DB?                        verification logic.            and some       constraints, data    cautiously.
                                                                     fields are     types, indexes.      
                                                                     known.                              

  What exactly do `item_code`,        Prevents incorrect joins and   User           Canonical key and    Should resolve
  `item_identifier`, and              false results.                 explicitly     mapping table/rule.  before final
  `medicine_code` mean?                                              questioned                          matching.
                                                                     this                                
                                                                     distinction.                        

  What is the current global view     Determines actual integration  View discussed Full `CREATE VIEW`   No reliable
  SQL?                                behavior.                      repeatedly.    definition.          validation
                                                                                                         without it.

  Is there a materialized view?       Affects freshness and          Concept        Existence,           Yes, but
                                      performance.                   discussed.     definition, refresh  performance
                                                                                    strategy.            analysis
                                                                                                         incomplete.

  What are the exact                  Required for consistent        Labels known.  Predicates and       Only
  Genuine/Nakali/Suspicious/Expired   classification.                               precedence.          partially.
  rules?                                                                                                 

  Does missing vendor mean "vendor    Avoids confusing missing data  Expected       Exact UI/query       Yes, test it
  record not found" regardless of     with counterfeit evidence.     phrase         conditions.          explicitly.
  other sources?                                                     explicitly                          
                                                                     requested.                          

  What is the approval schema?        Needed for WXY/WXT/unapproved  Approval query Tables/columns and   Not until
                                      cases.                         discussions.   authorization        schema is
                                                                                    semantics.           recovered.

  Which noisy matching algorithm is   Phase 2 requirement.           Noisy entity   Algorithm,           Must be
  implemented/planned?                                               matching       threshold,           addressed
                                                                     required.      normalization,       urgently.
                                                                                    ambiguity handling.  

  Does Streamlit currently call the   End-to-end flow.               Architecture   Source code and test Unknown.
  mediator?                                                          says it        result.              
                                                                     should.                             

  What are exact FDW server/table     Needed to reproduce            FDW is the     DDL/configuration.   Need
  names and credentials setup?        integration.                   target.                             artifacts.

  Why are 200 records slow?           Could impair demo.             Reported       Query, plans,        Yes, after
                                                                     minutes.       environment, exact   baseline
                                                                                    timing.              capture.

  Why does PostgreSQL not stay        Affects reliability.           User reported  OS, install method,  Need
  running?                                                           repeated       service              environment
                                                                     startup and    status/error.        detail.
                                                                     failed                              
                                                                     attempted fix.                      

  How are SQL logs enabled/viewed?    Needed for debugging and       User asked     Logging              Yes.
                                      evidence.                      about logs.    configuration and    
                                                                                    desired log type.    

  Is Ministry reporting a real        Scope and compliance           Original brief Format, recipient    Can
  submission or a report-generation   implications.                  says report if workflow, API,       demonstrate
  demo?                                                              Nakali.        authorization.       report
                                                                                                         generation
                                                                                                         without live
                                                                                                         integration.

  Are test IDs WXY/WXT and ITEM...    Reproducible scenarios.        Strings        Final data and case  Yes, after
  final?                                                             appeared in    assignments.         validating
                                                                     discussions.                        database.

  Which OS hosts each DB?             Setup/performance/debugging.   Windows and    Exact                Needed for
                                                                     Linux were     topology/versions.   operations
                                                                     mentioned.                          fixes.
  ---------------------------------------------------------------------------------------------------------------------

------------------------------------------------------------------------

# 15. PROJECT-SPECIFIC WORKING PREFERENCES

Explicit preferences/corrections visible in the project history: - Give
**general logic**, not logic that only tests one item. - Test the
general logic through the **GUI**, not only a one-off SQL statement. -
Explain where schema matching happens and how `medicine_code` relates to
`item_code`; do not gloss over this distinction. - Explain concepts such
as global view versus materialized view in understandable terms. -
Provide practical SQL that can be pasted into DBeaver when the schema is
known. - Provide multiple IDs for each case so the system can be
demonstrated under random selection. - If a requested item is not in
vendor test data, the output should say **"vendor record not found."** -
The user asks how to inspect SQL logs and how database changes propagate
to the mediator/view. - The project team wants a clear explanation of
scope, innovation, and future users, not only implementation mechanics.

Collaboration guidance for the next LLM: - Be kind and patient; explain
the role of each DB/tool in plain language before giving commands. -
When giving SQL, label which database/connection it must run against. -
Prefer complete, internally consistent SQL blocks when explicitly
requested, but do not invent missing schema details. - Distinguish a
proposed query from a tested query. - For debugging, ask for the exact
error/schema only when it is not already available; do not repeatedly
ask about facts documented here. - Keep the academic demonstration
requirement in view, particularly noisy-data matching and random test
cases.

------------------------------------------------------------------------

# 16. CRITICAL CONTEXT THAT MUST NOT BE LOST

1.  **The core project is medicine authenticity verification through
    heterogeneous database integration**, not a generic fake-product
    classifier and not a vehicle-registration project. The professor
    used vehicle registration as an example of noisy matching; this
    project remains about medicines.
2.  The stated goal is: **"From heterogeneous data to intelligent,
    trustworthy and decision-centric integration."**
3.  The sources are designed independently and may have semantically
    shared values under different attribute names.
4.  The intended flow is specifically **Streamlit → Mediator Database
    (Member 4) → FDW → Manufacturer + Distributor + Vendor DBs → Global
    View → Verification → classification → Report + Analytics**.
5.  The user explicitly requested general logic and rejected a
    one-item-only test approach.
6.  The user explicitly asked where schema matching happens. It must be
    a visible, explainable part of the design.
7.  Do not conflate `medicine_code`, `item_code`, and `item_identifier`
    without an explicit mapping.
8.  "Vendor record not found" is an expected outcome for an item absent
    from vendor test data; it is not synonymous with "Nakali."
9.  The team has discussed approval cases, including sample codes `WXY`
    and `WXT`, and an unapproved vendor scenario. Exact approval
    table/column names are not recoverable here.
10. `vendor_inventory` fields discussed include `vendor_id`,
    `item_identifier`, `received_date`, `expiry_date`, and
    `vendor_distributor_id`.
11. Global view versus materialized view and SQL logs are topics the
    user has asked to understand; explain them in context of this
    project.
12. A performance problem was reported for 200 records (minutes), but no
    root cause or benchmark is confirmed.
13. PostgreSQL repeated startup is an unresolved issue; a previous
    suggested fix did not work for the user.
14. Phase 2 evaluation is **21--23 October 2026** and requires
    demonstrating data integration/entity matching under noisy data.
15. Never claim Ministry reporting is connected to a real endpoint
    unless the actual integration is inspected and verified.
16. Do not claim the entire codebase or final SQL was inspected: this
    handover is based on available conversation summaries and three text
    resources, not a repository dump.

------------------------------------------------------------------------

# 17. SOURCE AND EVIDENCE TRACKING

## 17.1 Directly inspected uploaded resources

-   **`Asli-or-Nakli.txt`**: Original project brief and stated goal.
-   **`pasted.txt`**: Architecture flow.
-   **`Pasted text.txt`**: The request for this handover, not
    implementation evidence.

## 17.2 Conversation-derived facts

-   **12 September 2026:** Phase 2 evaluation instructions summarized;
    noisy data/entity matching required; evaluation 21--23 October.
-   **11--16 September 2026:** DBeaver/PostgreSQL setup, vendor schema,
    distributor DB SQL, approval queries, `WXY`/`WXT`,
    global/materialized view, schema matching, vendor-not-found
    behavior, expiry, SQL logs, PostgreSQL startup, and performance
    discussions.
-   Dates are based on shared project conversation metadata and should
    be treated as conversation timestamps, not necessarily code-change
    dates.

## 17.3 Evidence categories

-   **Direct source:** Explicitly present in inspected text files or
    preserved SQL excerpt.
-   **Conversation summary:** Reported in available shared project
    conversation context; original full SQL/transcript may not be
    available here.
-   **Interpretation/recommendation:** Clearly labelled as such; must
    not be represented as a user-approved decision or implemented
    behavior.
-   **Unknown/unverified:** Not supported by the available evidence.

## 17.4 Conflicts or gaps

-   The original brief says manufacturer has a unique code, while later
    conversation asks why `medicine_code` and `item_code` both exist.
    This is not necessarily a contradiction, but the mapping is
    unresolved.
-   The architecture flow shows all four classifications, but the exact
    conditions for each are not documented.
-   Conversation summaries refer to SQL blocks previously provided, but
    the complete current DDL is not in the available source files. Do
    not recreate it from assumptions.
-   The item/distributor list excerpt is incomplete for `ITEM000210`; do
    not fill in a missing value.

------------------------------------------------------------------------

# 18. FINAL PROJECT HANDOVER SUMMARY

## 18.1 One-paragraph summary

"Asli-or-Nakli" is an academic project to help identify potentially fake
medicines at purchase time by integrating manufacturer, distributor, and
vendor data stored in independently designed databases. A user enters an
item code in a Streamlit GUI; a mediator PostgreSQL database accesses
the source databases through FDW, and a global view assembles the item's
history. Verification logic is intended to consider cross-source
consistency, supplier/approval relationships, procurement/received date,
expiry, and identifier matches, then return an outcome such as Genuine,
Nakali, Suspicious, Expired, or vendor record not found. The core
academic goal is heterogeneous integration that is intelligent,
trustworthy, and decision-centric, with noisy-data entity matching
required for Phase 2.

## 18.2 Concise technical overview

-   DBMS: PostgreSQL.
-   DB client: DBeaver.
-   GUI target: Streamlit.
-   Integration: PostgreSQL FDW through a mediator DB ("Member 4").
-   Query layer: Global view; materialized view has been discussed but
    its status is unknown.
-   Source domains: Manufacturer, Distributor, Vendor.
-   Important vendor inventory fields discussed: `vendor_id`,
    `item_identifier`, `received_date`, `expiry_date`,
    `vendor_distributor_id`.
-   Current major technical uncertainty: mapping `item_code` ↔
    `item_identifier` ↔ manufacturer `medicine_code`.
-   No confirmed external API or production deployment.

## 18.3 Current implementation status

The architecture and database concepts are established, and SQL/schema
work has been discussed and partially represented in conversation. The
full current schemas, view definitions, FDW setup, GUI source, and test
outputs are not available here. Treat the integration/classification as
unverified until the current artifacts are inspected and the end-to-end
flow is tested.

## 18.4 Most important decisions

-   Preserve multiple independent databases and integrate them.
-   Use a mediator and FDW.
-   Build a global view for unified history.
-   Implement general rather than item-hard-coded logic.
-   Explicitly support "vendor record not found."
-   Make schema matching and noisy entity resolution visible and
    testable.
-   Do not assume that an item code is the same as a medicine code.
-   Demonstrate varied cases through the GUI.

## 18.5 Immediate next steps

1.  Recover current SQL and app files.
2.  Document exact schema/identifier mappings.
3.  Inspect global view and materialized view.
4.  Specify classification rules and precedence.
5.  Implement/verify noisy matching and candidate handling.
6.  Test the full scenario matrix in the GUI.
7.  benchmark 200-record performance.
8.  Resolve PostgreSQL startup/logging issues.
9.  Prepare a random-case Phase 2 demonstration for 21--23 October 2026.

## 18.6 Top unresolved problems

-   Identifier semantics and schema matching.
-   Actual final SQL/schema/view definitions.
-   Exact verification/classification rules.
-   Noisy entity-matching implementation.
-   Slow 200-record execution.
-   PostgreSQL startup persistence.
-   SQL log visibility.
-   Actual Ministry reporting workflow.

## 18.7 Essential resources

-   `Asli-or-Nakli.txt` --- original project brief.
-   `pasted.txt` --- architecture flow.
-   Previous SQL conversations for `distributor_db`, vendor schema,
    approvals, and global view --- retrieve from the original project
    chat if possible.
-   Current database DDL and Streamlit app --- not included in the
    current handover resources; must be collected from the project
    workspace.

## 18.8 Key constraints

-   Academic evaluation is near.
-   Random selection means the system must not rely on one test ID.
-   Heterogeneous schemas and noisy matching are core, not cosmetic.
-   Missing data must be distinguished from counterfeit evidence.
-   No claims of successful testing without logs/results.
-   Do not include secrets in documentation.

## 18.9 Missing information

Full schemas, complete SQL, source code, exact database
versions/topology, exact view definitions, matching algorithm,
classification precedence, test outputs, setup commands, Ministry report
format, deployment, and final performance measurements.

## 18.10 Instructions for the receiving LLM

Read this document first. Continue from the existing
PostgreSQL/FDW/mediator/global-view design. Do not redesign or restart
the project unnecessarily. First request or inspect the current
DDL/view/app files if available, then make the identifier mapping and
noisy matching explicit. Preserve all known requirements and do not
invent schemas, test results, or implementation status.

------------------------------------------------------------------------

# 19. MASTER CONTINUATION PROMPT FOR THE NEW LLM

You are continuing an existing academic project called
**Asli-or-Nakli**, focused on identifying potentially fake medicines
during purchase by integrating heterogeneous manufacturer, distributor,
and vendor databases.

Treat the supplied Project Handover Document as the primary record of
context. Preserve its established requirements, decisions, unresolved
issues, and terminology. Do not ask the user to repeat information
already documented.

## Your operating rules

1.  Continue from the documented current state; do not restart or
    redesign the project without a clear reason.
2.  Keep the intended architecture in view: **Streamlit GUI → Mediator
    Database (Member 4) → PostgreSQL FDW →
    Manufacturer/Distributor/Vendor DBs → Global View → Verification
    Rules → Genuine/Nakali/Suspicious/Expired or vendor record not found
    → Reporting/Analytics**.
3.  Treat the full source schemas, current SQL, global-view definition,
    materialized-view definition, FDW setup, and Streamlit code as
    missing unless the user provides them or you can actually inspect
    them. Never pretend to have seen code that is not available.
4.  Do not conflate `item_code`, `item_identifier`, and `medicine_code`.
    First establish their semantics and the mapping across source
    databases.
5.  Keep schema matching and noisy-data entity resolution explicit.
    Phase 2 evaluation is scheduled for 21--23 October 2026 and expects
    integration/entity matching under noisy data. Exact-match-only
    behavior may be insufficient.
6.  Preserve the user's explicit requirement for general logic, not a
    query hard-coded for one item. Test through the GUI where possible
    and use multiple cases/IDs.
7.  "vendor record not found" is a required behavior for an absent
    vendor record. Do not equate missing vendor data with confirmed
    counterfeiting.
8.  Do not assume the Ministry of Consumer Affairs has a connected API.
    Distinguish generating a report from actually submitting it.
9.  Explain database roles, SQL, global versus materialized views, logs,
    and debugging in clear language. When giving SQL, state which
    database/connection it belongs in.
10. Distinguish facts, conversation-reported details, inferences,
    recommendations, and unknowns. Never invent code, test results,
    schemas, package versions, timings, or project status.
11. Explain proposed changes and trade-offs before consequential
    changes. Make incremental, verifiable progress, preserve working
    behavior, and check edge cases/regressions.
12. Avoid destructive operations. Inspect current definitions/data
    before recommending changes; ask for a backup or explicit approval
    before any destructive migration.
13. Keep a test matrix covering consistent/genuine-like data,
    noisy/mismatched identifiers, ambiguous candidates, missing vendor
    records, unapproved vendor/distributor, expired items, and source
    inconsistency.
14. The 200-record query was reported to take minutes; root cause is
    unknown. Measure and inspect before optimizing.
15. PostgreSQL startup persistence and SQL logging were unresolved in
    prior conversations. Do not repeat an unverified fix without first
    establishing the operating system, installation method, and exact
    symptoms.
16. Update the project handover when important requirements or decisions
    change.

## First response workflow

-   First, summarize your understanding of the current architecture and
    the top unresolved issue in a few sentences.
-   Then identify the next concrete action that can be taken without
    guessing. Prefer inspecting the current database schemas/view
    definitions and the Streamlit source, or ask the user to provide
    those artifacts if they are unavailable.
-   Ask only focused questions needed to avoid a consequential mistake.
-   Once the current artifacts are available, create a traceable plan,
    implement in small steps, and verify each step with real outputs.

The goal is to help complete and demonstrate the existing project
reliably, especially the heterogeneous integration and noisy-data
entity-matching requirements, without losing project history or
inventing details.
