<div dir="rtl">

# توضیح کد جلسه‌ی ۸

در جلسه‌ی ۷ مدلی را `@champion` کردیم. در این جلسه آن مدل را به یک **سرویس وب (REST API)** با FastAPI تبدیل می‌کنیم. هر برنامه‌ی دیگری (وب‌سایت، موبایل و ...) می‌تواند مشخصات یک مشتری را با HTTP بفرستد و احتمال churn را در جواب بگیرد.

فایل‌های این جلسه:

- فایل `churn/api.py`: خود API. مهم‌ترین و پیچیده‌ترین فایل دوره است.
- فایل `scripts/check_contract.py`: مقایسه‌ی ورودی API با signature مدل `@champion`.
- فایل `tests/test_api.py`: یازده تست که بدون سرور اجرا می‌شوند.
- پوشه‌ی `examples/`: سه نمونه‌ی ورودی JSON (فایل کد نیست و این‌جا توضیح داده نمی‌شود).
- فایل `Makefile`: هدف‌های تازه‌ی `contract` و `serve`.

ارتباط با جلسه‌ها: `api.py` برای اتصال به MLflow از `churn/registry.py` (جلسه‌ی ۷) استفاده می‌کند، یعنی `connect` و `check_download_setting`. در جلسه‌های بعد همین کد داخل image داکر و بعد روی Kubernetes می‌رود.

کامنت‌ها و docstringهای داخل کد عمداً انگلیسی هستند، چون ویرایشگرهای کد متن را چپ‌به‌راست نشان می‌دهند. شرح فارسی همه‌چیز در همین فایل است.

---

## نقشه‌ی کلی: یک درخواست `/predict` چه مسیری می‌رود

```text
کلاینت --JSON--> middleware (زمان‌سنجی + لاگ)
                    -> pydantic (Customer): ورودی بد؟ -> 422 و پایان
                    -> predict(): مدل لودشده در app.state
                    -> Prediction (JSON) + شمارنده و histogram
```

مدل **فقط یک بار** هنگام روشن شدن سرور (در `lifespan`) لود می‌شود، نه برای هر درخواست.

---

## فایل `churn/api.py`

**کار فایل:** مدل `@champion` را از Registry لود می‌کند و با endpointهای زیر سرو می‌کند:

| آدرس | کار |
|---|---|
| `GET /health` | زنده بودن پروسه (liveness) |
| `GET /ready` | آماده بودن مدل (readiness)، با کد ۵۰۳ اگر مدل لود نشده باشد |
| `GET /model-info` | نسخه و `run_id` مدلی که الان سرو می‌شود |
| `POST /predict` | ورودی یک مشتری (JSON)، خروجی احتمال churn |
| `GET /metrics` | متریک‌های Prometheus |
| `GET /docs` | مستندات تعاملی که FastAPI خودکار می‌سازد |

**اجرا** (با سرور MLflow روشن و متغیرهای `.env` لودشده):

```bash
set -a; source .env; set +a
make serve
```

دستور `make serve` همان `uv run uvicorn churn.api:app --host 127.0.0.1 --port 8000` است.

**ورودی و خروجی:** ورودی درخواست‌های HTTP و مدل `@champion` است. خروجی پاسخ JSON، لاگ‌های JSON روی stderr و متریک‌ها در `/metrics` است.

### تنظیمات از متغیر محیطی

```python
# Config comes from environment variables with defaults, so the same code runs on the
# laptop, in Docker and in Kubernetes without editing the file (12-factor style).
MODEL_URI = os.environ.get("MODEL_URI", "models:/churn@champion")
THRESHOLD = float(os.environ.get("PREDICT_THRESHOLD", "0.5"))  # env values are always str
```

تنظیمات از متغیر محیطی می‌آید و مقدار پیش‌فرض دارد. به این ترتیب همین کد روی لپ‌تاپ، در Docker و در Kubernetes بدون ویرایش فایل اجرا می‌شود (روش 12-factor). مقدار متغیرهای محیطی همیشه رشته است، پس `THRESHOLD` را با `float` تبدیل می‌کنیم.

### متریک‌های Prometheus: Counter و Histogram

```python
# Prometheus metrics live at module level: they must be created ONCE per process.
# Counter only goes up. The label "churn" ("true"/"false") splits it into two series.
PREDICTIONS = Counter("churn_predictions_total", "Predictions served", ["churn"])
# Histogram counts how many observations fell into time buckets (to see slow requests).
LATENCY = Histogram("churn_predict_seconds", "Time spent in model.predict_proba")
```

دو نوع متریک داریم:

