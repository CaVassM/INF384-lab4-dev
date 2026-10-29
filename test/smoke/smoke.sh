#!/usr/bin/env bash
# Verifica que la version desplegada responde antes de las pruebas de e2e.
set -euo pipefail

: "${BASE_URL:?BASE_URL no definida}"
url="${BASE_URL%/}"
intentos="${INTENTOS:-30}"

for i in $(seq 1 "$intentos"); do
  if salud="$(curl -fsS --max-time 10 "${url}/salud")"; then
    break
  fi
  if [ "$i" -eq "$intentos" ]; then
    echo "::error::/salud no responde"
    exit 1
  fi
  sleep 5
done
echo "salud: ${salud}"

if [ -n "${EXPECTED_COMMIT:-}" ]; then
  for i in $(seq 1 "$intentos"); do
    commit="$(curl -fsS --max-time 10 "${url}/version" | jq -r .commit)"
    if [ "$commit" = "$EXPECTED_COMMIT" ]; then
      break
    fi
    if [ "$i" -eq "$intentos" ]; then
      echo "::error::/version devuelve ${commit}, se esperaba ${EXPECTED_COMMIT}"
      exit 1
    fi
    sleep 5
  done
  echo "commit: ${commit}"
fi

saldo="$(curl -fsS --max-time 10 "${url}/saldo/ana")"
echo "$saldo" | jq -e '.usuario == "ana" and (.saldo | type == "number")' > /dev/null
echo "saldo: ${saldo}"
