# Aether throughput gaps — teknik rapor

**Güncel floor:** Nox **1.171.2**, Aether **0.7.2**. 2026-09-27 satırı Nox 1.104.0 ölçümüdür (QBE ping 156 305 / echo 130 595). 1.29.8 tabloları tarihseldir.

Kaynak ölçüm (tarihsel): `wrk -t4 -c40 -d8s`, darwin arm64, Nox **1.29.8**, Aether **0.6.3**,
`AETHER_WORKERS=1`, `NOX_POOL_WORKERS=1`, `AETHER_REQUEST_ID=0`,
`AETHER_REQUEST_HEADERS=0`, production CORS/metrics/openapi/log kapalı.
Ham log: `benchmarks/results/*.txt`.

Amaç: Gin / Nest / QBE / `--release` farklarını **geliştirilebilir iş kalemlerine**
ayırmak. Mutlak RPS makineye bağlıdır; oranlar ve hot-path kanıtı asıl teslimattır.

## 1. Ölçülen matris

### 0.6.3 + Nox 1.29.8 + Aether G2 path (tarihsel)

İzole Aether (Nest/Gin kapalı):

| Hedef | GET /ping req/s | POST /echo req/s | ping→echo düşüş |
|--------|----------------:|-----------------:|----------------:|
| Aether QBE | 208 213 | **163 343** | −22% |
| Aether `--release` | **202 562** | **169 672** | **−16%** |

Aynı oturumda Gin echo ~174k → Gin/Aether echo ≈ **1.02×–1.09×** (önceden 1.63× / 2.0×).

### 0.6.3 + Nox 1.29.8 decode-only (tarihsel, Aether G2 path öncesi)

QBE 199 015 / 106 417; `--release` 210 165 / 113 592; Nest 65 603 / 51 712; Gin 192 403 / 185 482.
Gin/echo **1.63×**. Ping→echo ~−46%.

### 0.6.3 + Nox 1.29.6 (tarihsel)

QBE 206 956 / 89 940; `--release` 207 402 / 91 019; Nest 65 412 / 50 969; Gin 191 539 / 185 185.
`--release` 8w: ping 66 382, echo 90 460. Gin/echo **2.03×**.

### 0.6.2 + Nox 1.29.4 (tarihsel)

QBE 206 199 / 89 096; `--release` 209 364 / 90 908; Nest 64 394 / 51 546; Gin 192 468 / 186 202.
`--release` 8w (`AETHER_LLVM=1`): ping 49 776, echo 48 843.

### 0.6.1 + Nox 1.29.3 (tarihsel)

QBE 209 226 / 94 342; `--release` 206 284 / 89 782; Nest 66 975 / 51 532; Gin 196 243 / 186 348.
`--release` 8w: ping 143 574, echo 94 066.

### 0.6.1 / Nox 1.29.2 (tarihsel)

QBE 203 263 / 88 057; `--release` 188 075 / 86 937; Nest 64 792 / 51 062; Gin 189 441 / 177 275.

## 2. Üç bağımsız fark (karıştırmayın)

```
ping  : HTTP accept + route + sabit JSON body
echo  : ping + JSON decode + DTO validate + encode_string + concat
--rel : aynı Aether kodu, farklı Nox runtime (M:N + atomic ARC)
```

| ID | Semptom | Kök katman | Gin’e kapanır mı? |
|----|---------|------------|-------------------|
| G1 | Ping QBE 159k vs Gin 191k (~%17) | Nox HTTP + Aether dispatch bookkeeping | Kısmen (Aether+Nox) |
| G2 | Echo ~1.05× Gin (önceden ~2.0×) | Nox decode (1.29.8) + Aether validate/ingest/encode | Kısmen kapandı — kalan Nest-style DTO tax |
| G3 | `--release` ping 3.1× yavaş | Nox 1.29 M:N otomatik havuz | Hayır — yanlış workload veya `NOX_POOL_WORKERS=1` |
| G4 | wrk socket `read` error (yalnız Aether) | Nox HTTP keep-alive / connection teardown | Nox runtime |

## Aether G2 path — validate/ingest/encode (2026-08-14)