- نوع `Counter` فقط بالا می‌رود (هیچ‌وقت کم نمی‌شود). برچسب `churn` با مقدار `"true"` یا `"false"` آن را به دو سری جدا تقسیم می‌کند، پس می‌توانیم بپرسیم «چند پیش‌بینی churn داشتیم و چند پیش‌بینی ماندگار».
- نوع `Histogram` می‌شمارد چند مشاهده در هر بازه‌ی زمانی (bucket) افتاد. با آن درخواست‌های کند را می‌بینید، مثلاً «۹۵ درصد پیش‌بینی‌ها زیر ۵ میلی‌ثانیه بود».

چرا در سطح ماژول؟ هر متریک باید در هر پروسه **فقط یک بار** ساخته شود. اگر داخل تابع ساخته شود، ساخت دوباره با خطای «Duplicated timeseries» تمام می‌شود. در جلسه‌های مانیتورینگ Prometheus همین دو متریک را جمع می‌کند و Grafana نشان می‌دهد.

### لاگ JSON

```python
class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {"ts": self.formatTime(record), "level": record.levelname, "event": record.msg}
        # We pass extra fields as log.info("x", extra={"fields": {...}}); logging stores
        # them as record.fields. getattr(..., {}) = empty dict when a log has no extras.
        entry.update(getattr(record, "fields", {}))
        return json.dumps(entry)
```

چرا JSON؟ لاگ متنی را فقط آدم می‌خواند. ابزارهایی مثل Loki یا Elasticsearch لاگ JSON را فیلد به فیلد می‌فهمند و می‌شود مثلاً همه‌ی درخواست‌های `status=500` را جست‌وجو کرد. `Formatter` در Python تعیین می‌کند هر رکورد لاگ چطور به متن تبدیل شود. فیلدهای اضافه را با `extra={"fields": {...}}` می‌فرستیم و `getattr(..., {})` برای لاگ‌هایی است که فیلد اضافه ندارند.

```python
log = logging.getLogger("churn.api")
_handler = logging.StreamHandler()
_handler.setFormatter(JsonFormatter())
log.addHandler(_handler)
log.setLevel(logging.INFO)  # INFO and above (INFO, WARNING, ERROR) are printed
log.propagate = False  # do not also send records to the root logger (no duplicate lines)
```

یک logger نام‌دار می‌سازیم، یک handler (خروجی stderr) با فرمت JSON به آن می‌دهیم و `propagate = False` می‌گذاریم تا هر خط دوبار (یک بار JSON و یک بار متن معمولی) چاپ نشود. به همین دلیل در `Makefile` گزینه‌ی `--no-access-log` را برای uvicorn گذاشته‌ایم.

### کلاس `Customer`: قرارداد ورودی و `extra="forbid"`

```python
class Customer(BaseModel):
    # extra="forbid": an unknown field (e.g. "discount") is an error, not silently ignored.
    # json_schema_extra: puts EXAMPLE in the /docs page so "Try it out" is pre-filled.
    model_config = ConfigDict(extra="forbid", json_schema_extra={"examples": [EXAMPLE]})

    # Field(ge=0, le=120): "greater or equal 0" and "less or equal 120" (a sanity range).
    tenure_months: float = Field(ge=0, le=120)
    monthly_charges: float = Field(gt=0, le=500)  # gt = strictly greater than 0
    # Literal[...]: only these exact strings are accepted (a closed set of categories).
    contract: Literal["month-to-month", "one-year", "two-year"]
    internet_service: Literal["dsl", "fiber", "none"]
    payment_method: Literal["card", "bank_transfer", "cash"]
    support_calls: int = Field(ge=0, le=50)  # int: 1.5 is rejected (the signature says long)
```

این کلاس شکل درخواست `/predict` را تعریف می‌کند. pydantic هر JSON ورودی را با آن مقایسه می‌کند. اگر فیلدی کم باشد، اضافه باشد، نوعش غلط باشد یا عددش خارج از بازه باشد، خطای ۴۲۲ (Unprocessable Entity) می‌گیرید و **مدل اصلاً صدا زده نمی‌شود**. یعنی داده‌ی بد هرگز به مدل نمی‌رسد.

نکته‌های مهم:

- گزینه‌ی `extra="forbid"`: فیلد ناشناخته (مثلاً `discount`) خطا است. بدون این گزینه pydantic آن را بی‌صدا نادیده می‌گرفت و کلاینت فکر می‌کرد تخفیف در پیش‌بینی اثر دارد.
- قید `Field(ge=0, le=120)`: بازه‌ی منطقی. `ge` یعنی بزرگ‌تر یا مساوی و `le` یعنی کوچک‌تر یا مساوی. `gt` یعنی اکیداً بزرگ‌تر.
- نوع `Literal[...]`: فقط همین رشته‌های دقیق پذیرفته می‌شوند (مجموعه‌ی بسته‌ی دسته‌ها). `weekly` برای `contract` رد می‌شود.
- فیلد `support_calls: int`: مقدار `1.5` رد می‌شود، چون signature مدل نوع این ستون را `long` (عدد صحیح) می‌گوید.
- گزینه‌ی `json_schema_extra`: نمونه‌ی `EXAMPLE` را در صفحه‌ی `/docs` می‌گذارد تا دکمه‌ی «Try it out» از قبل پر باشد.

