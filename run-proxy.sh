#!/bin/bash

APACHE_ARGS="-DFOREGROUND"
export OIDC_DISCOVERY="${OIDC_DISCOVERY:-${OIDC_ISSUER:+${OIDC_ISSUER%/}/.well-known/openid-configuration}}"
export OIDC_SCOPE="${OIDC_SCOPE:-openid}"
export OIDC_REDIRECT_URI="${OIDC_REDIRECT_URI}"

export SERVER_NAME="${SERVER_NAME:-$HOSTNAME}"
export SESSION_NAME="${SESSION_NAME:-oidc-proxy-session}"
export SESSION_SECRET="${SESSION_SECRET:-$OIDC_CLIENT_SECRET}"
export SESSION_TIMEOUT="${SESSION_TIMEOUT:-3600}"

export PROXY_PASS="${PROXY_PASS%/}/"

[ ! -z "$OIDC_DISCOVERY" ] && \
    [ ! -z "$OIDC_CLIENT_ID" ] && \
    [ ! -z "$OIDC_CLIENT_SECRET" ] && \
    [ ! -z "$OIDC_REDIRECT_URI" ] || {
    echo 'OIDC_DISCOVERY, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET and OIDC_REDIRECT_URI required'
    exit 1
}
[ ! -z "$OIDC_SCOPE" ] || {
    echo 'OIDC_SCOPE required'
    exit 1
}
[ ! -z "$SESSION_NAME" ] && [ ! -z "$SESSION_SECRET" ] || {
    echo 'SESSION_NAME and SESSION_SECRET required'
    exit 1
}

[ ! -z "$PROXY_PASS" ] || {
    echo 'PROXY_PASS required'
    exit 1
}

[ ! -z "$SESSION_REDIS" ] && APACHE_ARGS="$APACHE_ARGS -DSESSION_REDIS"
[ ! -z "$SESSION_REDIS_AUTH" ] && APACHE_ARGS="$APACHE_ARGS -DSESSION_REDIS_AUTH"

mkdir -p /etc/kube-oidc-proxy && (
    PROXY_AUTH_LOCATIONS="${PROXY_AUTH_LOCATIONS:-/}"
    PROXY_PROTECT_RESOURCES="${PROXY_PROTECT_RESOURCES:-/api/}"
    PROXY_PUBLIC_LOCATIONS="${PROXY_PUBLIC_LOCATIONS:-/assets/,/static/,/favicon.ico}"

    [ ! -z "$PROXY_AUTH_LOCATIONS" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_AUTH_LOCATIONS" && \
    for LOCATION in "${LOCATIONS[@]}"; do
        [ ! -z "$LOCATION" ] && echo "
        <Location \"$LOCATION\">
          AuthType openid-connect
          Require valid-user
          OIDCUnAuthAction auth
        </Location>"
    done 
    [ ! -z "$PROXY_PROTECT_RESOURCES" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_PROTECT_RESOURCES" && \
    for LOCATION in "${LOCATIONS[@]}"; do
        [ ! -z "$LOCATION" ] && echo "
        <Location \"$LOCATION\">
          AuthType openid-connect
          Require valid-user
          OIDCUnAuthAction 401
        </Location>"
    done 
    [ ! -z "$PROXY_PUBLIC_LOCATIONS" ] && IFS=',; |:' read -ra LOCATIONS<<<"$PROXY_PUBLIC_LOCATIONS" && \
    for LOCATION in "${LOCATIONS[@]}"; do
        [ ! -z "$LOCATION" ] && echo "
        <Location \"$LOCATION\">
          AuthType none
          Require all granted
        </Location>"
    done )>/etc/kube-oidc-proxy/000_auth-locations.conf

export APACHE_RUN_USER=www-data
export APACHE_RUN_GROUP=www-data

export APACHE_RUN_DIR=/var/run/apache2
export APACHE_PID_FILE=$APACHE_RUN_DIR/apache2.pid
export APACHE_LOCK_DIR=/var/lock/apache2
export APACHE_LOG_DIR=/var/log/apache2
export LANG=C
export LANG

unset HOME
mkdir -p $APACHE_RUN_DIR $APACHE_LOCK_DIR $APACHE_LOG_DIR
rm -f /var/logs/apache2.pid && exec apache2 $APACHE_ARGS