Bare `nox.http`+`nox.json` ping≈echo (1.29.8 sonrası). Aether echo ekleri:

1. `validation_pipe` → `nox.validate.validate(schema.flat())` (+ gereksiz 2. tur format/min/max)
2. `ValidatedBody._ingest` — decode edilmiş nesneyi 4 paralel diziye **yeniden** yürüyüş
3. `encode_str_map` — tek alan için list+join

**Düzeltme (0.6.3):** `_jsons` içinde `JsonValue` tut / accessor doğrudan okur;
`_schema_needs_extra` yoksa 2. validate turu yok; tek alan `encode_str_map` hızlı yolu.

**Ölçüm:** `--release` echo 114k→**170k**; ping↔echo −46%→**−16%**; Gin’e ~1.05×.

G4 açık.

## Nox 1.29.7 / 1.29.8 — `nox.json.decode` (2026-08-14)

Diff `v1.29.6...v1.29.8`: yalnız `runtime/stdlib_shims/json.zig` + golden
`json_decode_repeated_calls`. HTTP/keep-alive yok. **API değişmedi.**

**1.29.7 — dürüst negatif:** Aether ping/echo ~2.3× farkı izole edildi → kök
`decode()` (body okuma / `encode` değil). Hipotez “düğüm-başına Nox çağrısı
domine ediyor” `--release`’de yanlış çıktı (~%1–2). Yine de `JsonValue` artık
Zig’de doğrudan inşa (class_id runtime keşif) — sadeleştirme, PUBLIK API aynı.

**1.29.8 — asıl darboğaz:** her `decode()`’da taze `ArenaAllocator` →
`page_allocator` → **mmap+munmap** (profil: maliyetin ~%62’si). Düzeltme:
`threadlocal` arena + `reset(.retain_with_limit(64KiB))`. Nox kendi ölçümü:
sıkı döngü decode **6.2×**; wrk echo-decode-only 138k→**226k** (+64%), raw
passthrough’a yakınlık %57→**%94**.

**Bu microbench (Aether):** `--release` echo **91k→114k (+25%)**; QBE echo
**90k→106k (+18%)**. Gin/echo **2.03×→1.63×**. Ping gürültü bandında.
Kalan G2: Aether DTO validate + `encode_str_map` / `json_ok_str` (ve Nox
`std.json` / `dupeToNoxStr` artığı). G4 açık.

**Aether kodu:** gerekmez (zaten tek decode). Bu turun floor’u **1.29.8** idi; güncel floor **1.104.0**.

## Nox 1.29.5 / 1.29.6 — steal + TLS (2026-08-14)

Diff `v1.29.4...v1.29.6`: `runtime/stdlib_shims/http_server.zig`, `scheduler.zig`,
`tls_server.zig` + golden testler. JSON/keep-alive yok.

**1.29.5 — ne çözüldü:** `--release` `serve_multicore` bağlantı fiber’ları artık
Chase-Lev deque’e gidiyor (work-steal). 1.29.4 SO_REUSEPORT sonrası dengesiz
kernel dağılımında boş worker yardım edemiyordu → Aether dispatch maliyetinde
8w ping ~209k→~56k (−%73). Nox kendi ölçümü (Aether handler, atlatma bypass):
8w artık 1w altına düşmüyor (+%6…+%25).

**Bu microbench (c=40):** 8w echo **~90k ≈ 1w** (1.29.4 `AETHER_LLVM` 8w ~49k’tan
kurtuldu). 8w ping hâlâ 66k (1w 207k) — ucuz non-yielding ping + steal vergisi.
Varsayılan `AETHER_WORKERS=1` kalsın; JSON-ağır production `--release`’de
`workers>1` + `serve_multicore` tekrar doğru yol.

**1.29.6:** `serve_tls` threadlocal BIO buffer yarışı (aynı OS thread’de iç içe
TLS fiber’ları). Ping/echo bench’i etkilemez; production TLS için floor.

**Aether kodu (0.6.3):** `AETHER_LLVM` atlatması kaldırıldı. `use_os_workers` =
`workers>1` → `serve_multicore` (QBE + `--release`). Floor pin later raised to
**1.29.8** (JSON decode). `NOX_POOL_WORKERS` hâlâ exec öncesi.