### کلاس `Prediction`

```python
class Prediction(BaseModel):
    churn_probability: float
    churn: bool
    threshold: float
    model_version: str
```

شکل پاسخ `/predict`: احتمال، تصمیم بله یا نه، آستانه‌ی استفاده‌شده و نسخه‌ی مدل. نسخه‌ی مدل در جواب می‌آید تا اگر بعداً `@champion` عوض شد، بتوان فهمید هر پیش‌بینی را کدام نسخه داده است.

### تابع `contract_mismatches`

```python
SIGNATURE_TYPES = {"double": float, "float": float, "long": int, "integer": int, "string": str}
```

```python
    problems = []
    # dict comprehension: {"tenure_months": float, ..., "contract": Literal[...]}
    fields = {name: f.annotation for name, f in Customer.model_fields.items()}
    for col in signature_inputs:
        # SIGNATURE_TYPES.get(...) gives None for a type we do not know (always a mismatch)
        name, expected = col["name"], SIGNATURE_TYPES.get(col["type"])
        if name not in fields:
            problems.append(f"missing field '{name}' ({col['type']})")
            continue  # nothing to compare for this column, go to the next one
        actual = fields.pop(name)  # pop = remove, so what is left at the end is "extra"
        # A Literal[...] field is a string in JSON; its __origin__ is `Literal`.
        actual = str if getattr(actual, "__origin__", None) is Literal else actual
        if actual is not expected:
            problems.append(f"field '{name}' is {actual.__name__}, signature says {col['type']}")
    # Whatever remains in `fields` was never seen in the signature.
    problems += [f"extra field '{name}' (not in the signature)" for name in fields]
    return problems
```

مفهوم signature مدل فهرست ستون‌ها و نوع هر ستون است. این تابع `Customer` را با آن مقایسه می‌کند و سه نوع ناسازگاری پیدا می‌کند:

1. ستونی در مدل هست ولی در `Customer` نیست (`missing field`).
2. نوع فیلد با نوع ستون فرق دارد، مثلاً `int` در مقابل `double`.
3. فیلدی در `Customer` هست که مدل نمی‌شناسد (`extra field`).

ترفند الگوریتم: فیلدهای `Customer` را در یک dict می‌ریزد و هر ستون signature را که دید با `pop` از dict بیرون می‌کشد. آنچه آخر کار در dict می‌ماند، فیلد اضافه است. خروجی فهرست مشکل‌ها است و فهرست خالی یعنی API و مدل هم‌نظرند. چون این تابع MLflow را صدا نمی‌زند، تستش آسان است.

### تابع `load_registered_model`: حل یک‌باره‌ی alias

```python
    check_download_setting()  # without this env variable load_model would hang forever
    client = connect()
    path = uri.removeprefix("models:/")  # "churn@champion" or "churn/3"
    if "@" in path:
        name, alias = path.split("@")  # unpack the two parts
        mv = client.get_model_version_by_alias(name, alias)  # alias -> a concrete version
    else:
        name, version = path.split("/")
        mv = client.get_model_version(name, version)
    # Load by number, not by alias: exactly the version we just resolved.
    model = mlflow.sklearn.load_model(f"models:/{name}/{mv.version}")
    return model, {"uri": uri, "name": name, "version": str(mv.version), "run_id": mv.run_id}
```

چرا alias را یک بار «حل» می‌کنیم؟ alias یک برچسب متحرک است. اگر مستقیم `models:/churn@champion` را لود کنیم و همان لحظه کسی `promote` بزند، ممکن است بخشی از کار با نسخه‌ی قدیمی و بخشی با نسخه‌ی جدید انجام شود. پس اول می‌پرسیم alias الان به کدام شماره‌ی نسخه اشاره می‌کند و بعد **همان شماره** را لود می‌کنیم (`models:/churn/3`). شماره‌ی نسخه را هم برای `/model-info` و لاگ نگه می‌داریم.

دو شکل آدرس پشتیبانی می‌شود: `models:/churn@champion` (با alias) و `models:/churn/3` (با شماره‌ی نسخه).

خط اول، `check_download_setting()`، همان نگهبان جلسه‌ی ۷ است. بدون متغیر `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false`، دانلود مدل از لپ‌تاپ بدون هیچ خطایی برای همیشه گیر می‌کند. نگهبان یا `connect` در صورت مشکل `SystemExit` پرتاب می‌کنند؛ این نکته در بخش `lifespan` مهم می‌شود.

خروجی تابع یک tuple است: خود مدل (sklearn Pipeline) و یک dict با `uri`، `name`، `version` و `run_id`.

