# Asli-or-Nakli: handoff for the deployment / DevOps project

Paste or upload this file at the start of the new project or chat. It holds everything needed to continue.

## 1. Who I am and what I want

- I'm a student at IIIT Delhi. I built **Asli-or-Nakli** (fake-medicine verification) as a team course project for IIA (Information Integration). The course is finished, and I'm now the **sole owner** of all the code and databases.
- **Goal now:** deploy it properly on **AWS** and use it as a **DevOps portfolio project** for DevOps / cloud job applications. I want to learn real practices along the way: Docker, IaC, CI/CD, monitoring, backups and security, not just "get it online".
- I've just created an AWS account (new account, so it's on the 2025+ credit-based Free Tier).

## 2. What the application is

A buyer or pharmacist checks a medicine (item code, pack details, bill, or a free-text question). The system integrates **4 PostgreSQL databases** and answers with a verdict: genuine / counterfeit / expired / substandard batch / transport damage / and so on, with evidence.

| Database | Role |
|---|---|
| `manuf_db` (was `manufacturer_db`) | medicines, manufactured items, plants, production batches, QC reports (7 tables) |
| `distributor_db` | inventory, supplied items, warehouses, shipments, shipment lines, temperature logs (7 tables) |
| `vendor_db` | vendor inventory, sales, purchase invoices, customers, complaints (8 tables) |
| `mediator_db` | integration layer: no copies of source data; queries the sources live |

- **Phase 1:** a mediator built on `postgres_fdw` with foreign servers `manufacturer_server`, `distributor_server` and `vendor_server`, plus verification rules (`verify_item`).
- **Phase 2:** entity matching on noisy data and cleansing, written in SQL. Uses a custom extension **`asli_match`** (schema `asli`: `fold`, `keys`, `dist`, `name_key`, `month_key`, `parse_date`), which is **plain SQL (a `.control` file plus `asli_match--1.0.sql`), not C**. It must be installed on all 4 databases. The mediator's foreign servers use the option `extensions 'asli_match'` so the functions are pushed down to the sources. Each source returns its top-k candidates (`asli_probe`, registry table `asli_sources`).
- **Phase 3:** unstructured data plus federated context.
  - The mediator sends `asli_ctx.discover(...)` to each source in parallel with **`dblink` async calls** (`dblink_connect(conn, <foreign server name>)`, so dblink reuses the same foreign servers and user mappings). Each source walks its own FK graph and returns related rows.
  - A second round follows cross-database keys (`p3_links`).
  - Hybrid document search runs over 22 documents (`p3_search_documents`: full-text plus embeddings (LSA, or sentence-transformers if installed) plus an entity bonus).
  - An optional LLM answer is written by Claude when `ANTHROPIC_API_KEY` is set; otherwise a rule-based answer is used.
  - Endpoints are in `p3_endpoints` (column `server_name`), and the call audit is in `p3_source_calls`.
- **GUI:** Streamlit, `phase3/app/gui.py`. Python dependencies: streamlit, psycopg2-binary, pandas, scikit-learn, joblib (and optionally anthropic and sentence-transformers). DB settings come from `phase3/app/asli_db.py` and the environment variables `ASLI_DB_HOST`, `ASLI_DB_PORT`, `ASLI_DB_NAME` (default `mediator_db`), `ASLI_DB_USER` and `ASLI_DB_PASSWORD`.
- **Document indexer:** `phase3/app/phase3_index_documents.py`. It stores vectors in the mediator, so a restored dump already contains them. Re-run it only when `phase3/corpus/documents.json` changes.

