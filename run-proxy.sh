#!/bin/bash

export PROXY_AUTH_LOCATIONS="${PROXY_AUTH_LOCATIONS:-/}"
export PROXY_PROTECT_RESOURCES="${PROXY_PROTECT_RESOURCES:-/api/}"
export PROXY_PUBLIC_LOCATIONS="${PROXY_PUBLIC_LOCATIONS:-/assets/,/static/,/favicon.ico}"
export PROXY_PASS="${PROXY_PASS%/}"

( exec >/etc/kube-oidc-proxy.locations
    cat <<EOF
        $(sed -n '/nameserver/s/nameserver\(.*\)/resolver\1;/p' /etc/resolv.conf | head -1)
        set \$oidc_access '${OIDC_SESSION_NAME:-openid}';
        set \$oidc_access_opts '{
            "id_token_refresh": true,
            "enc_id_token" : true,
            "claim_headers": { "Authorization": "bearer_enc_id_token" }
        }';
EOF
    [ ! -z "$PROXY_AUTH_LOCATIONS" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_AUTH_LOCATIONS" && \
        for LOCATION in "${LOCATIONS[@]}"; do
            [ ! -z "$LOCATION" ] && echo "
        location $LOCATION {
            set \$oidc_access_action 'auth';
            proxy_pass $PROXY_PASS;
        }"
        done 
    [ ! -z "$PROXY_PROTECT_RESOURCES" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_PROTECT_RESOURCES" && \
        for LOCATION in "${LOCATIONS[@]}"; do
            [ ! -z "$LOCATION" ] && echo "
        location $LOCATION {
            set \$oidc_access_action 'deny';
            proxy_pass $PROXY_PASS;
        }"
        done 
    [ ! -z "$PROXY_PUBLIC_LOCATIONS" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_PUBLIC_LOCATIONS" && \
        for LOCATION in "${LOCATIONS[@]}"; do
            [ ! -z "$LOCATION" ] && echo "
        location $LOCATION {
            set \$oidc_access '';
            proxy_pass $PROXY_PASS;
        }"
        done 
) && cat /etc/kube-oidc-proxy.locations >&2
NGINX_CONFIG_PATH="/etc" \
OIDC_CONFIG="kube-oidc-proxy" \
OIDC_JWKS_PREFETCH='Y' \
exec /setup.sh /usr/local/openresty/bin/openresty -g "daemon off;"