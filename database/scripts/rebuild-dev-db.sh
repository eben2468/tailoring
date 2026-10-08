#!/usr/bin/env bash
# Drops and rebuilds the LOCAL DEVELOPMENT database: Laravel migrations (which run our SQL files)
# → reference seeds → demo seeds. Runs inside the nutofe-php container.
#
#   ./database/scripts/rebuild-dev-db.sh             # with demo data
#   SKIP_DEMO=1 ./database/scripts/rebuild-dev-db.sh
set -euo pipefail

run() { MSYS_NO_PATHCONV=1 docker exec -w /var/www/backend nutofe-php "$@"; }

run php artisan migrate:fresh --drop-views --seed
if [[ "${SKIP_DEMO:-0}" != "1" ]]; then
  run php artisan db:seed --class=DemoSeeder
fi