### تابع `create_app(loader)`: ترفند تست

```python
def create_app(loader: Callable = load_registered_model) -> FastAPI:
```

چرا همه‌چیز داخل یک تابع است و `loader` پارامتر دارد؟ **برای تست.** در تست‌ها به جای `load_registered_model` (که به MLflow وصل می‌شود) یک تابع کوچک می‌دهیم که مدل محلی برمی‌گرداند. بقیه‌ی کد دقیقاً همان چیزی است که در production اجرا می‌شود. به این الگو می‌گویند «تزریق وابستگی» (dependency injection) ساده.

سطر آخر فایل یک `app` با loader واقعی می‌سازد که uvicorn آن را اجرا می‌کند:

```python
# The real app that `uvicorn churn.api:app` imports. Importing does NOT load the model:
# that happens in `lifespan`, when the server starts.
app = create_app()
```

با import کردن فایل مدل را لود نمی‌کند؛ لود در `lifespan` و هنگام روشن شدن سرور انجام می‌شود. به همین دلیل تست‌ها می‌توانند فایل را import کنند بدون اینکه به MLflow وصل شوند.

#### `lifespan`: لود مدل هنگام شروع و چرا `SystemExit` گرفته می‌شود

```python
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        # Start in the "not ready" state: no model yet. /ready will answer 503 until set.
        app.state.model, app.state.info = None, {"uri": MODEL_URI}
        start = time.perf_counter()  # perf_counter = accurate clock for measuring durations
        try:
            app.state.model, app.state.info = loader(MODEL_URI)
        except (Exception, SystemExit) as e:  # stay alive but NOT ready
            # SystemExit is not an Exception subclass, and check_download_setting/connect
            # raise it, so it must be listed explicitly. If we did not catch it, the whole
            # server would die; Kubernetes would restart it again and again (crash loop)
            # instead of just reporting "not ready".
            log.error("model_load_failed", extra={"fields": {"uri": MODEL_URI, "error": str(e)}})
        else:  # runs only if the try block had no exception
            secs = round(time.perf_counter() - start, 2)
            # {**a, "k": v} = a new dict with everything from a plus one more key
            log.info("model_loaded", extra={"fields": {**app.state.info, "seconds": secs}})
        yield  # the server runs (and serves requests) while we are suspended here
```

مفهوم `lifespan` کدی است که هنگام روشن و خاموش شدن سرور اجرا می‌شود. هرچه قبل از `yield` باشد یک بار هنگام شروع اجرا می‌شود (اینجا لود مدل). هرچه بعد از آن باشد هنگام خاموش شدن (اینجا چیزی نداریم). مدل را در `app.state` می‌گذاریم تا همه‌ی endpointها به آن دسترسی داشته باشند و برای هر درخواست دوباره لود نشود، چون لود چند ثانیه طول می‌کشد.

مراحل:

1. اول وضعیت «آماده نیست» را می‌گذاریم: `model = None`. تا مدل لود نشود، `/ready` جواب ۵۰۳ می‌دهد.
2. زمان شروع را می‌گیریم تا مدت لود را لاگ کنیم.
3. تابع `loader(MODEL_URI)` را صدا می‌زنیم. اگر موفق بود، مدل و اطلاعاتش جای مقدارهای اولیه می‌نشینند و لاگ `model_loaded` با مدت لود نوشته می‌شود (بلوک `else`).
4. اگر شکست خورد، لاگ `model_load_failed` با متن خطا نوشته می‌شود.

**چرا `SystemExit` را صریح می‌گیریم؟** این یک نکته‌ی ظریف و مهم است:

- کلاس `SystemExit` زیرکلاس `Exception` **نیست** (زیرکلاس `BaseException` است). پس `except Exception` آن را نمی‌گیرد.
- ولی `check_download_setting()` و `connect()` (از جلسه‌ی ۷) در صورت مشکل دقیقاً `SystemExit` پرتاب می‌کنند. دلیلش این بود که در اسکریپت، پیام تمیز بدون traceback می‌خواستیم.
- اگر این استثنا گرفته نشود، کل سرور می‌میرد. در Kubernetes، پروسه‌ای که می‌میرد دوباره راه‌اندازی می‌شود و دوباره می‌میرد (crash loop) و شما فقط می‌بینید pod مدام restart می‌شود.
- با گرفتن آن، سرویس **زنده می‌ماند ولی آماده نیست**: `/health` جواب ۲۰۰ می‌دهد، `/ready` و `/predict` جواب ۵۰۳. علت در لاگ JSON نوشته شده است.

در آزمایش واقعی جلسه: وقتی سرور MLflow خاموش بود و API را بالا آوردیم، `/ready` برابر ۵۰۳ شد. بعد از روشن کردن MLflow هم `/ready` **همچنان ۵۰۳ ماند**، چون مدل فقط هنگام شروع لود می‌شود. باید API را restart کرد. این نکته در جلسه‌ی Kubernetes دوباره می‌آید: readiness probe ترافیک را از این نسخه دور نگه می‌دارد و restart یا rollout مدل را لود می‌کند.

