# Aether

[Nox](https://github.com/mburakmmm/nox-lang) (≥ **1.26.0**) için NestJS esintili **API / backend** framework’ü.

Pythonic modüller; resmi DI modeli **closure injection** + provider **isim** kaydı; guard / pipe / interceptor / exception filter; typed DTO (format doğrulama); OpenAPI + Swagger UI; CORS / rate limit / metrics; WebSocket gateway (oda/broadcast); arka plan kuyrukları (stale reclaim + DLQ).

> [Nyx](https://github.com/mburakmmm/nyx)’ten bağımsızdır (Rails tarzı full-stack). HTTP API için Aether; HTML monolit için Nyx.

## Hızlı başlangıç

```sh
noxc fetch
AETHER_ENV=development noxc run examples/hello_api/main.nox
```

Örnek kod için [README.md](README.md) ve `examples/hello_api/`.

## Nox limitasyonları

Kanıtlı dil engelleri: [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md) — Nox tarafında geliştirme için referans.

## Lisans

MIT
