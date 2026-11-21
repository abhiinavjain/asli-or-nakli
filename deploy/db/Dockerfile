# Official PostgreSQL (dblink + postgres_fdw included) + the asli_match extension.
# Use the same major version as your source databases: SELECT version();
ARG PG_MAJOR=18
FROM postgres:${PG_MAJOR}
ARG PG_MAJOR
COPY phase2/step6_refactor/asli_match/asli_match.control \
     phase2/step6_refactor/asli_match/asli_match--1.0.sql \
     /usr/share/postgresql/${PG_MAJOR}/extension/
# the files must be readable by the postgres user, whatever their mode on the host
RUN chmod 644 /usr/share/postgresql/${PG_MAJOR}/extension/asli_match*
