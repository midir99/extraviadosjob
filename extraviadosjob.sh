#!/bin/bash
#
# This script uses extraviadoscli to scrap missing person posters from
# the official prosecutor office websites and then uses the API of
# extraviados.mx to upload them to its database.

set -Eeuo pipefail

msg() {
  echo >&2 -e "${1-}"
}

activate_venv() {
    if [ -n "$PYTHON_VENV" ]
    then
        . "${PYTHON_VENV}/bin/activate"
    fi
}

count_mpps() {
    http --ignore-stdin --print b "$EXTRAVIADOS_API_URL/mpps/" po_post_url==$1 | jq '.count'
}

clean_up() {
    trap - SIGINT SIGTERM ERR EXIT
    rm -rf "$TEMP_DIR"
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

. "${SCRIPT_DIR}/.config"
TEMP_DIR=$(mktemp -d extraviadosjob.XXXXX)
EXTRAVIADOS_FILE="${TEMP_DIR}/extraviados-full.json"

activate_venv

msg 'step 1: starting web scrapers...'

# Guerrero
extraviadoscli gro-amber  --approach pages --page-from "$PAGE_FROM" --page-to "$PAGE_TO" > "${TEMP_DIR}/extraviados-list-gro-amber.json" &
# Morelos
extraviadoscli mor-custom --approach pages --page-from "$PAGE_FROM" --page-to "$PAGE_TO" > "${TEMP_DIR}/extraviados-list-mor-custom.json" &
extraviadoscli mor-amber  --approach pages --page-from "$PAGE_FROM" --page-to "$PAGE_TO" > "${TEMP_DIR}/extraviados-list-mor-amber.json" &
wait

msg 'step 2: merging all JSON files obtained...'

python3 "${SCRIPT_DIR}/merge-json-lists.py" "${TEMP_DIR}"/extraviados-list-*.json > "$EXTRAVIADOS_FILE"

msg "step 3: creating new missing person posters in ${EXTRAVIADOS_API_URL}..."

MPPS_LEN=$(jq '. | length' "$EXTRAVIADOS_FILE")
for ((i=0; i<MPPS_LEN; i++))
do
    PO_POST_URL=$(jq -r --arg i "$i" '.[$i | tonumber].po_post_url' "$EXTRAVIADOS_FILE")
    COUNT=$(count_mpps $PO_POST_URL)
    if [ "$COUNT" -eq "0" ]
    then
        MPP_NAME=$(jq -r --arg i "$i" '.[$i | tonumber].mp_name' "$EXTRAVIADOS_FILE")
        msg "creating: $MPP_NAME"
        jq --arg i "$i" '.[$i | tonumber]' "$EXTRAVIADOS_FILE" > "${TEMP_DIR}/mpp.json"
        http POST "${EXTRAVIADOS_API_URL}/mpps/" "Authorization:Token $EXTRAVIADOS_API_KEY" < "${TEMP_DIR}/mpp.json"
    else
        MPP_NAME=$(jq -r --arg i "$i" '.[$i | tonumber].mp_name' "$EXTRAVIADOS_FILE")
        msg "ignoring: $MPP_NAME"
    fi
done

msg 'step 4: updating the counter last update date at extraviados.mx...'
http PUT "${EXTRAVIADOS_API_URL}/counter/updated_at/" "Authorization:Token $EXTRAVIADOS_API_KEY"

msg 'step 4: cleaning up...'

clean_up

exit 0
