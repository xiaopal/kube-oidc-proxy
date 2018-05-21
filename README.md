1. 为 kubernetes-dashboard 提供 openid-connect 登录代理
2. 集中管理 session, 自动刷新过期的的 id-token (通过刷新 access-token 实现)

# Usage
```
docker run -it --rm -p 80:80 \
-e OIDC_ISSUER='https://xxxxxxxxxxxx/xxxx' \
-e OIDC_CLIENT_ID=xxxxxxxxxx \
-e OIDC_CLIENT_SECRET=xxxxxxxxx \
-e PROXY_PASS=http://127.0.0.1:9090 \
-e SESSION_REDIS=172.17.0.2 \
xiaopal/kube-oidc-proxy:latest
```

# Dev/Test
```
docker build -t kube-oidc-proxy:test .

docker run -it --rm --name kube-oidc-proxy --network host \
-e OIDC_ISSUER='https://xxxxxxxxxxxx/xxxx' \
-e OIDC_CLIENT_ID=xxxxxxxxxx \
-e OIDC_CLIENT_SECRET=xxxxxxxxx \
-e PROXY_PASS=http://127.0.0.1:8888 \
kube-oidc-proxy:test

```
