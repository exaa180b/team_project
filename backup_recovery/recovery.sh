# Wipe tables, then load the last backup.
cd "$(dirname "$0")/.."
source .env

psql "$DATABASE_URL" -f tables/table_creation.sql
psql "$DATABASE_URL" -f backup_recovery/backup.sql

echo "Restore done"