#### ثبت `Instrumentator` و `/metrics`

```python
    app = FastAPI(title="Churn inference API", version="0.6.0", lifespan=lifespan)
    # Adds the /metrics endpoint with HTTP metrics (http_requests_total, latency...) and
    # also exposes our own PREDICTIONS / LATENCY from the default Prometheus registry.
    Instrumentator().instrument(app).expose(app, include_in_schema=False)
```

ابزار `Instrumentator` آدرس `/metrics` را اضافه می‌کند. این آدرس هم متریک‌های آماده‌ی HTTP (مثل `http_requests_total`) را دارد و هم `PREDICTIONS` و `LATENCY` خودمان را، چون در registry پیش‌فرض Prometheus ثبت شده‌اند. گزینه‌ی `include_in_schema=False` آن را از صفحه‌ی `/docs` پنهان می‌کند.

#### middleware به نام `access_log`

```python
    @app.middleware("http")
    async def access_log(request: Request, call_next):
        start = time.perf_counter()
        response = await call_next(request)  # run the real endpoint and wait for its response
        ms = round((time.perf_counter() - start) * 1000, 1)  # seconds -> milliseconds
        fields = {"method": request.method, "path": request.url.path}
        log.info("request", extra={"fields": {**fields, "status": response.status_code, "ms": ms}})
        return response
```

مفهوم middleware کدی است که دور هر درخواست اجرا می‌شود: قبل از endpoint، خود endpoint (`call_next`) و بعد از آن. این‌جا فقط زمان را اندازه می‌گیریم و بعد از آماده شدن پاسخ، یک خط لاگ می‌نویسیم (متد، مسیر، status و میلی‌ثانیه). **بدنه‌ی درخواست را عمداً لاگ نمی‌کنیم**، چون ممکن است داده‌ی شخصی مشتری باشد.

#### endpointهای `/health` و `/ready`: liveness در برابر readiness

```python
    @app.get("/health")
    def health() -> dict:
        return {"status": "ok"}

    @app.get("/ready")
    def ready(request: Request) -> dict:
        # request.app.state: the same object the lifespan filled at startup
        if request.app.state.model is None:
            raise HTTPException(503, "model not loaded")
        return {"status": "ready", "model_version": request.app.state.info["version"]}
```

این دو endpoint ظاهراً شبیه‌اند ولی دو سؤال متفاوت جواب می‌دهند، و تفاوتشان یکی از سؤال‌های مهم کلاس است:

- **سلامت پروسه (liveness، آدرس `/health`):** «آیا پروسه زنده است؟» عمداً به مدل وابسته نیست. اگر جواب ندهد، Kubernetes پروسه را **restart** می‌کند. اگر به مدل وابسته بود، خرابی موقت MLflow باعث restart بی‌پایان می‌شد.
- **آمادگی (readiness، آدرس `/ready`):** «آیا آماده‌ام درخواست بگیرم؟» فقط وقتی مدل لود شده ۲۰۰ می‌دهد. وگرنه ۵۰۳ می‌دهد و Kubernetes ترافیک را به این نسخه **نمی‌فرستد** (ولی restart هم نمی‌کند).

قاعده‌ی ساده: liveness برای تصمیم «بکشمش؟» است و readiness برای تصمیم «ترافیک بدهم؟».

شیء `request.app.state` همان شیئی است که `lifespan` هنگام شروع پر کرد.

#### endpoint به نام `/model-info`

```python
    @app.get("/model-info")
    def model_info(request: Request) -> dict:
        return {**request.app.state.info, "threshold": THRESHOLD}
```

نشان می‌دهد کدام مدل سرو می‌شود: `uri`، `name`، `version`، `run_id` و آستانه‌ی تصمیم. بعد از `promote` و restart، این آدرس نسخه‌ی جدید را نشان می‌دهد.

#### endpoint به نام `/predict`

```python
    @app.post("/predict")
    def predict(customer: Customer, request: Request) -> Prediction:
        model, info = request.app.state.model, request.app.state.info
        if model is None:
            raise HTTPException(503, "model not loaded")
        # The model expects a table: one row, columns named like in the training data.
        X = pd.DataFrame([customer.model_dump()])
        with LATENCY.time():  # records how long the block takes into the histogram
            # predict_proba -> [[P(stay), P(churn)]]; [0, 1] = first row, churn column
            proba = round(float(model.predict_proba(X)[0, 1]), 4)
        # Strictly greater: a probability exactly equal to the threshold counts as "no churn".
        churn = proba > THRESHOLD  # same rule as evaluate.py
        # Label values must be strings: True -> "true"
        PREDICTIONS.labels(churn=str(churn).lower()).inc()
        # Log only the version and the probability, not the customer's data (privacy).
        log.info("prediction", extra={"fields": {"version": info["version"], "proba": proba}})
```

