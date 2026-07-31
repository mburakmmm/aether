# Aether

NestJS-inspired **API / backend** framework for [Nox](https://github.com/mburakmmm/nox-lang) (≥ **1.26.0**).

Pythonic modules, closure-based DI, guards/pipes/interceptors, typed DTOs, OpenAPI, WebSocket gateways, and background queues.

> Independent of [Nyx](https://github.com/mburakmmm/nyx) (Rails-style full-stack). Use Aether for HTTP APIs; use Nyx for monolithic HTML apps.

## Quick start

```nox
import nox.http
from nox.http import HttpRequest, HttpResponse
import aether.application
import aether.server
import aether.config
from aether.application import Application
from aether.config import Config
from aether.module import ModuleBuilder
from aether.context import HttpContext
from aether.response import json_ok

class HealthModule:
    def configure(self: HealthModule, m: ModuleBuilder) -> None:
        m.get("/healthz", self._health())

    def _health(self: HealthModule) -> (HttpContext) -> HttpResponse:
        def health(ctx: HttpContext) -> HttpResponse:
            return json_ok("{\"status\":\"ok\"}")
        return health

def build(app: Application) -> None:
    HealthModule().configure(app.module())

cfg: Config = aether.config.load()
app: Application = aether.application.boot_with_config(cfg, build)

def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch(app, req)

aether.server.print_listen(cfg, aether.server.serve_mode(cfg, False))
try:
    workers: int = aether.server.effective_workers(cfg)
    if workers > 1:
        nox.http.serve_multicore(cfg.port, handle, workers)
    else:
        nox.http.serve(cfg.port, handle)
finally:
    aether.application.shutdown(app)
```

```sh
noxc fetch
AETHER_ENV=development noxc run examples/hello_api/main.nox
```

## Features

| Feature | Module |
|---------|--------|
| Application boot / dispatch | `aether.application` |
| Modules + routing | `aether.module` (`app.module()`) |
| Provider name registry | `aether.container` |
| Request context (`TaskLocal`) | `aether.context` |
| Guards / pipes / interceptors | function-based (`aether.guard`, `pipe`, `interceptor`) |
| DTO validation | `aether.dto` |
| Structured errors | `aether.errors` |
| OpenAPI 3 | `aether.openapi` (`GET /openapi.json`) |
| WebSocket gateway | `aether.gateway` |
| Background jobs | `aether.queue` |
| CLI scaffold | `aether` bin (`cli.nox`) |

## DI style

Nox cannot subclass imported framework bases and has no ctor reflection. Aether uses **closure injection**:

```nox
svc: UserService = UserService()
m.provide("UserService")          # name registry only
m.get("/users/:id", self._show(svc))  # svc captured by handler
```

## Nox limitations

Evidence-backed language gaps for upstream work: [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md).

Performance notes: [docs/PERF.md](docs/PERF.md).

## License

MIT
