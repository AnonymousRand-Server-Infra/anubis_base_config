#!/bin/sh

set -ex

[ -f $ANUBIS_POLICY_DEST_FILE.template ] \
    && envsubst < $ANUBIS_POLICY_DEST_FILE.template > $ANUBIS_POLICY_DEST_FILE

# the caller of this script must pass the original entrypoint as args, and this executes it
exec "$@"