G2 (echo ~2× Gin) ve G4 (wrk `read`) açık.

## Nox 1.29.4 — SO_REUSEPORT (2026-08-13)

Diff `v1.29.3...v1.29.4`: `compiler/codegen_qbe/http_intrinsics.zig`, `runtime/stdlib_shims/http_server.zig`, `runtime/async_rt/io.zig`. JSON yok. Keep-alive yok.

**Ne çözüldü (QBE):** `serve_multicore` artık paylaşılan tek `accept()` fd yerine worker başına `SO_REUSEPORT` soket açıyor. Nox’un kendi C deneyi: paylaşılan fd 8 thread’de 1’e göre %12 yavaş; SO_REUSEPORT hafif iyileşme. Yanında `nox.http.serve()` 7-argüman ABI düzeltmesi (sessiz erken dönüş) ve sınırlı `max_connections` için paylaşılan atomic bütçe.

**`--release` yan etkisi:** flatten hâlâ `$nox_pool_serve(N, worker_fn)`. `worker_fn` artık her havuz worker’ında **bağımsız** soket açıyor → N accept döngüsü, steal yok. Bu microbench’te 8w ping **143k → 56k**. Tek `serve()` + `NOX_POOL_WORKERS=8` (`AETHER_LLVM=1`) de ~50k — ping yield etmediği için 7 worker boşta + G3 havuz vergisi.

**Aether kodu (0.6.2):** `aether.server.use_os_workers`. QBE `workers>1` → `serve_multicore`. `--release` (`AETHER_LLVM=1`, `./run-release.sh`) → her zaman `serve()`. Floor pin 1.29.4. Varsayılan `AETHER_WORKERS=1` kalsın.

G2 ve G4 1.29.4’te açık. 8w `--release` ping 1.29.3’ten **kötü** (Nox flatten+SO_REUSEPORT uyumsuzluğu; Aether Nox codegen’i geri alamaz).

## Nox 1.29.3 — ARC free-list kilidi (2026-08-13)

Diff `v1.29.2...v1.29.3`: yalnız `runtime/alloc/arc.zig`, `asap.zig`, `worker_pool.zig`. JSON/HTTP/keep-alive yok. Nox API değişmedi.

**Ne çözüldü:** `--release` paylaşılan havuzda `pool_free_lists` tek `SpinLock` idi. JSON-yoğun handler 8 worker’da 1 worker’dan yavaştı (~89k vs ~101k). Worker-slotlu kilitsiz satır (64B align) sonrası Nox kendi ölçümü: 8w 89k→147k (+64%), 8w artık 1w’yi +%43 geçer.

**Aether kodu:** gerekmez. Floor pin 1.29.3 yeterli. `NOX_POOL_WORKERS` zaten exec öncesi.

**Bu microbench’te:** workers=1 ping/echo 1.29.2 ile aynı bant (çekişme yok). 8 worker ping c=40’ta 1 worker’dan yavaş (143k vs 206k) — küçük ping + steal vergisi. Echo +%5 (90k→94k). Varsayılan `AETHER_WORKERS=1` kalsın; JSON-ağır production `--release`’de `AETHER_WORKERS>1` artık tersine ölçeklenmemeli.

G2 (echo ~2× Gin) ve G4 (wrk `read`) 1.29.3’te açık.

## Nox 1.29.1 / 1.29.2 — darboğaz kapanışı (2026-08-13)

