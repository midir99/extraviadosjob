#!/bin/bash
#
# This script uses extraviadoscli to scrap missing person posters from
# the official prosecutor office websites and then uses the API of
# extraviados.mx to upload them to its database.

set -Eeuo pipefail

EXTRAVIADOS_API_URL=https://extraviados.mx/api/v1

msg() {
  echo >&2 -e "${1-}"
}

count_mpps() {
    http --ignore-stdin --print b "$EXTRAVIADOS_API_URL/mpps/" po_post_url==$1 | jq '.count'
}

msg 'step 1: starting web scrapers...'

extraviadoscli mor-custom --approach pages --page-from 1 --page-to 2 > extraviados-list-mor-custom.json &
extraviadoscli mor-amber  --approach pages --page-from 1 --page-to 2 > extraviados-list-mor-amber.json &
wait

msg 'step 2: merging all JSON files obtained...'

EXTRAVIADOS_FILE=extraviados-full.json
python3 merge-json-lists.py extraviados-list-*.json > "$EXTRAVIADOS_FILE"

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
        jq --arg i "$i" '.[$i | tonumber]' "$EXTRAVIADOS_FILE" > mpp.json
        API_KEY=$(cat .API-KEY)
        http POST "$EXTRAVIADOS_API_URL/mpps/" "Authorization:Token $API_KEY" < mpp.json
    else
        MPP_NAME=$(jq -r --arg i "$i" '.[$i | tonumber].mp_name' "$EXTRAVIADOS_FILE")
        msg "ignoring: $MPP_NAME"
    fi
done

msg 'step 4: cleaning up...'

rm -f "$EXTRAVIADOS_FILE" extraviados-list-*.json mpp.json

exit 0
