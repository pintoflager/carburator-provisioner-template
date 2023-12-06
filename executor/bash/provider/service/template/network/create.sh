#!/usr/bin/env bash

carburator log info \
	"Invoking $PROVISIONER_SERVICE_PROVIDER_NAME $PROVISIONER_NAME server \
	network provisioner..."

resource="network"
resource_dir="$INVOCATION_PATH/$PROVISIONER_NAME"
data_dir="$PROVISIONER_PATH/providers/$PROVISIONER_SERVICE_PROVIDER_NAME"
templates_sourcedir="$data_dir/$resource"

# Resource data paths
network_out="$data_dir/$resource.json"
node_out="$data_dir/node.json"

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

# We should only connect nodes provisioned with our provisioner.
nodes_output=$(carburator get json node array-raw -p "$node_out")

if [[ -z $nodes_output ]]; then
	carburator log error \
		"Could not load $PROVISIONER_NAME nodes array from $node_out"
	exit 120
fi

provisioner_call() {
	echo "Run provisioner program with required information extracted \
	from \$nodes_output..."
}

provisioner_call "$resource_dir" "$network_out"; exitcode=$?

if [[ $exitcode -eq 0 ]]; then
	carburator log success \
		"Private network created successfully with $PROVISIONER_NAME"
else
	exit 110
fi

###
# Register node private network IP addresses to project
#
net_len=$(carburator get json network array --path "$network_out" | wc -l)
net_nodes_len=$(carburator get json node array --path "$network_out" | wc -l)
nodes_len=$(carburator get json node array -p "$node_out" | wc -l)

# Loop all networks created.
for (( a=0; a<net_len; a++ )); do
	block=$(carburator get json "network.$a.ip_range" string -p "$network_out")

	if [[ -z $block ]]; then
		carburator log error "Unable to read network range from '$network_out'"
		exit 120
	fi

	# Loop all nodes attached to private network.
	for (( i=0; i<net_nodes_len; i++ )); do
		# Find node uuid with help of the node id.
		net_node_id=$(carburator get json "node.$i.node_id" number -p "$network_out")

		if [[ -z $net_node_id ]]; then
			carburator log error "Unable to read node ID from '$network_out'"
			exit 120
		fi
		
		# Private network addresses are always ipv4
		ip=$(carburator get json "node.$i.ip" string -p "$network_out")

		if [[ -z $ip || $ip == null ]]; then
			carburator log error "Unable to find IP for node with ID '$net_node_id'"
			exit 120
		fi

		# Loop all nodes from node.json, find node uuid, add block and address.
		for (( g=0; g<nodes_len; g++ )); do
			node_id=$(carburator get json "node.$g.id" string -p "$node_out")

			# Not what we're looking for, next round please.
			if [[ $node_id != "$net_node_id" ]]; then continue; fi

			# Easiest way to locate the right node is with it's UUID
			node_uuid=$(carburator get json "node.$g.labels.uuid" string \
				-p "$node_out")

			# Register block and extract first (and the only) ip from it.
			net_uuid=$(carburator register net-block "$block" \
				--extract \
				--provider "$PROVISIONER_SERVICE_PROVIDER_NAME" \
				--provisioner "$PROVISIONER_NAME" \
				--ip "$ip" \
				--uuid); exitcode=$?

			if [[ $exitcode -gt 0 ]]; then
				carburator log error \
					"Unable to register network block '$block' and extract IP '$ip'"
				exit 120
			fi

			# Point address to node.
			carburator node address \
				--node-uuid "$node_uuid" \
				--address-uuid "$net_uuid"

			# Get the hell out of here and to the next network iteration.
			continue 2;
		done

		# We should be able to find all nodes, if not, well, shit.
		carburator log error "Unable to find node matching ID '$net_node_id'"
		exit 120
	done
done
