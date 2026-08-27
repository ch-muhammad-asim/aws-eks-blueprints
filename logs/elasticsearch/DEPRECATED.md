# ⚠️ Deprecated — Bitnami Elasticsearch chart

This vendored chart **cannot be deployed**. Every container image it references
has been withdrawn from Docker Hub (verified 2026-08-27):

```
docker.io/bitnami/elasticsearch:8.6.2-debian-11-r10   -> 404
docker.io/bitnami/kibana:7.17.8                       -> 404
docker.io/bitnami/bitnami-shell:11-debian-11-r97      -> 404
```

Bitnami restructured its catalogue in August 2025: most images moved to the paid
Bitnami Secure Images, and the free tier moved to a frozen `bitnamilegacy/*`
namespace that receives no security patches.

Elasticsearch 7.17 and 8.6 are also both end of life.

## ✅ Use this instead

[`../eck/`](../eck/) — Elasticsearch 9.1.2 and Kibana 9.1.2 on the ECK operator,
deployed and verified on this cluster.

This directory is kept only so the previous configuration remains readable.
