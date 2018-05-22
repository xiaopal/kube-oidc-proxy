#!/bin/bash

CONFIG_NAME="${OIDC_CONFIG:-oidc-auth}"
NGINX_CONFIG="${NGINX_CONFIG_PATH:-/etc/nginx}" && NGINX_CONFIG="${NGINX_CONFIG%/}"
SESSION_NAME="${OIDC_SESSION_NAME:-openid}"
SESSION_SECRET="$OIDC_SESSION_SECRET"
SESSION_REDIS="$OIDC_SESSION_REDIS"
SESSION_REDIS_PREFIX="$OIDC_SESSION_REDIS_PREFIX"
SESSION_REDIS_AUTH="$OIDC_SESSION_REDIS_AUTH"

config_session(){
    echo "config session: $SESSION_NAME" >&2
    local OIDC_DISCOVERY="${OIDC_DISCOVERY:-${OIDC_ISSUER:+${OIDC_ISSUER%/}/.well-known/openid-configuration}}"
    [ ! -z "$OIDC_DISCOVERY" ] && \
        [ ! -z "$OIDC_CLIENT_ID" ] && \
        [ ! -z "$OIDC_CLIENT_SECRET" ] || {
        echo 'OIDC_DISCOVERY, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET required' >&2
        return 1
    }
    local OIDC_PUBLIC_KEY="$OIDC_PUBLIC_KEY"
    [ -z "$OIDC_JWKS_PREFETCH" ] || [ ! -z "$OIDC_PUBLIC_KEY" ] || {
        local OIDC_DISCOVERY_CACHE="$(curl -sSL "$OIDC_DISCOVERY")" && [ ! -z "$OIDC_DISCOVERY_CACHE" ] || return 1
        local OIDC_JWKS_URI="$(jq -r '.jwks_uri//empty'<<<"$OIDC_DISCOVERY_CACHE")"
        # 使用 jwks2pem 工具预先导出为pem格式：openidc_v1.5.4.lua 的 openidc_pem_from_rsa_n_and_e 存在缺陷， 不能将jwks正确导出到pem  
        [ ! -z "$OIDC_JWKS_URI" ] && OIDC_PUBLIC_KEY="$(curl -sSL "$OIDC_JWKS_URI" | jwks2pem)" && \
        echo "loaded: $OIDC_JWKS_URI" >&2
    }
    [ ! -z "$SESSION_SECRET" ] || read -r SESSION_SECRET _< <(echo "$SESSION_NAME:$OIDC_CLIENT_ID:$OIDC_CLIENT_SECRET" | sha256sum)
    ( export SESSION_NAME SESSION_SECRET \
                SESSION_REDIS SESSION_REDIS_PREFIX SESSION_REDIS_AUTH \
                OIDC_CLIENT_ID OIDC_CLIENT_SECRET \
                OIDC_DISCOVERY OIDC_ISSUER OIDC_PUBLIC_KEY \
                OIDC_SCOPE OIDC_REDIRECT_PATH OIDC_LOGOUT_PATH; jq -n '{
        name: env.SESSION_NAME,
        scope: env.OIDC_SCOPE,
        redirect_path: env.OIDC_REDIRECT_PATH,
        logout_path: env.OIDC_LOGOUT_PATH,
        session_secret: env.SESSION_SECRET,
        discovery: env.OIDC_DISCOVERY,
        client_id: env.OIDC_CLIENT_ID,
        client_secret: env.OIDC_CLIENT_SECRET,
        public_key: env.OIDC_PUBLIC_KEY,
        session_redis: env.SESSION_REDIS,
        session_redis_auth: env.SESSION_REDIS_AUTH,
        session_redis_prefix: env.SESSION_REDIS_PREFIX
    } | with_entries(select( .value//"" | length>0 )) | [{key: .name, value:.}] | from_entries' ) >>"$NGINX_CONFIG/$CONFIG_NAME.sessions_"
}

rm -f "$NGINX_CONFIG/$CONFIG_NAME.sessions_"
[ -z "$OIDC_CLIENT_ID" ] || config_session || exit 1
OIDC_CONFIG_PATH="${OIDC_CONFIG_PATH:-/etc/$CONFIG_NAME}" && for CONFIG in ${OIDC_CONFIG_PATH//[ ;,:]/ }; do
    [ -d "$CONFIG" ] && for SESSION_CONF in "${CONFIG%/}"/*.conf; do
        [ -f "$SESSION_CONF" ] || continue
        ( SESSION_NAME="${SESSION_CONF%%.*}" && SESSION_NAME="${SESSION_NAME##*/}" && . "$SESSION_CONF" && config_session ) || exit 1
    done 
done
[ ! -f "$NGINX_CONFIG/$CONFIG_NAME.sessions_" ] || \
(jq -sc 'reduce .[] as $item ( {}; . * $item )' "$NGINX_CONFIG/$CONFIG_NAME.sessions_" >"$NGINX_CONFIG/$CONFIG_NAME.sessions" && rm -f "$NGINX_CONFIG/$CONFIG_NAME.sessions_") || exit 1    

cat<<EOF >"$NGINX_CONFIG/$CONFIG_NAME.http"
    init_by_lua_block {
        local cjson = require("cjson")
        oidc_sessions = cjson.decode($([ -f "$NGINX_CONFIG/$CONFIG_NAME.sessions" ] && jq -c 'tojson' "$NGINX_CONFIG/$CONFIG_NAME.sessions" || echo '"{}"'))
    }
EOF

cat<<\EOF >"$NGINX_CONFIG/$CONFIG_NAME.server"
    set $session_name '';
    set $session_secret '';
    set $session_storage '';
    set $session_redis_host '';
    set $session_redis_port '';
    set $session_redis_prefix '';
    set $session_redis_auth '';
    set $session_redis_host '';
    access_by_lua_block {
        local oidc_access = ngx.var.oidc_access
        if oidc_access and oidc_access ~= "" then
            local shared_cfg = oidc_sessions[oidc_access]
            if not shared_cfg then
                ngx.log(ngx.ERR, "session '" .. oidc_access .. "' not defined")            
                ngx.status = 500
                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
            local cjson = require("cjson")
            local cfg = {}
            for k,v in pairs(shared_cfg) do cfg[k] = v end
            local oidc_access_opts = ngx.var.oidc_access_opts
            if oidc_access_opts and oidc_access_opts ~= "" then
                for k,v in pairs(cjson.decode(oidc_access_opts)) do cfg[k] = v end
            end
            session_contents = {id_token=true, user=true}
            if cfg["enc_id_token"] then
                session_contents["enc_id_token"] = true
            end
            if cfg["id_token_refresh"] then
                session_contents["access_token"] = true
            end
            ngx.var.session_name = oidc_access .. "$session"
            ngx.var.session_secret = cfg["session_secret"] or cfg["client_secret"]
            ngx.var.session_storage = cfg["session_redis"] and "redis" or "cookie"
            local redis = cfg["session_redis"]
            ngx.var.session_redis_host = redis and redis:match("([^:]+):%d+") or redis or nil
            ngx.var.session_redis_port = redis and redis:match("[^:]+:(%d+)") or 6379
            ngx.var.session_redis_prefix = cfg["session_redis_prefix"] or ("sessions:" .. oidc_access)
            ngx.var.session_redis_auth = cfg["session_redis_auth"] or nil

            local opts = {
                scope = cfg["scope"] or "openid",
                redirect_uri_path = cfg["redirect_path"] or "/openid-connect",
                logout_path = cfg["logout_path"] or "/logout",
                discovery = cfg["discovery"],
                client_id = cfg["client_id"],
                client_secret = cfg["client_secret"],
                session_contents = session_contents
            }
            if cfg["public_key"] then
                opts["secret"] = cfg["public_key"]
            end
            if cfg["id_token_refresh"] then
                opts["id_token_refresh"] = cfg["id_token_refresh"]
                if cfg["id_token_refresh_interval"] then
                    opts["id_token_refresh_interval"] = cfg["id_token_refresh_interval"]
                end
            end

            local action = ngx.var.oidc_access_action or "auth"
            -- action aliases
            action = (action == "allow" or action == "ignore") and "pass" or action
            action = (action == "block") and "deny" or action
            local res, err, url, session = require("resty.openidc").authenticate(opts, nil, (action == "pass" or action == "deny") and "pass")
            if err then
                ngx.log(ngx.ERR, err)            
                ngx.status = 500
                ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
            end
            local claims = res and {}
            if claims then
                if res["user"] then
                    for k,v in pairs(res["user"]) do claims[k] = v end
                end
                if res["id_token"] then
                    for k,v in pairs(res["id_token"]) do claims[k] = v end
                end
                if session.data["enc_id_token"] then
                    claims["enc_id_token"] = session.data["enc_id_token"]
                    claims["bearer_enc_id_token"] = "Bearer " .. session.data["enc_id_token"]
                end
            end

            if claims and cfg["enc_id_token"] and not claims["enc_id_token"] then
                claims = nil
            end
            if not claims and (action ~= "pass") then
                ngx.status = 401
                ngx.exit(ngx.HTTP_UNAUTHORIZED)
            end

            for name,claim in pairs(cfg["claim_vars"] or {}) do
                ngx.var[name] = claims and claims[claim]
            end
            for name,claim in pairs(cfg["claim_headers"] or {}) do
                ngx.req.set_header(name, claims and claims[claim])
            end
        end
    }    
EOF

[ -z "$1" ] || { echo "$*" >&2 && exec "$@"; }