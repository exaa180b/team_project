# Save a copy of the database rows.
cd "$(dirname "$0")/.."
source .env

pg_dump "$DATABASE_URL" --data-only --no-owner --no-acl -f backup_recovery/backup.sql

echo "Backup saved to backup_recovery/backup.sql"