پارامتر `customer: Customer` یعنی FastAPI خودش JSON بدنه را می‌خواند و با pydantic چک می‌کند. اگر غلط باشد، این تابع **اصلاً اجرا نمی‌شود** (کد ۴۲۲). خروجی هم با `Prediction` چک و به JSON تبدیل می‌شود.

مراحل داخل تابع:

1. اگر مدل لود نشده، ۵۰۳ (دفاع دوم، علاوه بر `/ready`).
2. مدل جدول می‌خواهد، پس مشتری را به یک `DataFrame` با یک ردیف تبدیل می‌کنیم.
3. عبارت `LATENCY.time()` مدت اجرای بلوک را در histogram ثبت می‌کند.
4. تابع `predict_proba` دو ستون برمی‌گرداند و `[0, 1]` یعنی ردیف اول، ستون احتمال churn.
5. تصمیم: احتمال **اکیداً بزرگ‌تر** از آستانه یعنی churn. اگر دقیقاً مساوی باشد، «churn نیست». همین قانون در `evaluate.py` هم هست.
6. شمارنده‌ی `PREDICTIONS` یکی زیاد می‌شود. مقدار برچسب باید رشته باشد، پس `True` به `"true"` تبدیل می‌شود.
7. لاگ فقط نسخه و احتمال را می‌نویسد، نه مشخصات مشتری (حریم خصوصی).

---

## فایل `scripts/check_contract.py`

**کار فایل:** یک «بازرسی» پیش از deploy است. آیا فیلدهای `Customer` (چیزی که API از کاربر می‌پذیرد) دقیقاً با ستون‌هایی که مدل `@champion` موقع آموزش دیده (signature) یکی است؟ اگر کسی ویژگی جدیدی به مدل اضافه کند ولی API را عوض نکند، این اسکریپت قبل از deploy خطا می‌دهد.

**اجرا** (با سرور MLflow روشن):

```bash
make contract
```

**ورودی و خروجی:** ورودی signature مدل `@champion` است. خروجی فهرست ستون‌ها و نوع‌ها روی صفحه است و در پایان یا `contract OK` یا فهرست `MISMATCH` با exit code برابر ۱. فایلی نوشته نمی‌شود.

```python
# connect() sets the tracking URI as a side effect; we do not need the client it returns.
connect()
# Only the model's metadata (signature) is read here: the model files are NOT downloaded.
signature = mlflow.models.get_model_info(MODEL_URI).signature
# to_dict() gives a list like [{"name": "tenure_months", "type": "double", ...}, ...]
inputs = signature.inputs.to_dict()
```

فقط metadata مدل (signature) خوانده می‌شود و فایل‌های مدل دانلود **نمی‌شوند**؛ به همین دلیل این اسکریپت سریع است و نیازی به متغیر `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD` ندارد. از `connect()` فقط برای اثر جانبی‌اش (تنظیم آدرس سرور) استفاده می‌کنیم.

```python
for col in inputs:
    print(f"  {col['name']:16} {col['type']}")  # :16 = pad the name to 16 characters (a table)
problems = contract_mismatches(inputs)  # empty list = the API and the model agree
for p in problems:
    print(f"  MISMATCH {p}")
if problems:
    # SystemExit with a string: prints it to stderr and exits with code 1 (fails CI / make)
    raise SystemExit(f"contract does NOT match {MODEL_URI}")
print(f"contract OK: Customer matches the signature of {MODEL_URI}")
```

منطق مقایسه در تابع `contract_mismatches` در `churn/api.py` است؛ این اسکریپت فقط آن را صدا می‌زند و نتیجه را زیبا چاپ می‌کند. اگر مشکلی باشد، `SystemExit` با یک رشته پیام را روی stderr می‌نویسد و با کد ۱ خارج می‌شود تا `make` و CI شکست را بفهمند.

---

## فایل `tests/test_api.py`

**کار فایل:** یازده تست برای API که با یک مدل کوچک محلی کار می‌کنند و به MLflow، Docker یا شبکه نیاز ندارند.

**اجرا:**

```bash
make test
```

ترفند اصلی: `create_app(loader=...)` اجازه می‌دهد به جای لود از MLflow، یک مدل محلی بدهیم. `TestClient` هم بدون روشن کردن سرور واقعی (uvicorn) درخواست HTTP را شبیه‌سازی می‌کند.

### داده‌های ثابت تست

```python
CUSTOMER = {
    "tenure_months": 3,
    "monthly_charges": 95.5,
    "contract": "month-to-month",
    "internet_service": "fiber",
    "payment_method": "card",
    "support_calls": 4,
}
```

