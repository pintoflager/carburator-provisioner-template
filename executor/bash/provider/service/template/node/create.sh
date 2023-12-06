#!/usr/bin/env bash

carburator log info \
	"Invoking $PROVISIONER_SERVICE_PROVIDER_NAME $PROVISIONER_NAME server \
	node provisioner..."

resource="node"
resource_dir="$INVOCATION_PATH/$PROVISIONER_NAME"
data_dir="$PROVISIONER_PATH/providers/$PROVISIONER_SERVICE_PROVIDER_NAME"
templates_sourcedir="$data_dir/$resource"

# Resource data paths
node_out="$data_dir/$resource.json"

# This copies only files with the given extension
template_file_ext="cfg"

# Copy provider configuration files from 'templates' dir (don't overwrite existing)
# These files can be modified without risk of unwarned overwrite on package upgrade.
while read -r file; do
	target_file=$(basename "$file")
	cp -n "$file" "$resource_dir/$target_file"
done < <(find "$templates_sourcedir" -maxdepth 1 -iname "*.$template_file_ext")

# To copy the whole dir contents just do
# cp -rn "$templates_sourcedir"/* "$resource_dir"


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

# Get nodes json array service provider should of provided for us.
nodes=$(carburator get json nodes array-raw -p .exec.json)

if [[ -z $nodes ]]; then
	carburator log error "Could not load nodes array from .exec.json"
	exit 120
fi

# Implement provisioner execution...
provisioner_call() {
	echo "Run provisioner program with required information extracted from \$nodes..."
}

provisioner_call "$resource_dir" "$node_out"; exitcode=$?

if [[ $exitcode -eq 0 ]]; then
	carburator log success \
		"Server nodes created successfully with $PROVISIONER_NAME"

	len=$(carburator get json node.value array -p "$node_out" | wc -l)
	for (( i=0; i<len; i++ )); do
		# Pair the provisioned remote node with the local one. Depends on the
		# provisioner output how this should be done.
		node_uuid=$(carburator get json "node.$i.labels.uuid" string -p "$node_out")
		name=$(carburator get json "node.$i.name" string -p "$node_out")
		
		carburator log info \
			"Locking node '$name' provisioner to $PROVISIONER_NAME..."

		carburator node lock-provisioner "$PROVISIONER_NAME" --node-uuid "$node_uuid"

		# Lets assume IPv4 is a single address, not a block:
		#
		# We have to define the CIDR block we use.
		# register-block value could be suffixed with /32 as well but lets leave a
		# reminder how to use the --cidr flag.
		ipv4=$(carburator get json "node.$i.ipv4" string -p "$node_out")

		# Register block and extract first ip from it.
		if [[ -n $ipv4 && $ipv4 != null ]]; then
			carburator log info \
				"Extracting IPv4 address blocks from node '$name' IP..."

			address_block_uuid=$(carburator register net-block "$ipv4" \
				--extract \
				--ip "$ipv4" \
				--uuid \
				--provider "$PROVISIONER_SERVICE_PROVIDER_NAME" \
				--provisioner "$PROVISIONER_NAME" \
				--cidr 32) || exit 120

			# Point address to node.
			carburator node address \
				--node-uuid "$node_uuid" \
				--address-uuid "$address_block_uuid"
		fi

		# For IPv6 lets assume we receive a full block of addresses from the provider
		ipv6_block=$(carburator get json "node.$i.ipv6_block" string -p "$node_out")
		
		# Register block
		if [[ -n $ipv6_block && $ipv6_block != null ]]; then
			carburator log info \
				"Extracting IPv6 address blocks from node '$name' IP..."

			ipv6=$(carburator get json "node.$i.ipv6" string -p "$node_out")

			# This is the other way to handle the address block registration.
			# register-block value has /cidr.
			address_block_uuid=$(carburator register net-block "$ipv6_block" \
				--uuid \
				--extract \
				--provider "$PROVISIONER_SERVICE_PROVIDER_NAME" \
				--provisioner "$PROVISIONER_NAME" \
				--ip "$ipv6") || exit 120

			# Point address to node.
			carburator node address \
				--node-uuid "$node_uuid" \
				--address-uuid "$address_block_uuid" || exit 120
		fi
	done

	carburator log success "IP address blocks registered."
elif [[ $exitcode -eq 110 ]]; then
	carburator log error \
		"$PROVISIONER_NAME provisioner failed with exitcode $exitcode, allow retry..."
	exit 110
else
	carburator log error \
		"$PROVISIONER_NAME provisioner failed with exitcode $exitcode"
	exit 120
fi
