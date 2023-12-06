#!/usr/bin/env bash

carburator log info "Invoking $PROVISIONER_NAME project provisioner..."

###
# Registers project and adds ssh key for project root.
#
resource="project"
resource_dir="$INVOCATION_PATH/$PROVISIONER_NAME"
data_dir="$PROVISIONER_PATH/providers/$PROVISIONER_SERVICE_PROVIDER_NAME"
templates_sourcedir="$data_dir/$resource"

# Resource data paths
# shellcheck disable=SC2034
project_out="$data_dir/$resource.json"
template_file_ext="cfg"

# Copy provider configuration files from 'templates' dir (don't overwrite existing)
# These files can be modified without risk of unwarned overwrite on package upgrade.
while read -r file; do
	# This copies only files with the given extension
	target_file=$(basename "$file")
	cp -n "$file" "$resource_dir/$target_file"
done < <(find "$templates_sourcedir" -maxdepth 1 -iname "*.$template_file_ext")

###
# Get API token from secrets or bail early.
#
token=$(carburator get secret "$PROVISIONER_SERVICE_PROVIDER_SECRETS_0" --user root)
exitcode=$?

if [[ -z $token || $exitcode -gt 0 ]]; then
	carburator log error \
		"Could not load $PROVISIONER_SERVICE_PROVIDER_NAME API token from secret. \
		Unable to proceed"
	exit 120
fi

# Execute provisioner program writing output to "project_out" file...