یک درخواست معتبر، هم‌شکل `Customer`. تست‌های خطا یک فیلد این dict را خراب می‌کنند. ثابت `SIGNATURE` هم همان چیزی است که MLflow به‌عنوان signature مدل گزارش می‌کند (نام ستون و نوع MLflow).

### fixtureهای `model` و `client`

```python
@pytest.fixture(scope="module")
def model():
    train, _ = split(make(rows=600, seed=1), 0.25, 42)
    X = train.drop(columns=["churn"])
    return build_model(X, C=0.1, max_iter=200).fit(X, train["churn"])
```

گزینه‌ی `scope="module"` یعنی pytest این fixture را فقط یک بار اجرا می‌کند و نتیجه را بین همه‌ی تست‌های این فایل به اشتراک می‌گذارد. آموزش دادن در هر تست وقت تلف می‌کرد.

```python
@pytest.fixture
def client(model):
    # loader is a lambda: it ignores the real registry and returns our local model plus
    # a fake info dict (version "7") that we can recognise in the assertions.
    app = create_app(loader=lambda uri: (model, {"uri": uri, "version": "7", "run_id": "local"}))
    with TestClient(app) as c:  # "with" runs the startup (lifespan) that loads the model
        yield c
```

اینجا ترفند `create_app(loader)` را در عمل می‌بینید. `loader` یک `lambda` است که Registry واقعی را نادیده می‌گیرد و مدل محلی را با نسخه‌ی ساختگی `"7"` برمی‌گرداند. نسخه‌ی ۷ را عمداً انتخاب کرده‌ایم تا در assertionها به‌راحتی شناخته شود. هر تست یک app تازه می‌گیرد تا state بین تست‌ها قاطی نشود. نکته: بدون `with`، مرحله‌ی startup (`lifespan`) اجرا نمی‌شود و مدل لود نمی‌شود.

### تست‌های health، ready و predict

```python
def test_health_and_ready(client):
    assert client.get("/health").json() == {"status": "ok"}
    assert client.get("/ready").json() == {"status": "ready", "model_version": "7"}
```

هر دو endpoint سلامت وقتی مدل لود شده ۲۰۰ می‌دهند و نسخه‌ی مدل در `/ready` دیده می‌شود.

```python
    r = client.post("/predict", json=CUSTOMER)
    assert r.status_code == 200
    body = r.json()
    assert 0 <= body["churn_probability"] <= 1
    # the decision must follow the same rule as evaluate.py: probability > threshold (0.5)
    assert body["churn"] == (body["churn_probability"] > 0.5)
    assert body["model_version"] == "7"
```

جواب `/predict` باید احتمال بین ۰ و ۱ باشد، تصمیم هماهنگ با آستانه داشته باشد و نسخه‌ی مدل را برگرداند.

### تست ورودی بد با `parametrize`

```python
# parametrize runs the test below once per item: 4 bad inputs, 4 separate test results.
@pytest.mark.parametrize(
    "change",
    [
        {"contract": "weekly"},  # not one of the 3 known values
        {"support_calls": 1.5},  # long in the signature
        {"tenure_months": -1},  # out of range
        {"discount": 10},  # unknown field
    ],
)
def test_bad_input_is_rejected_with_422(client, change):
    assert client.post("/predict", json={**CUSTOMER, **change}).status_code == 422
```

دکوراتور `parametrize` همین تست را برای هر عضو فهرست یک بار اجرا می‌کند: چهار ورودی بد و چهار نتیجه‌ی جدا. هر مورد یکی از سازوکارهای `Customer` را آزمایش می‌کند: دسته‌ی ناشناخته (`Literal`)، نوع غلط (`int`)، خارج از بازه (`ge`) و فیلد اضافه (`extra="forbid"`). عبارت `{**CUSTOMER, **change}` یک کپی از مشتری درست است که فقط یک فیلد در آن خراب شده (کلیدهای `change` مقدارهای قبلی را بازنویسی می‌کنند).

```python
    body = {k: v for k, v in CUSTOMER.items() if k != "contract"}
    r = client.post("/predict", json=body)
    assert r.status_code == 422
    # FastAPI's error list says where the problem is: in the body, field "contract"
    assert r.json()["detail"][0]["loc"] == ["body", "contract"]
```

نبودن یک فیلد هم ۴۲۲ می‌دهد و خطا دقیقاً می‌گوید کدام فیلد کم است (`loc` یعنی «محل خطا»).

### تست «مدل لود نشد»

```python
    def broken(uri):
        raise SystemExit("MLflow server not reachable")

    with TestClient(create_app(loader=broken)) as c:  # "with" = run the startup (lifespan)
        assert c.get("/health").status_code == 200
        assert c.get("/ready").status_code == 503
        assert c.post("/predict", json=CUSTOMER).status_code == 503
```