Kaynak: [nox-lang v1.29.1](https://github.com/mburakmmm/nox-lang/releases/tag/v1.29.1) /
[v1.29.2](https://github.com/mburakmmm/nox-lang/releases/tag/v1.29.2) CHANGELOG.
1.29.2 metni açıkça Aether `PERF_GAPS.md`’yi işaret ediyor. Diff:
`v1.29.0...v1.29.2` — `json.zig` yok; HTTP runtime + `$main` havuz + codegen.

### Hüküm (Aether 0.6.0 kodu + 1.29.2 runtime)

| Gap | Nox 1.29.2 çözdü mü? | Aether bugün yararlanır mı? |
|-----|----------------------|------------------------------|
| G1 ping tavanı | **Kısmen.** `TCP_NODELAY` (Madde 1) + header-skip (Madde 2) | `TCP_NODELAY`: **evet** (paylaşılan `noxrt`). Header-skip: **hayır** — `handle` `req`’i `dispatch_ensure`’e kaçırıyor → `UsedRequestFields.allUsed()` |
| G2 echo / çift decode | **Hayır.** `nox.json` mimarisi aynı (~2.3× serde; Zig→Nox per-node) | Aether E1/E2 hâlâ tek yol |
| G3 `--release` 3× | **Kısmen, yanlış program sınıfı için.** `serve_multicore` AST’de yoksa havuz 2 worker | Aether şablonları `if workers > 1: serve_multicore` içerir → AST `true` → CPU havuzu. `apply_pool_workers` **çok geç** |
| G4 wrk `read` | **Hayır.** Keep-alive teardown aynı; `TCP_NODELAY` Nagle gecikmesi, RST değil | wrk error Aether+Nox’ta kalır |
| (yan) `--release` SEGV | **Evet (1.29.1).** `Task[T]` çapraz-worker `await_()` Waiter düzeltmesi | Ping/echo path’i `Task.await` kullanmaz; doğruluk kazancı |

### Madde 1 — `TCP_NODELAY` (G1’e gerçek katkı)

`runtime/async_rt/io.zig` `setTcpNodelay` + `http_server.zig` `blockingAccept`.
Kabul edilen her conn soketine `IPPROTO_TCP`/`TCP_NODELAY`. Nagle + delayed-ACK
küçük JSON yazımlarında onlarca ms ekleyebiliyordu.

Nox’un kendi `http_compare` ölçümü (çıplak Nox, Aether değil): **c=30 +%4.0,
c=100 +%15.1**. Runtime değişikliği — QBE `noxc run` da yeni `noxrt` ile alır
(changelog’un “üç madde LLVM-only” cümlesi codegen IR içindir; `TCP_NODELAY`
Zig runtime’dadır).

Aether ping/echo sabit küçük JSON → aynı sınıfta. Beklenen: QBE ping’de
tek haneli–orta yüzde, yüksek `c`’de daha görünür. Gin %17’lik ping farkını
tek başına kapatmaz.

### Madde 2 — header kopya atlama (Aether’e işlemez)

`used_fields.headers` artık `nox_http_serve_raw(..., needs_headers)`.
`needs_headers == false` iken `iterateHeaders` + header başına 2 ARC
`dupeToNoxStr` atlanır. Analiz **intra-procedural** ve kaçışta muhafazakâr:

```nox
# benchmarks/aether/main.nox — req tanımlayıcı olarak çağrı argümanı
def handle(req: HttpRequest) -> HttpResponse:
    return aether.application.dispatch_ensure(req, cfg, build)
```

`visitExprForReqUsage(.identifier)` → `allUsed()`. CORS kapalı olsa bile
derleme `needs_headers=1` üretir. Kazanç yalnız `handle` gövdesinde
`req.headers` hiç geçmeyen (ve `req` kaçmayan) çıplak Nox handler’larda.

Aether’in yararlanması için: Nox IPA, veya `handle` içinde `req.method` /
`req.target` / `req.body` okuyup `req`’i kaçırmayan bir dispatch API
(bugünkü `dispatch_ensure` ile uyumsuz).

### Madde 3 — küçük `$main` havuzu (G3 Aether’de kaçırılır)

`--release` `$main` otomatik havuz:

- `NOX_POOL_WORKERS` getenv **önce** (process env, `$main` init)
- yoksa ve AST’de `serve_multicore*`/`pool_run` yoksa → **2** worker
- yoksa CPU sayısı

Aether `benchmarks/aether/main.nox` / `templates/app/main.nox`:

```nox
if workers > 1:
    nox.http.serve_multicore(cfg.port, handle, workers)
else:
    nox.http.serve(cfg.port, handle)
```

`moduleUsesMulticorePool` **runtime `workers` değerine bakmaz** — AST’de
çağrı varsa `true`. `AETHER_WORKERS=1` `--release` hâlâ CPU worker açar.

Daha kötüsü: `apply_pool_workers` → `nox.os.set_var("NOX_POOL_WORKERS", ...)`
**kullanıcı `main`inde**, havuz `nox_pool_main_init` ile **çoktan kurulduktan
sonra**. 1.29.0’da da 1.29.2’de de `set_var` havuz boyutunu değiştirmez.
`benchmarks/run.sh` `AETHER_WORKERS=1` export eder, `NOX_POOL_WORKERS` etmez.

Bu, G3’ün 3.13×’inin asıl adayı: microbench `workers=1` sanırken `--release`
M:N + atomic ARC + CPU worker. 1.29.2 bunu Aether şablonları için kapatmadı.

Doğru kaçış (hâlâ geçerli): **süreç başlamadan** `NOX_POOL_WORKERS=1`
(shell / launchd / systemd). Sonra R1’i yeniden koş.

### 1.29.1 — Task await yarışı

`--release` altında `Task.await_()` yanlış scheduler’a `markReady` (Channel
MN.9.1 ile aynı sınıf). Ping/echo bunu kullanmaz. QBE+LLVM aynı anda
SIGSEGV ayrı bir konu (iki HTTP sunucusu). 1.29.1 production `--release`
doğruluğu için pin’e değer; throughput tablosunu değiştirmez.

### Aether aksiyon (0.6.1 uygulandı)

1. Floor **1.29.2** (CI `NOX_VERSION`) — `TCP_NODELAY`.
2. Launch: `scripts/aether_env.sh` + scaffold `run.sh` / `run-release.sh`.
   `apply_pool_workers` çocuk süreçler için kaldı; `$main` havuzu için no-op.
3. E1: `parse_value_or_raise` → `ValidatedBody.from_decoded` (tek decode).
4. E2: `json_ok_str` / `encode_str_map` + `nox.strings.join`.
5. G1: `dispatch_from_parts` + `handle_bare` (`AETHER_REQUEST_HEADERS=0`);
   `apply_headers` in-place; `AETHER_REQUEST_ID=0` uuid atlar.
6. G4 keep-alive — hâlâ Nox upstream.

Kalan: R1’i 1.29.2 + `NOX_POOL_WORKERS=1` ile yeniden ölçmek.

## 3. G1 — Ping: Aether QBE vs Gin

### Ne ölçülüyor

Her iki sunucu da `{"pong":true}` benzeri küçük JSON döner. Scheduler farkı yok
(`workers=1`, QBE = tek OS thread M:1).

### Aether ping hot-path (her istek)

`benchmarks/aether/main.nox` → `dispatch_ensure` → `dispatch` (`application.nox`):

1. `nox.uuid.uuid4()` — request id
2. `path_only` + `normalize_path`
3. `begin` / `finish` (`TaskLocal` RequestState)
4. `max_body_bytes` kontrolü
5. `find_route_indexed` (method bucket; ping’de ucuz)
6. `HttpContext` tahsisi
7. `execute` — boş guard/pipe/interceptor short-circuit (0.4.1)
8. Handler: `json_ok("{\"pong\":true}")` — sabit string, encode yok
9. `_finalize_response`: header map kopyası + `X-Request-Id`
10. `metrics.record(status)` (route metrics production’da kapalı)

Gin: `gin.New()` + `c.JSON` (`encoding/json` + buffer). Goroutine/istek modeli
ucuz; header/body tek `net/http` yazım yolu.

### Hipotez (öncelik sırası)

1. **Nox HTTP sunucusu** (keep-alive, syscall, header serialize) — G4 ile aynı
   aile. Bare Nox ~231k (0.4.1 micro-probe) vs Aether ~163k: framework ~%30.
   Gin 191k, bare Nox 231k → Aether ping tavanı büyük ölçüde Nox HTTP + Aether
   bookkeeping.
2. **`uuid4` + TaskLocal + HttpContext + header copy** her ping’de.
3. **ARC / string**: `resp.body + ""` (`with_headers`) gereksiz kopya.

### Geliştirme deneyleri

| Deney | Nasıl | Başarı ölçütü |
|-------|--------|----------------|
| P1 | Bench app’de `dispatch` yerine bare `handle` (aynı port protokolü) | Framework delta (bugün ~bare 231k vs 159k) |
| P2 | `uuid4`’ü opt-in yap (prod’da `X-Request-Id` kapalı) | Ping +% | 
| P3 | Finalize’da header copy elision (tek dict mutate) | Küçük ama ping’de görünür |
| P4 | Nox HTTP keep-alive / `read` error (upstream) | wrk `Socket errors: read` → 0; ping Gin bandına yaklaşır |

## 4. G2 — Echo: Aether’in asıl framework kaybı

Gin echo neredeyse ping (−6%). Aether echo ping’in yarısı (−51%). Bu **Aether
JSON yolu**, HTTP değil.

### Echo pipeline

`m.post_body` → `validation_pipe(input_schema)` (`pipe.nox`):

```nox
raw: str = ctx.body()
validated: str = parse_or_raise(raw, schema)  # nox.json.decode + validate
ctx.set_input(validated)                      # raw kopyası, parse tree yok
```

`parse_or_raise` (`dto.nox`) decode eder, hata yoksa **aynı raw string’i** döner.
Handler:

```nox
return json_ok("{\"msg\":" + nox.json.encode_string(ctx.input_str("msg")) + "}")
```

`input_str` → `validated_body()` → `ValidatedBody._ensure` → **ikinci**
`nox.json.decode` (`body.nox`). Accessor tekrarları cache’li; validation→handler
arası **değil**.

Sonra `encode_string` + `+` concat + `json_ok` + header copy.

Gin: tek `ShouldBindJSON` (reflect bir kez) + tek `c.JSON` (aynı buffer ailesi).

### Maliyet modeli (echo extra vs ping)

```
echo_extra ≈ decode_validate + decode_access + encode_string + concat
```

Çift decode kanıtı:

- `validation_pipe` → `parse_or_raise` → `nox.json.decode`
- `ValidatedBody._ensure` → `nox.json.decode` (aynı raw)

Nox `json_bench` mimari notu: Zig→Nox per-node call (~2.7× C). Aether bunu
**istek başına iki kez** ödüyor.

### Geliştirme deneyleri

| Deney | Nasıl | Başarı ölçütü |
|-------|--------|----------------|
| E1 | `parse_or_raise` JsonValue’yu context’e yaz; `ValidatedBody` decode etme | Echo QBE ping’e yaklaşır (hedef: düşüş −51% → −15–25%) |
| E2 | `json_ok_obj` / buffer API (Nox stdlib yoksa Aether `list[str]` join) | encode_string+concat kaybı |
| E3 | Echo bench’te validation kapalı vs açık A/B | Validation’ın tam maliyeti |
| E4 | Sabit `{"msg":"hello"}` için interned escape-skip | Micro; asıl kazanç E1 |

**E1 en yüksek Aether-kontrollü ROI.** ChatGPT 0.4.2 notu hâlâ geçerli.

## 5. G3 — `--release` 3× yavaş (yanlış workload)

Aynı `benchmarks/aether/main.nox`, `AETHER_WORKERS=1`. Kod değişmiyor; Nox
backend değişiyor.

Nox 1.29 `--release`:

- `$main` otomatik M:N havuz (`NOX_POOL_WORKERS`, varsayılan = CPU)
- `serve` / `serve_multicore` havuza **flatten**
- Atomic ARC (`atomicrmw`) her retain/release
- Kooperatif STW cycle collector
- Chase-Lev deque + steal

QBE `noxc run`: tek OS thread, non-atomic ARC, M:1 fiber. Ping ~250µs; M:N
sabit vergisi RPS’i 3× düşürür. Echo’da oran 1.73× — iş CPU-bound JSON’a
kayınca havuz vergisi görece küçülür (hala kayıp).

`--release` ping’in Nest’in altında kalması (51k vs 66k) bu vergiden.

### Bu bir Aether bug’ı değil

`--release` hedefi: paylaşımlı heap, gerçek çok çekirdek, `AppBind` görünürlüğü.
Tek-worker JSON ping onun kazanç alanı değil.

### Geliştirme deneyleri

| Deney | Nasıl | Beklenti |
|-------|--------|----------|
| R1 | `NOX_POOL_WORKERS=1 noxc build --release` + aynı wrk | Elma-elma vs QBE (LLVM −O2 vs QBE, havuz yok) |
| R2 | QBE `AETHER_WORKERS=N` vs `--release` N vs Gin (GOMAXPROCS) | `--release`’in gerçek değeri |
| R3 | `apply_pool_workers` `workers==1` iken `NOX_POOL_WORKERS=1` zorla | Production `workers=1 --release` ping’i QBE’ye yaklaşır |

R3 production default ile uyumlu: Aether default `workers=1`. Bugün `--release`
yine de CPU kadar worker açıyor olabilir — **doğrulanmalı** (`sample` / thread
count). Doğrulama: `AETHER_WORKERS=1` `--release` süreçte kaç OS thread.

## 6. G4 — wrk `Socket errors: read`

Yalnız Aether (QBE ve `--release`). Nest/Gin 0.

`wrk` bağlantıyı kapatırken peer `read` hata sayıyor: keep-alive reuse, erken
close, veya RST. Throughput’u kirletir (QBE ping 1.2k error / 1.29M istek ≈
%0.1) ama sıralamayı değiştirmez. Keep-alive bozuksa **uzun** testte Gin
farkı büyür.

Nox `http_server` / `serve` keep-alive. Aether tarafında yapılacak az şey var;
repro: aynı wrk’i bare Nox ping’e (`benchmarks` dışı) koş. Bare’de de error
varsa upstream; yoksa Aether finalize/header.

## 7. Nest farkı (referans)

Express + V8 + tek event loop. QBE ping 2.43× Nest beklenen. Echo’da fark
1.53×’e iner — Nest’in JSON’u Aether echo yolundan daha olgun; Aether ping’de
native, echo’da string-concat cezası yiyor.

## 8. Önerilen iş sırası (geliştirme)

P0 — ölçüm hijyeni + Nox 1.29.2

1. Floor Nox **1.29.2** (TCP_NODELAY).
2. `NOX_POOL_WORKERS`’ı **süreç env**’ine yaz ( `apply_pool_workers` /
   `set_var` `$main` havuzundan sonra gelir — no-op). Sonra R1.
3. Bare Nox vs Aether ping (P1) + socket error (G4) ayrımı.

P1 — Aether kodu (Gin echo farkı)

4. E1: validation JsonValue → ValidatedBody (çift decode kalksın).
5. E3: validation on/off A/B.
6. E2: yanıt buffer / tek encode.

P2 — ping tavanı

7. P2/P3: uuid/header copy opt-in.
8. G4 upstream veya keep-alive.

P3 — `--release` değeri

9. R2: N worker vs Gin. Microbench tablosuna “workers=1 `--release`” ayrı
   satır olarak kalsın; “production multicore” ayrı tablo.

## 9. Bilinçli olarak dokunulmayanlar

- Class decorator / Nest rewrite — Nox 1.29’da yok.
- In-memory RateStore mutex — `--release` multicore’da ayrı konu; ping/echo
  path’te kapalı.
- Linux `--release` iddiası — spec macOS/arm64.

## 10. Repro

```sh
# QBE + Nest + Gin + sequential --release
DURATION=8s CONNECTIONS=40 THREADS=4 ./benchmarks/run.sh

# Havuzsuz LLVM (R1)
NOX_POOL_WORKERS=1 AETHER_WORKERS=1 AETHER_SKIP_RELEASE=1 \
  DURATION=8s CONNECTIONS=40 THREADS=4 ./benchmarks/run.sh
# sonra ayrıca:
NOX_POOL_WORKERS=1 AETHER_ENV=production AETHER_PORT=3004 AETHER_WORKERS=1 \
  AETHER_OPENAPI=0 AETHER_LOG_REQUESTS=0 AETHER_CORS_ORIGINS= \
  AETHER_METRICS=0 AETHER_METRICS_ROUTES=0 \
  noxc build --release -o /tmp/aether-rel benchmarks/aether/main.nox
/tmp/aether-rel
wrk -t4 -c40 -d8s http://127.0.0.1:3004/ping
```
