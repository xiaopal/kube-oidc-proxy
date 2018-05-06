#!/bin/bash

export OIDC_DISCOVERY="${OIDC_DISCOVERY:-${OIDC_ISSUER:+${OIDC_ISSUER%/}/.well-known/openid-configuration}}"
export PROXY_AUTH_LOCATIONS="${PROXY_AUTH_LOCATIONS:-/}"
export PROXY_PROTECT_RESOURCES="${PROXY_PROTECT_RESOURCES:-/api/}"
export PROXY_PUBLIC_LOCATIONS="${PROXY_PUBLIC_LOCATIONS:-/assets/,/static/,/favicon.ico}"
export PROXY_PASS="${PROXY_PASS%/}"

[ ! -z "$OIDC_DISCOVERY" ] && \
    [ ! -z "$OIDC_CLIENT_ID" ] && \
    [ ! -z "$OIDC_CLIENT_SECRET" ] || {
    echo 'OIDC_DISCOVERY, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET required'
    exit 1
}

[ ! -z "$PROXY_PASS" ] || {
    echo 'PROXY_PASS required'
    exit 1
}

mkdir -p /etc/kube-oidc-proxy && cat<<EOF >/etc/kube-oidc-proxy/global.inc
env OIDC_DISCOVERY;
env OIDC_CLIENT_ID;
env OIDC_CLIENT_SECRET;
env OIDC_PUBLIC_KEY;
env OIDC_SCOPE;
env OIDC_REDIRECT_PATH;
env OIDC_LOGOUT_PATH;

env SESSION_NAME;
env SESSION_SECRET;
env SESSION_TIMEOUT;
env SESSION_REDIS;
env SESSION_REDIS_PREFIX;
env SESSION_REDIS_AUTH;

env PROXY_PASS;

error_log  logs/error.log  debug;
EOF

( exec >/etc/kube-oidc-proxy/000_default.conf
sed -n '/nameserver/s/nameserver\(.*\)/resolver\1;/p' /etc/resolv.conf | head -1 
cat<<\EOF
    set_by_lua $proxy_pass 'return os.getenv("PROXY_PASS")';

    set_by_lua $session_name 'return os.getenv("SESSION_NAME") or "openid-session"';
    set_by_lua $session_secret 'return os.getenv("SESSION_SECRET") or os.getenv("OIDC_CLIENT_SECRET")';
    set_by_lua $session_storage 'return os.getenv("SESSION_REDIS") and "redis" or "cookie"';
    set_by_lua $session_redis_host '
        local redis = os.getenv("SESSION_REDIS") 
        return redis and redis:match("([^:]+):%d+") or redis';
    set_by_lua $session_redis_port '
        local redis=os.getenv("SESSION_REDIS") 
        return redis and redis:match("[^:]+:(%d+)") or 6379';
    set_by_lua $session_redis_prefix 'return os.getenv("SESSION_REDIS_PREFIX") or "openid-session"';

    set $oidc_action 'auth';
    access_by_lua_block {
        local opts = {
            scope = os.getenv("OIDC_SCOPE") or "openid",
            redirect_uri_path = os.getenv("OIDC_REDIRECT_PATH") or "/authorize",
            logout_path = os.getenv("OIDC_LOGOUT_PATH") or "/logout",
            discovery = os.getenv("OIDC_DISCOVERY"),
            client_id = os.getenv("OIDC_CLIENT_ID"),
            client_secret = os.getenv("OIDC_CLIENT_SECRET"),
            id_token_refresh_interval = 30,
EOF
[ ! -z "$OIDC_PUBLIC_KEY" ] && cat<<\EOF
            -- Try https://github.com/jpf/okta-jwks-to-pem 
            secret = os.getenv("OIDC_PUBLIC_KEY"),
EOF
cat<<\EOF
            session_contents = { id_token=true, enc_id_token=true, access_token=true }
        }
        if ngx.var.oidc_action ~= "pass" then
            local res, err, url, session = require("resty.openidc").authenticate(opts, nil, (ngx.var.oidc_action == "block") and "pass" or "")
            if err then
                ngx.log(ngx.ERR, err)            
                ngx.status = 500
                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
            if not session.data.enc_id_token then
                ngx.status = 401
                ngx.exit(ngx.HTTP_UNAUTHORIZED)
            end
            ngx.var.proxy_authorization = "Bearer " .. session.data.enc_id_token
        end
    }    
EOF
[ ! -z "$SESSION_REDIS_AUTH" ] && cat<<\EOF
    set_by_lua $session_redis_auth 'return os.getenv("SESSION_REDIS_AUTH")';
EOF

[ ! -z "$PROXY_AUTH_LOCATIONS" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_AUTH_LOCATIONS" && \
    for LOCATION in "${LOCATIONS[@]}"; do
        [ ! -z "$LOCATION" ] && echo "
        location $LOCATION {
            set \$oidc_action 'auth';
            proxy_pass \$proxy_pass;
        }"
    done 
[ ! -z "$PROXY_PROTECT_RESOURCES" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_PROTECT_RESOURCES" && \
    for LOCATION in "${LOCATIONS[@]}"; do
        [ ! -z "$LOCATION" ] && echo "
        location $LOCATION {
            set \$oidc_action 'block';
            proxy_pass \$proxy_pass;
        }"
    done 
[ ! -z "$PROXY_PUBLIC_LOCATIONS" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_PUBLIC_LOCATIONS" && \
    for LOCATION in "${LOCATIONS[@]}"; do
        [ ! -z "$LOCATION" ] && echo "
        location $LOCATION {
            set \$oidc_action 'pass';
            proxy_pass \$proxy_pass;
        }"
    done 
)

exec /usr/local/openresty/bin/openresty -g "daemon off;"
