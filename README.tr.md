# Aether

[English](README.md) · [Türkçe](README.tr.md)

**[Nox](https://github.com/mburakmmm/nox-lang) için NestJS esintili API / backend framework’ü.**  
Pythonic modüller, closure tabanlı DI, guard / pipe / interceptor, typed DTO, OpenAPI + Swagger UI, WebSocket gateway ve SQLite iş kuyrukları.

**Sürüm:** 0.2.0 · **Lisans:** MIT · **Nox ≥ 1.26.0**  
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
      "ref": "v0.2.0"
    }
  ]
}
```

```sh
noxc fetch
AETHER_ENV=development noxc run main.nox
```

### Yerel path (geliştirme)

```json
{ "alias": "aether", "repo": "/absolute/path/to/aether", "ref": "master" }
```

### CLI iskelet

```sh
noxc install github.com/mburakmmm/aether@v0.2.0
aether new myapi
cd myapi && noxc fetch && AETHER_ENV=development noxc run main.nox
```

---

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

Detaylı İngilizce README: [README.md](README.md) · mimari: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · Nox limitleri: [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md).

## Lisans

MIT
