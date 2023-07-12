#!/usr/bin/env bash

# To prevent unwanted behaviour in case of a bad package config.
if [[ $1 == "server" ]]; then
    carburator print terminal error \
        "Provisioners register only on client nodes. Package configuration error."
    exit 120
fi

if ! carburator has program "$PROVISIONER_NAME"; then
    carburator print terminal warn "Missing $PROVISIONER_NAME on client machine."

    carburator prompt yes-no \
        "Should we try to install $PROVISIONER_NAME?" \
        --yes-val "Yes try to install with a script" \
        --no-val "No, I'll install everything"; exitcode=$?

    if [[ $exitcode -ne 0 ]]; then
        exit 120
    fi
else
    carburator print terminal success "$PROVISIONER_NAME found from the client"
    exit 0
fi

carburator print terminal warn \
  "Missing required program $PROVISIONER_NAME. Trying to install it before proceeding..."

# Try to install provisioner program on localhost...