این تست درس `lifespan` را ثابت می‌کند. `loader` ساختگی عمداً `SystemExit` پرتاب می‌کند، چون `connect()` و `check_download_setting()` واقعی هم همین کار را می‌کنند. اگر `lifespan` فقط `Exception` را می‌گرفت، این تست با مرگ کل برنامه شکست می‌خورد. نتیجه‌ی درست: `/health` برابر ۲۰۰ و `/ready` و `/predict` برابر ۵۰۳.

### تست شمارنده‌ی `/metrics`

```python
    def predictions(text):
        lines = [x for x in text.splitlines() if x.startswith("churn_predictions_total{")]
        # each line looks like: churn_predictions_total{churn="true"} 3.0 -> take the last word
        return sum(float(x.split()[-1]) for x in lines)

    before = predictions(client.get("/metrics").text)
    client.post("/predict", json=CUSTOMER)
    text = client.get("/metrics").text
    assert predictions(text) == before + 1
```

هر `/predict` موفق باید شمارنده را دقیقاً یکی زیاد کند. شمارنده‌های Prometheus بین تست‌ها در حافظه‌ی همین پروسه می‌مانند، پس مقدار «قبل» و «بعد» را مقایسه می‌کنیم و عدد مطلق را نه. تابع داخلی `predictions` خطوط متن `/metrics` را جمع می‌زند (برچسب `true` و `false` را با هم).

### تست قرارداد

```python
    assert contract_mismatches(SIGNATURE) == []
    # [*a, b] = a new list: the first five columns plus one changed column (long -> double)
    wrong = [*SIGNATURE[:5], {"name": "support_calls", "type": "double"}]
    assert contract_mismatches(wrong) == ["field 'support_calls' is int, signature says double"]
```

قرارداد `Customer` با signature درست یکی است، و اگر نوع یک ستون عوض شود (`long` به `double`)، تابع دقیقاً همان مشکل را گزارش می‌کند.

### تست لود از Registry

```python
    # one loop, two URI styles: by alias and by explicit version number
    for uri in ("models:/churn@challenger", "models:/churn/1"):
        loaded, info = load_registered_model(uri)
        assert info["version"] == "1" and info["run_id"] == run_id
        # 3 rows in -> a (3, 2) array out: two probabilities (stay, churn) per row
        assert loaded.predict_proba(test.drop(columns=["churn"]).head(3)).shape == (3, 2)
```

این تست یک Registry موقت با SQLite می‌سازد (بدون سرور)، با `register` از جلسه‌ی ۷ یک مدل ثبت می‌کند و بعد `load_registered_model` را با هر دو شکل آدرس صدا می‌زند. هر دو باید همان نسخه‌ی ۱ و همان run را لود کنند. متغیر `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false` را با `monkeypatch.setenv` می‌گذاریم، چون خود تابع آن را چک می‌کند.

---

## فایل `Makefile`

**کار فایل:** این Makefile شامل هدف‌های جلسه‌های قبل و دو هدف تازه است.

```makefile
PORT ?= 8000
```

متغیر `PORT` پورت API است و پیش‌فرضش ۸۰۰۰ است. علامت `?=` یعنی فقط اگر مقدارش قبلاً داده نشده باشد. می‌توانید با `make serve PORT=9000` عوضش کنید.

```makefile
contract:
	uv run python scripts/check_contract.py
```

هدف `contract`: ورودی API را با signature مدل `@champion` مقایسه می‌کند.

```makefile
serve:
	uv run uvicorn churn.api:app --host 127.0.0.1 --port $(PORT) --no-access-log
```

هدف `serve`: API را با uvicorn روی لوکال‌هاست بالا می‌آورد. عبارت `churn.api:app` یعنی «در ماژول `churn.api` شیء `app` را اجرا کن». گزینه‌ی `--no-access-log` لاگ دسترسی خود uvicorn را خاموش می‌کند، چون API لاگ JSON خودش را دارد (middleware به نام `access_log`). برای اجرا به `@champion` و متغیرهای فایل `.env` نیاز دارید.

جلوی خط‌های دستور باید TAB باشد، نه فاصله.

---

## پرسش‌هایی برای فکر کردن

1. اگر `lifespan` فقط `except Exception` داشت و MLflow خاموش بود، در Kubernetes چه اتفاقی می‌افتاد؟ چرا `SystemExit` از این دسته نیست؟
2. اگر `/health` هم مثل `/ready` به لود شدن مدل وابسته بود، خرابی چند دقیقه‌ای MLflow چه بلایی بر سر سرویس می‌آورد؟
3. چرا `extra="forbid"` را گذاشته‌ایم؟ اگر کلاینت فیلد `discount` را بفرستد و pydantic بی‌صدا نادیده بگیرد، چه سوءتفاهمی ممکن است پیش بیاید؟

</div>
