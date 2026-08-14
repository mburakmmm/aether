# Aether

[English](README.md) · [Türkçe](README.tr.md)

**[Nox](https://github.com/mburakmmm/nox-lang) için NestJS esintili API / backend framework’ü.**  
Pythonic modüller, closure tabanlı DI, guard / pipe / interceptor, typed DTO, OpenAPI + Swagger UI, WebSocket gateway ve SQLite iş kuyrukları.

**Sürüm:** 0.6.3 · **Lisans:** MIT · **Nox ≥ 1.29.8**  
Paket: `aether` · Repo: [github.com/mburakmmm/aether](https://github.com/mburakmmm/aether)

> [Nyx](https://github.com/mburakmmm/nyx)’ten bağımsızdır (Rails tarzı full-stack). HTTP API için **Aether**; HTML monolit için **Nyx**.

---

## Kurulum (Nox paketi)

Uygulama `nox.json`:

```json
{
  "name": "myapi",
  "entry": "main.nox",
  "requires": [
    {
      "alias": "aether",
      "repo": "github.com/mburakmmm/aether",
      "ref": "v0.6.3"
    }
  ]
}
```

```sh
noxc fetch
AETHER_ENV=development AETHER_WORKERS=1 NOX_POOL_WORKERS=1 noxc run main.nox
```

### Yerel path (geliştirme)

```json
{ "alias": "aether", "repo": "/absolute/path/to/aether", "ref": "master" }
```

### CLI iskelet

```sh
noxc install github.com/mburakmmm/aether@v0.6.3
aether new myapi
cd myapi && noxc fetch && chmod +x run.sh && ./run.sh
```

---

## 0.6.3

Nox ≥ 1.29.8. `workers>1` → `serve_multicore`. `AETHER_LLVM` kaldırıldı.
1.29.8 decode arena + Aether G2 path (ValidatedBody / flat validate / encode).
Echo ≈ Gin.

## 0.6.2

Nox ≥ 1.29.4. `--release` tek `serve()` (`AETHER_LLVM=1`); QBE `workers>1`
`serve_multicore` (SO_REUSEPORT). 0.6.3 / Nox 1.29.5 ile geçersiz.

## 0.6.1

Nox ≥ 1.29.3. `NOX_POOL_WORKERS` exec’ten önce (`./run.sh`). Tek JSON decode.
`dispatch_from_parts` / `handle_bare`. `AETHER_REQUEST_ID=0`.

## 0.6.0

Nox ≥ 1.29.0 çift runtime: QBE shared-nothing; `noxc build --release` M:N havuz
(macOS/arm64).

## 0.5.0

Desteklenen multicore: `dispatch_ensure` ile worker başına AppBind boot. Varsayılan workers=1.

## 0.4.4

DTO fingerprint (sıra bağımsız + nested), reclaim batch, contention test, route normalize, tag remote smoke.

## 0.4.3

Atomik stale reclaim, framework route / DTO isim çakışması boot kontrolü, release ref + package smoke.

## 0.4.2

Production correctness: workers=1 default, queue lease affected-row, metrics pattern key,
RateStore instance, body cache, string-only query/header, constant-time auth.

## 0.4.1

Hot-path: production CORS opt-in, tek header kopyası, lazy query, route metrics opt-in.

## 0.4.0

Query/header DTO + OpenAPI params, HS256 JWT (`jwt_bearer`), kuyruk lease dokümanı,
Aether / NestJS / Gin benchmark (`docs/BENCHMARKS.md`).

## 0.3.0

Correctness hardening: her response’ta `X-Request-Id`/CORS, interceptor unwind,
TaskLocal request bag, güvenli rate-limit varsayılanı, CORS allowlist, per-app
metrics, queue lease token + reclaim→DLQ.

## 0.2.0’da yeni

- Path prefix, `import_module`, exception filter
- CORS, body limiti, rate limit, 405, trailing slash
- OpenAPI `$ref` + status, `/docs` Swagger UI
- DTO format (`email` / `uuid` / `uri`) ve sayı aralığı
- `X-Forwarded-For` → `client_ip` (opt-in)
- Kuyruk stale reclaim + DLQ
- WebSocket oda / broadcast + token auth
- `/metrics`

Örnek uygulama: `examples/hello_api`.

Detaylı İngilizce README: [README.md](README.md) · mimari: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Nox limitleri: [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md) · kuyruk: [docs/QUEUE.md](docs/QUEUE.md) · benchmark: [docs/BENCHMARKS.md](docs/BENCHMARKS.md).

## Lisans

MIT
