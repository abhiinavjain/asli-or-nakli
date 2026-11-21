# Asli-or-Nakli — fake-medicine verification over 4 federated PostgreSQL databases

A buyer or pharmacist checks a medicine (item code, pack details, bill or a free-text question).
The mediator queries the manufacturer, distributor and vendor databases live (postgres_fdw + dblink)
and answers genuine / counterfeit / expired / substandard batch / transport damage, with evidence.

## Repository layout

| Folder | What it holds |
|---|---|
| `deploy/` | **How it runs:** Docker Compose (4 Postgres + Streamlit app + Caddy HTTPS/login), `restore.sh`, `repoint.sql`, `CONTEXT.md` (full handover) |
| `phase1_base/` | Original Phase 1 database dumps and handover notes (historical) |
| `phase2/` | Matching and cleansing in SQL: steps 1–6, `asli_match` extension (`step6_refactor/asli_match/`), `data_v2/` test cases, `data_v2_rebuilt/` (current data generator), `live_noise/` |
| `phase3/` | Federated context discovery, documents + hybrid search, Streamlit GUI (`app/`), smoke tests (`demo_check/`) |

`phase3/app/models/asli_lsa.joblib` is the embedding model that matches the document vectors in the
mediator dump. If you change `phase3/corpus/documents.json`, re-run `phase3/app/phase3_index_documents.py`
(it rewrites both the vectors and this file).

## Run it (Docker)

```bash
cd deploy
cp .env.example .env          # fill in (PG_MAJOR=18, passwords, DOMAIN, site login hash)
# put manuf_db.dump, distributor_db.dump, vendor_db.dump, mediator_db.dump in deploy/dumps/
bash restore.sh               # builds images, restores dumps, re-points the federation, starts app + Caddy
```
Open `https://<DOMAIN>` (or `https://localhost`) and log in with the site user.

Only ports 80/443 are published; the databases are reachable only inside the Docker network.
