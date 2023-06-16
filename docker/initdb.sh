#!/bin/bash

set -e

# Perform all actions as $POSTGRES_USER
export PGUSER="$POSTGRES_USER"

# Create the 'template_postgis' template db
"${psql[@]}" <<- 'EOSQL'
CREATE DATABASE template_postgis IS_TEMPLATE true;
EOSQL

echo "shared_preload_libraries = 'timescaledb'" >> /var/lib/postgresql/data/pgdata/postgresql.conf

# Load PostGIS into both template_database and $POSTGRES_DB
for DB in template_postgis "$POSTGRES_DB"; do
    echo "Loading PostGIS extensions into $DB"
    "${psql[@]}" --dbname="$DB" <<-'EOSQL'
        CREATE EXTENSION IF NOT EXISTS postgis;
        CREATE EXTENSION IF NOT EXISTS postgis_topology;
        CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
        CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder;
        CREATE EXTENSION IF NOT EXISTS pg_trgm;
        CREATE EXTENSION IF NOT EXISTS pgroonga;
        CREATE EXTENSION IF NOT EXISTS pg_jieba;
        CREATE EXTENSION IF NOT EXISTS timescaledb;
        CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
        CREATE EXTENSION IF NOT EXISTS pgcrypto;
EOSQL
done
