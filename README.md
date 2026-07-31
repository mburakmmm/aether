# Aether

NestJS-inspired **API / backend** framework for [Nox](https://github.com/mburakmmm/nox-lang) (≥ **1.26.0**).

Pythonic modules, dependency injection via closures + provider registry, guards, pipes, interceptors, typed DTOs, OpenAPI, WebSocket gateways, and background queues.

> Independent of [Nyx](https://github.com/mburakmmm/nyx) (Rails-style full-stack). Use Aether for HTTP APIs; use Nyx for monolithic HTML apps.

## Quick start

```nox
import aether.application
import aether.server
from aether.application import Application
from aether.module import ModuleBuilder
from aether.context import HttpContext
from aether.response import json_ok
from nox.http import HttpRequest, HttpResponse

class HealthModule:
    def configure(self: HealthModule, m: ModuleBuilder) -> None:
        m.get("/health", self._health())

    def _health(self: HealthModule) -> (HttpContext) -> HttpResponse:
        def health(ctx: HttpContext) -> HttpResponse:
            return json_ok("{\"status\":\"ok\"}")
        return health

def build(app: Application) -> None:
    app.import_module(HealthModule())

app: Application = aether.application.boot(build)

def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch(app, req)

aether.server.listen(app, handle)
```

```sh
noxc fetch
AETHER_ENV=development noxc run examples/hello_api/main.nox
```

## Features

| Feature | Module |
|---------|--------|
| Application boot / dispatch | `aether.application` |
| Modules + routing | `aether.module` |
| DI container | `aether.container` |
| Request context (`TaskLocal`) | `aether.context` |
| Guards / pipes / interceptors | `aether.guard`, `aether.pipe`, `aether.interceptor`, `aether.pipeline` |
| DTO validation | `aether.dto` |
| Structured errors | `aether.errors` |
| OpenAPI 3 | `aether.openapi` |
| WebSocket gateway | `aether.gateway` |
| Background jobs | `aether.queue` |
| CLI scaffold | `aether` bin (`cli.nox`) |

## Nox limitations

See [docs/NOX_LIMITATIONS.md](docs/NOX_LIMITATIONS.md) for evidence-backed language gaps (class decorators, ctor DI, peer IP, …) tracked for upstream Nox work.

## License

MIT
