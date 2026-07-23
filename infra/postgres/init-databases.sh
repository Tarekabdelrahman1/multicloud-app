#!/bin/sh
set -eu
export PGPASSWORD="${POSTGRES_PASSWORD}"

until pg_isready -h postgres -U "${POSTGRES_USER}" -d postgres >/dev/null 2>&1; do
  sleep 1
done

for database in device_db inventory_db workflow_db notification_db audit_db; do
  exists="$(psql -h postgres -U "${POSTGRES_USER}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${database}'")"
  if [ "$exists" != "1" ]; then
    echo "Creating database: ${database}"
    psql -h postgres -U "${POSTGRES_USER}" -d postgres -v ON_ERROR_STOP=1 -c "CREATE DATABASE \"${database}\""
  else
    echo "Database already exists: ${database}"
  fi
done