Repository layout (I'll upload it to the new project):
```
phase1/ ...  phase2/ (step3..step6_refactor, asli_match/, live_noise/, data_v2/)
phase3/ (sources/, mediator/, app/, corpus/, prompts/, demo_check/, README.md)
deploy/ (the kit below)
```

## 3. Current state of the databases

- Originally the system ran on 4 laptops (manufacturer on Linux, the others in WSL) over LAN.
- **Now all 4 databases are on my one machine** (probably one PostgreSQL instance, with the foreign servers pointing at localhost or that machine).
- The deploy kit doesn't depend on that: it restores each database from a `pg_dump` into **its own container** and re-points the foreign servers at the container names. The federation stays real: separate Postgres servers talking over a network.

## 4. Deployment decision so far

**Target architecture (stage 1):** one EC2 instance running Docker Compose with
- 4 Postgres containers (`manufacturer`, `distributor`, `vendor`, `mediator`), built from `postgres:<PG_MAJOR>` with `asli_match` copied into the extension directory (`dblink` and `postgres_fdw` ship with the image);
- an `app` container (python:3.11-slim plus Streamlit, port 8501, internal only);
- a `caddy` container: automatic HTTPS for my domain plus `basic_auth` (Streamlit has no login, and a public link must not burn my Anthropic credits).

Only ports 80 and 443 are published. The databases are never exposed.

Why not managed Postgres (RDS / Supabase / Neon)? I can't drop extension files into them, so `CREATE EXTENSION asli_match` fails, and the postgres_fdw `extensions` pushdown option needs a real extension. RDS does support `dblink` and `postgres_fdw` themselves. Moving to RDS would mean installing `asli_match` as a plain schema script and dropping the pushdown option, which is a possible later experiment, not stage 1.

### The kit (`deploy/`)

| File | What it does |
|---|---|
| `docker-compose.yml` | the 6 services, named volumes per DB, healthchecks, `./dumps` mounted read-only |
| `db/Dockerfile` | `FROM postgres:${PG_MAJOR}` + copies `phase2/step6_refactor/asli_match/{asli_match.control, asli_match--1.0.sql}` |
| `app/Dockerfile` | installs `phase3/app/requirements.txt` + `anthropic`, runs `streamlit run gui.py` headless on 0.0.0.0:8501 |
| `Caddyfile` | `{$DOMAIN}` → `basic_auth` → `reverse_proxy app:8501` |
| `.env.example` | `PG_MAJOR`, `PG_PASSWORD`, `DOMAIN`, `SITE_USER`, `SITE_PASSWORD_HASH` (`$` written as `$$`), `ANTHROPIC_API_KEY` |
| `restore.sh` | starts the DBs, `pg_restore`s `dumps/<db>_db.dump` (sources first, mediator last), runs `repoint.sql`, then starts app + caddy |
| `repoint.sql` | on `mediator_db`: sets `host`/`port`/`dbname` on the 3 foreign servers to the container names, and `user`/`password` on their user mappings; then checks `asli_probe('ITEM000001')` returns all 3 kinds |

Status (21 Nov 2026): kit lives at `~/IIITD Mtech/Major Project/asli/` (phase2/ + phase3/ + deploy/). Tested locally on the laptop (Kubuntu, Docker, **PostgreSQL 18**, so `PG_MAJOR=18`):
- all 4 DB containers build and come up healthy; `manuf_db` restores cleanly with `asli_match`.
- fixes made on the way: volumes mount at `/var/lib/postgresql` (required by the postgres:18 image); `db/Dockerfile` runs `chmod 644` on the extension files; `repoint.sql` no longer prints the password and renames the `manufacturer_db` label inside the mediator's cleansing functions/rows to `manuf_db`.
- **Blocked on dumps:** only `manufacturer_db` exists on this laptop. `distributor_db`, `vendor_db`, `mediator_db` must be dumped from wherever they live (old Phase-1-only `.sql` dumps from Sept are in `IIA/Project 2/` as a fallback for testing).

Making the dumps (on my machine):
```bash
pg_dump -U postgres -Fc -d manufacturer_db -f manuf_db.dump   # local name may still be manufacturer_db
for db in distributor vendor mediator; do pg_dump -U postgres -Fc -d ${db}_db -f ${db}_db.dump; done
SELECT version();   -- use the same major version as PG_MAJOR
```

## 5. AWS facts to respect (checked Nov 2026)

- New accounts (since 15 Jul 2025) get **$100 in credits plus up to $100 more** for completing activities.
- A **Free plan** account ends after **6 months or when the credits run out**, whichever comes first. AWS then closes the account (90 days to upgrade before deletion). Upgrading to the Paid plan keeps the remaining credits until they expire.
- Things that drain credits fast: NAT gateways, EKS clusters (charged per cluster-hour), idle Elastic IPs and public IPv4 addresses, oversized instances, forgotten snapshots. Set up AWS Budgets alerts on day 1.
- Planned region: `ap-south-1` (Mumbai).

## 6. DevOps roadmap (each stage = something to show on the resume)

0. **Account hygiene:** MFA on root, an admin IAM Identity Center or IAM user (never use root keys), budget alerts, billing alarm.
1. **Manual deploy:** EC2 (t4g.small or t3.small, 20 GB gp3), security group (22 from my IP only, 80, 443), Elastic IP, DuckDNS or Route 53 domain, install Docker, run `restore.sh`.
2. **Infrastructure as Code:** rebuild stage 1 with **Terraform** (VPC, subnet, SG, EC2, EIP, IAM instance role, `user_data`/cloud-init that installs Docker and starts the stack), with remote state in S3. Goal: `terraform destroy` then `apply` brings everything back.
3. **CI/CD:** GitHub repo plus **GitHub Actions**: build the images, run a smoke test (bring up the compose stack in CI with small dumps; run the `phase3/demo_check/*_smoke_test.sql` checks), push to **ECR** using **OIDC** (no long-lived keys), deploy via **SSM Run Command**.
4. **Operations:** nightly `pg_dump` to **S3** with lifecycle rules plus a tested restore; **CloudWatch** agent (logs, disk and memory alarms); **SSM Session Manager** instead of SSH; secrets in **SSM Parameter Store** instead of `.env`.
5. **Optional, containers at scale:** k3s on the instance with a Helm chart, Prometheus and Grafana; or the app on ECS Fargate. Avoid EKS on credits.

## 7. Where to start in the new chat

1. Check the AWS account basics (stage 0).
2. Make the 4 dumps and test the kit locally with `docker compose` on my machine (fastest place to fix restore errors).
3. Then stage 1 on EC2.
