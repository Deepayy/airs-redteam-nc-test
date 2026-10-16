The script 'nc_check.sh' walks through the same steps your proxy will perform against the Palo Alto registry, without needing a cluster. It confirms the registry credentials are accepted, logs in with Helm, pulls the panw-network-client chart, lists the container images the chart references (these are the image paths you’ll need to proxy as well as the chart), checks those images are reachable, and does a client-side dry run of the pull secret. It installs nothing and touches no cluster.

It needs helm and curl on the machine; docker and kubectl are used if present and skipped if not. Set the two credentials as environment variables and run it. These are the network channel username and password from the Network Channels page in Strata Cloud Manager, not the service account client ID and secret, which are only used later by helm install.

export NC_USER='<network channel username>'
export NC_PASS='<network channel password>'
bash nc_check.sh

The registry hostname, chart path and chart version are already set inside the script to the values for your tenant (registry-nl, the charts-nl path and version 1.5.0), so nothing else needs changing. If you ever need to override them, NC_REG, NC_CHART and NC_VER are the variable names.

Each step prints PASS or FAIL with a reason. A FAIL at step 1 is the credentials or egress to the registry; a FAIL at step 5 means the image path needs adding to your Docker proxy. If all six pass, the registry side is fine
