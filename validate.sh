#!/usr/bin/env bash
#
# Runs every recipe against a disposable SQL Server container to make sure the
# scripts in this repository actually execute.
#
# Usage: ./validate.sh

set -uo pipefail

CONTAINER="${CONTAINER:-sql-recipes-validate}"
PASSWORD="${MSSQL_SA_PASSWORD:-Validate_Recipes_2026}"
SQLCMD="/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${PASSWORD} -C"
STARTED_CONTAINER=0

cleanup() {
    if [ "${STARTED_CONTAINER}" -eq 1 ]; then
        docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

if ! docker ps --format '{{.Names}}' | grep -qx "${CONTAINER}"; then
    echo "Starting SQL Server container ${CONTAINER}"
    docker run -d --name "${CONTAINER}" \
        -e ACCEPT_EULA=Y \
        -e MSSQL_SA_PASSWORD="${PASSWORD}" \
        mcr.microsoft.com/mssql/server:2022-latest >/dev/null
    STARTED_CONTAINER=1

    echo -n "Waiting for SQL Server to accept connections"
    for _ in $(seq 1 60); do
        if docker exec "${CONTAINER}" ${SQLCMD} -Q "SELECT 1" >/dev/null 2>&1; then
            echo " ready"
            break
        fi
        echo -n "."
        sleep 2
    done
fi

run_script() {
    local file="$1"
    docker cp "${file}" "${CONTAINER}:/tmp/script.sql" >/dev/null
    docker exec "${CONTAINER}" ${SQLCMD} -i /tmp/script.sql 2>&1
}

echo "Applying schema and seed"
run_script setup/01-schema.sql >/dev/null
run_script setup/02-seed.sql >/dev/null

failures=0

while IFS= read -r script; do
    output="$(run_script "${script}")"

    if echo "${output}" | grep -qiE '^Msg [0-9]+|Incorrect syntax'; then
        echo "FAIL ${script}"
        echo "${output}" | grep -iE '^Msg [0-9]+|Incorrect syntax' | head -5
        failures=$((failures + 1))
    else
        echo "PASS ${script}"
    fi
done < <(find . -name '*.sql' -not -path './setup/*' | sort)

echo
if [ "${failures}" -gt 0 ]; then
    echo "${failures} script(s) failed."
    exit 1
fi

echo "All scripts executed successfully."
