"""Connection settings for the mediator, shared by the GUI and the Phase 3 scripts.
Values can be overridden with environment variables (ASLI_DB_HOST, ASLI_DB_PASSWORD, ...)."""

import os

DB_CONFIG = {
    "host": os.environ.get("ASLI_DB_HOST", "localhost"),
    "port": os.environ.get("ASLI_DB_PORT", "5432"),
    "dbname": os.environ.get("ASLI_DB_NAME", "mediator_db"),
    "user": os.environ.get("ASLI_DB_USER", "postgres"),
    "password": os.environ.get("ASLI_DB_PASSWORD", "postgres"),
}
