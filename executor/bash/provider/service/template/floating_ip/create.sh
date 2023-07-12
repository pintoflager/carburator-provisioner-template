#!/usr/bin/env bash

carburator print terminal info \
	"Invoking $PROVISIONER_SERVICE_PROVIDER_NAME $PROVISIONER_NAME server \
	floating IP provisioner..."

tag=$(carburator get env IP_NAME -p .exec.env)
ipv4=$(carburator get env IP_V4 -p .exec.env || echo "false")
ipv6=$(carburator get env IP_V6 -p .exec.env || echo "false")

if [[ -z $tag ]]; then
    carburator print terminal error "Floating IP name missing from exec.env"
    exit 120
fi

if [[ $ipv4 == false && $ipv6 == false ]]; then
    carburator print terminal error \
        "Trying to create floating IP without defining IP protocol."
    exit 120
fi

resource="floating_ip"
resource_dir="$INVOCATION_PATH/${PROVISIONER_NAME}_$tag"
data_dir="$PROVISIONER_PATH/providers/$PROVISIONER_SERVICE_PROVIDER_NAME"
templates_sourcedir="$data_dir/$resource"

# Resource data paths
node_out="$data_dir/node.json"
fip_out="$data_dir/${resource}_$tag.json"

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
	carburator print terminal error \
		"Could not load $PROVISIONER_SERVICE_PROVIDER_NAME API token from secret. \
		Unable to proceed"
	exit 120
fi

# We should have list of nodes where we plan to pingpong this IP on.
nodes=$(carburator get json nodes array-raw -p .exec.json)

if [[ -z $nodes ]]; then
	carburator print terminal error "Could not load nodes array from .exec.json"
	exit 120
fi

# We should only connect nodes provisioned with our provisioner.
nodes_output=$(carburator get json node.value array-raw -p "$node_out")

if [[ -z $nodes_output ]]; then
	carburator print terminal error \
		"Could not load $PROVISIONER_NAME nodes array from $node_out"
	exit 120
fi

provisioner_call() {
	echo "Run provisioner program with required information extracted \
	from \$nodes_output..."
}

provisioner_call "$resource_dir" "$fip_out"; exitcode=$?

if [[ $exitcode -eq 0 ]]; then
	carburator print terminal success \
		"Floating IP address(es) created successfully with $PROVISIONER_NAME"

    # Check if IPv4 was provisioned. Assuming single address instead of a block.
    fip4=$(carburator get json floating_ip.ipv4.address \
        string -p "$fip_out")

    if [[ -n $fip4 ]]; then
        carburator print terminal info \
            "Extracting IPv4 address block from floating IP '$tag'..."
        
        v4_block_uuid=$(carburator register net-block "$fip4" \
            --extract \
            --ip "$fip4" \
            --uuid \
            --floating \
            --provider "$PROVISIONER_SERVICE_PROVIDER_NAME" \
			--provisioner "$PROVISIONER_NAME" \
            --cidr 32) || exit 120

        # Point address to node.
        v4_node_uuid=$(carburator get json floating_ip.ipv4.labels.primary \
            string -p "$fip_out")
        
        carburator node address \
            --node-uuid "$v4_node_uuid" \
            --address-uuid "$v4_block_uuid"

        carburator print terminal success "IPv4 address block registered."
    fi

	# Same as above but this time assuming we've received a full block of addresses.
    fip6=$(carburator get json floating_ip.ipv6.address \
        string -p "$fip_out")
    
    if [[ -n $fip6 ]]; then
        carburator print terminal info \
            "Extracting IPv6 address block from floating IP '$tag'..."
        
        block_v6=$(carburator get json floating_ip.ipv6.network_block \
            string -p "$fip_out")

        v6_block_uuid=$(carburator register net-block "$block_v6" \
            --extract \
            --ip "$fip6" \
            --uuid \
            --floating \
            --provider "$PROVISIONER_SERVICE_PROVIDER_NAME" \
			--provisioner "$PROVISIONER_NAME") || exit 120

        # Point address to node.
        v6_node_uuid=$(carburator get json floating_ip.ipv6.labels.primary \
            string -p "$fip_out")

        carburator node address \
            --node-uuid "$v6_node_uuid" \
            --address-uuid "$v6_block_uuid"

        carburator print terminal success "IPv6 address block registered."
    fi
elif [[ $exitcode -eq 110 ]]; then
	carburator print terminal error \
		"$PROVISIONER_NAME provisioner failed with exitcode $exitcode, allow retry..."
	exit 110
else
	carburator print terminal error \
		"$PROVISIONER_NAME provisioner failed with exitcode $exitcode"
	exit 120
fi
