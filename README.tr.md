# Aether

[English](README.md) · [Türkçe](README.tr.md)

**[Nox](https://github.com/mburakmmm/nox-lang) için NestJS esintili API / backend framework’ü.**  
Pythonic modüller, closure tabanlı DI, guard / pipe / interceptor, typed DTO, OpenAPI + Swagger UI, WebSocket gateway ve SQLite iş kuyrukları.

**Sürüm:** 0.10.0 · **Lisans:** MIT · **Nox ≥ 2.1.52**  
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
      "ref": "v0.10.0"
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
noxc install github.com/mburakmmm/aether@v0.10.0
aether new myapi
cd myapi && noxc fetch && chmod +x run.sh && ./run.sh
```

---

## 0.10.0

Nox tabanı **2.1.52**. Bu sürüm etiketlenene kadar yerelde durur. `AETHER_WORKERS>1` girişleri `serve_multicore*` çağrısına `make_handle` verir; her worker accept’ten önce kendi `Application` örneğini kurar. `AETHER_IPV6=1` ve `AETHER_WORKERS>1` birlikte `nox.http.configure` `ip_family` değerini kullanır (`1` dual-stack, `AETHER_IPV6_ONLY` ile `2`). Tek worker yine `listen_v6` + `serve_fd` kullanır. İstek kimliği ve `boot_id` UUID v7’dir. Hız sınırı penceresi ve istek günlüğü süresi monotonik saattir. Kuyruk lease’i duvar saatinde ve UUID v4’te kalır.

## 0.9.0

Nox tabanı **2.0.186**. `boot_for_serve`, `nox.http.configure` ve `set_http2` uygular. Tam `handle` `req.conn` geçirir; handler `ctx.sse()` / `ctx.stream()` ile o bağlantıya yazar. `with_cookie` / `expire_cookie` her çerez için ayrı `Set-Cookie` üretir. Production yanıtlarına, handler kendi değerini yazmadıysa, `nosniff`, `DENY` ve `no-referrer` eklenir. `POST /__aether/shutdown` dinlemeyi sürdürür ve 503 döner. `request_shutdown` drain dosyasını yazıp accept’i durdurur. SIGTERM dosyayı yazmadan accept’i durdurur; `finalize_serve` dosyayı `serve*` dönünce yazar. Benchmark HTTP/1.1’de kalır (`AETHER_HTTP2=0`).

Soket gövdesi `AETHER_MAX_BODY_BYTES` (varsayılan 1 MiB) üstündeyse Nox düz metin 413 döner ve handler çalışmaz. `0` Nox’un 10 MiB varsayılanını bırakır.

## 0.8.2

Nox tabanı **2.0.63**. `uri` alanı `nox.url.parse` ile bakılır (`http`/`https`, host zorunlu, IPv6 literal geçer). Sorgu sayıları kenar boşluğunu kabul eder. Metin şemaları `pattern`, `min_length` ve `max_length` kabul eder (`nox.regex`). Yapılandırılmış günlükler gizli alanları maskeler. `serve` imzaları aynıdır.

## 0.8.1

Nox tabanı **2.0.7**. 2.0.1’den beri standart kütüphane hataları İngilizce. Tek alanlı gövde kontrolü `nox.validate` ile aynı cümleleri basar; skaler ve iç içe şema aynı 422 ayrıntısını verir.

## 0.8.0

Nox tabanı **2.0.0**. LLVM varsayılan backend. `AETHER_WORKERS>1` hem LLVM hem QBE’de `serve_multicore` çağırır. LLVM havuzu süreç başında sabitlendiği için `NOX_POOL_WORKERS`, `AETHER_WORKERS` ile aynı olmalıdır; değilse süreç dinlemeye başlamaz.

## 0.7.2

Nox tabanı **1.171.2**. `nox.json` eski adları kalktı. Aether `parse`, `dump` ve `dump_string` kullanır.

## 0.7.1

Nox tabanı **1.142.24**. `AETHER_IPV6=1` tek worker ile `listen_v6` + `serve_fd`. `serve_multicore` IPv4 kalır. `client_ip()` `peer_addr` içinden portu ayırır.

## 0.7.0

Nox tabanı **1.142.2**. JWT ve base64 `nox.jwt` / `nox.base64` üzerinden. Sorgu şemaları number ve bool kabul eder. Hata JSON’unda `line` vardır. Bağlı metod handler olur: `m.get("/ping", ctl.show)`.

`HttpRequest` beşinci alan `peer_addr`. Drain kontrolü her istekte dosyaya bakmaz; worker başına `AETHER_STOP_POLL_MS` (varsayılan 200) önbellek. Ayrıntı `docs/SCOPE.md` ve `docs/NOX_LIMITATIONS.md`.

## 0.6.5

`boot_for_serve` / `finalize_serve`; multicore’da idle parent Application yok.
Koordineli graceful drain (`aether.lifecycle`, 503 + slot-local hooks,
opsiyonel `POST /__aether/shutdown`). `docs/SCOPE.md`.

## 0.6.4

Worker-local Application scope (`docs/SCOPE.md`). Idempotent `build()`,
worker metrics/rate-limit, route-shape collision, `route_key` normalize fix.

## 0.6.3

Nox ≥ 1.29.8. `workers>1` → `serve_multicore`. `AETHER_LLVM` kaldırıldı.
1.29.8 decode arena + Aether G2/A1–A7. Echo ≈ Gin.

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
Aether / NestJS / Gin / Axum benchmark (`docs/BENCHMARKS.md`).

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
