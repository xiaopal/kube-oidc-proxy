# Usage
docker run -it --rm -p 80:80 \
-e OIDC_ISSUER='https://xxxxxxxxxxxx/xxxx' \
-e OIDC_CLIENT_ID=xxxxxxxxxx \
-e OIDC_CLIENT_SECRET=xxxxxxxxx \
-e OIDC_PUBLIC_KEY=PEM-XXXXXXXX \
-e PROXY_PASS=http://127.0.0.1:9090 \
-e SESSION_REDIS=172.17.0.2 \
xiaopal/kube-oidc-proxy:latest
