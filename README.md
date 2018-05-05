# Usage
docker run --rm -p 80:80 \
-e OIDC_ISSUER='https://xxxxxxxx/xxx/' \
-e OIDC_CLIENT_ID=xxxxxxxxxx \
-e OIDC_CLIENT_SECRET=xxxxxxxxx \
-e OIDC_REDIRECT_URI=http://expample/openid-connect \
-e PROXY_PASS=http://127.0.0.1:9090 \
xiaopal/kube-oidc-proxy:latest

touch 0505
