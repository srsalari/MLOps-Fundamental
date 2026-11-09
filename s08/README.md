<div dir="rtl">

# آزمایشگاه جلسه‌ی ۸ — سرویس استنتاج (Inference) با FastAPI

در این آزمایشگاه مدل `models:/churn@champion` را که در جلسه‌ی ۷ در Model Registry ساختید، پشت یک **API** می‌گذارید تا هر برنامه‌ای (مرورگر، `curl`، یک سرویس دیگر) با یک درخواست HTTP احتمال churn یک مشتری را بگیرد. ورودی را با یک **قرارداد** (pydantic) کنترل می‌کنید، خطا را با کد درست (۴۲۲ و ۵۰۳) برمی‌گردانید، لاگ ساخت‌یافته (JSON) می‌نویسید و یک صفحه‌ی `/metrics` می‌سازید که جلسه‌ی ۱۳ (Prometheus) از آن می‌خواند.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۷ سالم باشد: `main` شامل tag `v0.5.0` است و Registry مدل `churn` را با `@champion` دارد (`docker compose down -v` نزده باشید).
2. مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s08
```

3. سرویس‌ها را روشن کنید:

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow
```

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK`

در این جلسه **دو ترمینال** لازم دارید. ترمینال ۱ برای کار اصلی است و ترمینال ۲ فقط سرور API را اجرا می‌کند (تا وقتی سرور روشن است آن ترمینال مشغول است). هر دو در پوشه‌ی `~/work/churn-mlops` کار می‌کنند، مگر جایی که گفته شده. اگر ترمینال را بستید، خط `K=...` و دستور `source` گام ۱ را دوباره بزنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell.

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| API | راهی که برنامه‌ها با هم حرف می‌زنند؛ اینجا یک «در» روی شبکه که مدل پشت آن است |
| REST | سبک ساده‌ی API روی HTTP: آدرس (`/predict`)، روش (`GET` برای خواندن، `POST` برای فرستادن داده) و جواب JSON |
| endpoint | یک آدرس مشخص از API، مثل `/health` یا `/predict` |
| FastAPI | کتابخانه‌ی پایتون برای ساختن API؛ مستندات تعاملی را خودش در `/docs` می‌سازد |
| uvicorn | برنامه‌ای که کد FastAPI را اجرا می‌کند و به پورت گوش می‌دهد |
| pydantic | کتابخانه‌ای که شکل و نوع ورودی را کنترل می‌کند؛ ورودی غلط، پیش از رسیدن به مدل رد می‌شود |
| قرارداد ورودی | کلاس `Customer` در `api.py`؛ باید با signature مدل (جلسه‌ی ۷) هم‌خوان باشد |
| `422` | کد HTTP برای «درخواست شکل درستی ندارد»؛ تقصیر فرستنده است |
| `503` | کد HTTP برای «سرویس فعلاً نمی‌تواند جواب دهد»؛ اینجا یعنی مدل بار نشده |
| liveness (`/health`) | «برنامه زنده است؟» همیشه `ok` برمی‌گرداند، حتی اگر مدل بار نشده باشد |
| readiness (`/ready`) | «برنامه آماده‌ی کار است؟» فقط وقتی مدل بار شده `200` می‌دهد؛ در جلسه‌ی ۱۱ Kubernetes با آن ترافیک را هدایت می‌کند |
| لاگ ساخت‌یافته | هر خط لاگ یک شیء JSON است (`event`، `status`، `ms`، …)؛ جست‌وجو و جمع‌آوری آن آسان است |
| `/metrics` | شمارنده‌ها و زمان‌ها با قالب Prometheus؛ جلسه‌ی ۱۳ آن را می‌خواند |

یک نکته‌ی مهم: سرویس alias یعنی `@champion` را **فقط یک بار، هنگام روشن شدن** به شماره‌ی نسخه تبدیل می‌کند و مدل را در حافظه نگه می‌دارد. پس اگر بعداً `@champion` به نسخه‌ی دیگری برود، سرویسی که روشن است همان مدل قبلی را نشان می‌دهد تا دوباره راه‌اندازی شود. این را در گام ۴ و تکلیف می‌بینید.

## نتیجه‌ی نهایی

- <bdi dir="rtl">API روی `http://localhost:8000` با آدرس‌های `/health`، `/ready`، `/model-info`، `/predict`، `/metrics` و `/docs`</bdi>
- ورودی غلط جواب `422` می‌گیرد و وقتی مدل بار نشده جواب `503`
- یازده آزمون API که بدون سرور اجرا می‌شوند
- کد در Git با tag نسخه‌ی `v0.6.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `churn/api.py` | `src/churn/` | خود API: قرارداد `Customer`، بار کردن مدل، endpointها، لاگ JSON و `/metrics` |
| `scripts/check_contract.py` | `scripts/` | مقایسه‌ی `Customer` با signature مدل `@champion` |
| `tests/test_api.py` | `tests/` | یازده آزمون (بدون نیاز به سرور) |
| `examples/` | ریشه‌ی پروژه | سه نمونه‌ی ورودی JSON: `customer.json`، `loyal_customer.json`، `bad_customer.json` |
| `Makefile` | ریشه‌ی پروژه | هدف‌های تازه‌ی `contract` و `serve` |

توضیح خط‌به‌خط کد این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — وضعیت شروع و وابستگی‌ها (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git switch -c feature/inference-api
```

متغیرهای `.env` را در این ترمینال بار کنید (نشانی MLflow و تنظیم دانلود مدل در آن است):

```bash
set -a; source .env; set +a
```

```bash
git describe --tags
```

انتظار: `v0.5.0` (اگر تکلیف جلسه‌ی ۷ را merge کرده‌اید چیزی مثل `v0.5.0-2-g1a2b3c4` می‌بینید؛ مشکلی نیست)

حالا کتابخانه‌ها را به پروژه اضافه کنید:

```bash
uv add fastapi==0.143.2 uvicorn==0.54.0 prometheus-fastapi-instrumentator==8.1.0
```

انتظار: `Installed 3 packages` (در سیستم شما ممکن است تعداد یا ترتیب فرق کند).

<bdi dir="rtl">`fastapi` و `uvicorn` از پیش نصب بودند، چون خود MLflow به آن‌ها وابسته است. `uv add` فقط نسخه‌ی آن‌ها را در `pyproject.toml` و `uv.lock` **قفل (pin)** می‌کند تا پروژه‌ی شما به MLflow وابسته نماند و همه‌ی دانشجوها یک نسخه داشته باشند. کتابخانه‌ی تازه فقط `prometheus-fastapi-instrumentator` (و `prometheus-client` همراه آن) است.</bdi>

کتابخانه‌ی آزمون را به‌عنوان وابستگی توسعه اضافه کنید:

```bash
uv add --dev httpx2==2.13.1
```

چرا `httpx2` و نه `httpx`؟ آزمون‌های FastAPI با `TestClient` بدون سرور واقعی درخواست می‌فرستند و این کار به یک کتابخانه‌ی HTTP نیاز دارد. نسخه‌ی جدید Starlette اول `httpx2` را می‌خواهد؛ اگر فقط `httpx` نصب باشد آزمون‌ها پاس می‌شوند ولی هشدار `StarletteDeprecationWarning: Using httpx with starlette.testclient is deprecated; install httpx2 instead.` چاپ می‌شود.

فایل‌های آماده را کپی کنید:

```bash
cp $K/churn/api.py src/churn/
```

```bash
cp $K/scripts/check_contract.py scripts/
```

```bash
cp $K/tests/test_api.py tests/
```

```bash
cp -r $K/examples .
```

```bash
cp $K/Makefile .
```

> اگر به `Makefile` خودتان هدف دیگری اضافه کرده‌اید، فقط دو هدف تازه (`contract` و `serve`) و خط `PORT ?= 8000` را از فایل جدید به آن اضافه کنید.

## گام ۲ — قرارداد ورودی (۱۵ دقیقه)

فایل `src/churn/api.py` را در ویرایشگر باز کنید و کلاس `Customer` را پیدا کنید. هر فیلد یک ستون ورودی مدل است و محدودیتش را دارد:

| فیلد | نوع | محدودیت |
| --- | --- | --- |
| `tenure_months` | عدد | بین ۰ تا ۱۲۰ |
| `monthly_charges` | عدد | بزرگ‌تر از ۰ و تا ۵۰۰ |
| `contract` | یکی از چند مقدار | `month-to-month`، `one-year`، `two-year` |
| `internet_service` | یکی از چند مقدار | `dsl`، `fiber`، `none` |
| `payment_method` | یکی از چند مقدار | `card`، `bank_transfer`، `cash` |
| `support_calls` | عدد صحیح | بین ۰ تا ۵۰ |

دو نکته: فیلد اضافه (مثل `discount`) رد می‌شود (`extra="forbid"`)، و مقدارهای مجاز همان‌هایی هستند که `make_dataset.py` تولید می‌کند؛ مدل هرگز دسته‌ای (category) ندیده که اینجا مجاز نباشد.

قرارداد API باید با signature مدل یکی باشد، وگرنه مدل ستون ناشناخته می‌گیرد. این را خودکار بررسی کنید:

```bash
make contract
```

انتظار (حدود ۶ ثانیه):

```
  tenure_months    double
  monthly_charges  double
  contract         string
  internet_service string
  payment_method   string
  support_calls    long
contract OK: Customer matches the signature of models:/churn@champion
```

اسکریپت signature مدل `@champion` را از Registry می‌خواند و نام و نوع هر ستون را با `Customer` مقایسه می‌کند. در صورت اختلاف، پیامی مثل `field 'support_calls' is int, signature says double` چاپ می‌کند و با خطا تمام می‌شود.

در مرورگر `http://localhost:5050/#/models` را باز کنید، روی `churn` و بعد روی نسخه‌ای که `@champion` دارد کلیک کنید و بخش **Schema** را با جدول بالا مقایسه کنید: همان شش ستون با همان نوع‌ها.

## گام ۳ — روشن کردن سرویس (۲۰ دقیقه)

### ۳-۱. ترمینال ۲: سرور

یک ترمینال تازه باز کنید (در Windows یک تب WSL Ubuntu تازه) و این‌ها را بزنید:

```bash
cd ~/work/churn-mlops
```

```bash
set -a; source .env; set +a
```

```bash
make serve
```

انتظار (۷ تا ۱۰ ثانیه صبر کنید؛ شماره‌ی process و `run_id` و زمان در سیستم شما فرق دارند):

```
uv run uvicorn churn.api:app --host 127.0.0.1 --port 8000 --no-access-log
INFO:     Started server process [65464]
INFO:     Waiting for application startup.
{"ts": "2026-10-16 21:29:06,066", "level": "INFO", "event": "model_loaded", "uri": "models:/churn@champion", "name": "churn", "version": "3", "run_id": "8767408e88244b22b8684704c464feea", "seconds": 1.58}
INFO:     Application startup complete.
INFO:     Uvicorn running on http://127.0.0.1:8000 (Press CTRL+C to quit)
```

خط JSON با `"event": "model_loaded"` یعنی مدل از Registry بار شد. این ترمینال را باز نگه دارید؛ لاگ هر درخواست اینجا چاپ می‌شود.

### ۳-۲. ترمینال ۱: درخواست‌ها

به ترمینال ۱ برگردید (همان که در `~/work/churn-mlops` است). اول دو endpoint ساده:

```bash
curl -s localhost:8000/health
```

انتظار: `{"status":"ok"}`

```bash
curl -s localhost:8000/ready
```

انتظار: `{"status":"ready","model_version":"3"}`

```bash
curl -s localhost:8000/model-info
```

انتظار (`run_id` در سیستم شما فرق دارد):

```
{"uri":"models:/churn@champion","name":"churn","version":"3","run_id":"8767408e88244b22b8684704c464feea","threshold":0.5}
```

حالا پیش‌بینی. مشتری اول تازه‌وارد است، قرارداد ماه‌به‌ماه دارد و زیاد با پشتیبانی تماس گرفته:

```bash
curl -s -X POST localhost:8000/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار:

```
{"churn_probability":0.9032,"churn":true,"threshold":0.5,"model_version":"3"}
```

مشتری دوم وفادار است (قرارداد دوساله، بدون تماس):

```bash
curl -s -X POST localhost:8000/predict -H 'Content-Type: application/json' -d @examples/loyal_customer.json
```

انتظار:

```
{"churn_probability":0.0142,"churn":false,"threshold":0.5,"model_version":"3"}
```

<bdi dir="rtl">`churn` برابر `true` است وقتی احتمال از `threshold` بیشتر باشد؛ همان قاعده‌ی `evaluate.py`. اگر عددهای شما کمی فرق دارد، نسخه‌ی `@champion` شما با نمونه‌ی مدرس یکی نیست؛ مشکلی نیست.</bdi>

به ترمینال ۲ نگاه کنید. برای هر درخواست یک خط `request` (با `status` و زمان به میلی‌ثانیه) و برای هر پیش‌بینی یک خط `prediction` آمده است. نمونه:

```
{"ts": "2026-10-16 21:29:07,260", "level": "INFO", "event": "prediction", "version": "3", "proba": 0.9032}
{"ts": "2026-10-16 21:29:07,261", "level": "INFO", "event": "request", "method": "POST", "path": "/predict", "status": 200, "ms": 161.6}
```

اولین پیش‌بینی کندتر است (حدود ۱۶۰ میلی‌ثانیه، گرم شدن) و بعدی‌ها حدود ۳ میلی‌ثانیه.

### ۳-۳. مستندات تعاملی

در مرورگر `http://localhost:8000/docs` را باز کنید. FastAPI این صفحه (Swagger UI) را از روی قرارداد `Customer` خودش ساخته است. روی `POST /predict` کلیک کنید، **Try it out** را بزنید (نمونه‌ی مشتری از قبل پر شده)، یکی دو مقدار را عوض کنید (مثلاً `contract` را `two-year` کنید) و **Execute** را بزنید. جواب و کد `200` را زیر آن می‌بینید. بخش **Schemas** در پایین صفحه فهرست مقدارهای مجاز `contract` را نشان می‌دهد. دوباره به ترمینال ۲ نگاه کنید: همین درخواست هم لاگ شده است.

## گام ۴ — خطا و مشاهده‌پذیری (۱۵ دقیقه)

### ۴-۱. ورودی غلط: ۴۲۲

فایل `examples/bad_customer.json` دو اشتباه دارد: `contract` برابر `weekly` است و `support_calls` برابر `1.5` (کسری). در ترمینال ۱:

```bash
curl -s -w '\nHTTP %{http_code}\n' -X POST localhost:8000/predict -H 'Content-Type: application/json' -d @examples/bad_customer.json
```

انتظار:

```
{"detail":[{"type":"literal_error","loc":["body","contract"],"msg":"Input should be 'month-to-month', 'one-year' or 'two-year'","input":"weekly","ctx":{"expected":"'month-to-month', 'one-year' or 'two-year'"}},{"type":"int_from_float","loc":["body","support_calls"],"msg":"Input should be a valid integer, got a number with a fractional part","input":1.5}]}
HTTP 422
```

جواب هر دو اشتباه را با محل دقیقشان (`loc`) می‌گوید و مدل اصلاً صدا زده نمی‌شود. در ترمینال ۲ خط `request` با `"status": 422` را ببینید. قرارداد از مدل در برابر داده‌ی بی‌معنی محافظت می‌کند.

### ۴-۲. شمارنده‌ها: `/metrics`

```bash
curl -s localhost:8000/metrics | grep -E "^(churn_predictions_total|churn_predict_seconds_count|http_requests_total)"
```

انتظار (عددها بسته به تعداد درخواست‌های شما فرق دارند؛ اگر صفحه‌ی `/docs` را باز کرده‌اید، ردیف‌های `/docs` و `/openapi.json` هم می‌آیند):

```
churn_predictions_total{churn="true"} 1.0
churn_predictions_total{churn="false"} 1.0
churn_predict_seconds_count 2.0
http_requests_total{handler="/ready",method="GET",status="2xx"} 1.0
http_requests_total{handler="/health",method="GET",status="2xx"} 1.0
http_requests_total{handler="/model-info",method="GET",status="2xx"} 1.0
http_requests_total{handler="/predict",method="POST",status="2xx"} 2.0
http_requests_total{handler="/predict",method="POST",status="4xx"} 1.0
```

شمارنده‌های `churn_predictions_total` و `churn_predict_seconds` را خود ما تعریف کرده‌ایم؛ `http_requests_total` را کتابخانه‌ی `prometheus-fastapi-instrumentator` می‌سازد. این صفحه در جلسه‌ی ۱۳ به Prometheus داده می‌شود تا نمودار و هشدار بسازیم.

### ۴-۳. تمرین readiness: وقتی Registry در دسترس نیست

اول ببینید سرور روشن چه می‌کند وقتی MLflow خاموش شود:

```bash
cd ~/mlops-lab/compose && docker compose stop mlflow
```

```bash
cd ~/work/churn-mlops
```

```bash
curl -s localhost:8000/ready
```

انتظار: هنوز `{"status":"ready","model_version":"3"}`. مدل در حافظه‌ی API است و Registry فقط هنگام روشن شدن لازم بود.

حالا سرور را دوباره راه بیندازید: در ترمینال ۲ کلیدهای `Ctrl+C` را بزنید و بعد دوباره:

```bash
make serve
```

این بار در لاگ خط خطا می‌آید (اما سرور بالا می‌آید):

```
{"ts": "...", "level": "ERROR", "event": "model_load_failed", "uri": "models:/churn@champion", "error": "MLflow server not reachable at http://localhost:5050 (ConnectionError).\nStart it: cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow"}
INFO:     Application startup complete.
```

در ترمینال ۱ سه endpoint را امتحان کنید:

```bash
curl -s -w '  HTTP %{http_code}\n' localhost:8000/health
```

انتظار: `{"status":"ok"}  HTTP 200`

```bash
curl -s -w '  HTTP %{http_code}\n' localhost:8000/ready
```

انتظار: `{"detail":"model not loaded"}  HTTP 503`

```bash
curl -s -w '  HTTP %{http_code}\n' -X POST localhost:8000/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار: `{"detail":"model not loaded"}  HTTP 503`

معنی: برنامه **زنده** است (`/health` جواب می‌دهد) ولی **آماده** نیست (`/ready` و `/predict` با ۵۰۳ می‌گویند مدل ندارم). در Kubernetes جلسه‌ی ۱۱ همین تفاوت لازم می‌شود: چون `/health` سالم است Kubernetes برنامه را restart نمی‌کند، ولی چون `/ready` جواب ۵۰۳ می‌دهد ترافیک را از Podی که مدل ندارد دور نگه می‌دارد.

حالا MLflow را روشن کنید:

```bash
cd ~/mlops-lab/compose && docker compose start mlflow
```

```bash
sleep 10 && curl -s http://localhost:5050/health
```

انتظار: `OK`

```bash
cd ~/work/churn-mlops && curl -s -w '  HTTP %{http_code}\n' localhost:8000/ready
```

انتظار: هنوز `503`! سرویس مدل را فقط هنگام روشن شدن بار می‌کند و خودش دوباره تلاش نمی‌کند. در ترمینال ۲ دوباره `Ctrl+C` و `make serve` بزنید، ۱۰ ثانیه صبر کنید و بعد:

```bash
curl -s localhost:8000/ready
```

انتظار: `{"status":"ready","model_version":"3"}`

> همین رفتار برای جابه‌جا شدن `@champion` هم هست. اگر نسخه‌ی تازه‌ای champion شود، API روشن همچنان نسخه‌ی قبلی را سرو می‌کند تا restart شود. دلیل: alias یک بار به شماره‌ی نسخه تبدیل می‌شود و همه‌ی درخواست‌ها با یک مدل ثابت جواب می‌گیرند. اگر می‌خواهید نسخه‌ی مشخصی را سرو کنید (مثلاً برای rollback)، متغیر `MODEL_URI=models:/churn/1` را پیش از `make serve` بدهید.

## گام ۵ — آزمون، commit، Pull Request و tag (۱۵ دقیقه)

در ترمینال ۱ (سرور در ترمینال ۲ روشن بماند):

```bash
uv run ruff check . && uv run ruff format --check .
```

انتظار: `All checks passed!` و `... files already formatted`

```bash
uv run pytest -q tests/test_api.py
```

انتظار: `11 passed` (حدود ۱۷ ثانیه؛ ممکن است دو هشدار `warnings` هم ببینید که از آزمون SQLite مربوط به Registry می‌آید و بی‌خطر است).

این آزمون‌ها سرور لازم ندارند: `TestClient` برنامه را مستقیم صدا می‌زند و مدل را با یک مدل محلی جایگزین می‌کند. آزمون‌ها همین کارها را می‌سنجند: `/health` و `/ready`، پیش‌بینی، چهار حالت ورودی غلط (`422`)، فیلد جاافتاده، نبودن مدل (`/health` سالم و `/ready` و `/predict` با ۵۰۳)، بالا رفتن شمارنده‌ی `/metrics`، هم‌خوانی قرارداد و بار شدن مدل با alias و با شماره‌ی نسخه.

حالا commit:

```bash
git add src scripts tests examples pyproject.toml uv.lock Makefile && git commit -m "feat: inference API with FastAPI"
```

```bash
git status --short
```

انتظار: خالی.

```bash
git push -u origin feature/inference-api
```

در Gitea (`http://localhost:3000`) برای شاخه‌ی `feature/inference-api` یک Pull Request بسازید و در توضیح بنویسید:

```
Inference API for models:/churn@champion (FastAPI + uvicorn).
Endpoints: /health, /ready, /model-info, /predict, /metrics. Input contract checked
against the model signature (make contract). Bad input -> 422, no model -> 503.
JSON logs; 11 tests that need no server.
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.6.0 -m "Session 8: inference API"
```

```bash
git push origin v0.6.0
```

---

## بررسی پایان کار

<bdi dir="rtl">API باید هنوز در ترمینال ۲ روشن و آماده باشد (`/ready` جواب ۲۰۰ بدهد). بعد در ترمینال ۱:</bdi>

```bash
~/mlops-lab/scripts/verify.sh s08
```

انتظار (شماره‌ی commit و عددها در سیستم شما فرق دارند):

```
[PASS] fastapi, uvicorn, prometheus-fastapi-instrumentator and httpx2 pinned in pyproject.toml
[PASS] api.py, check_contract.py, test_api.py, examples and uv.lock committed
[PASS] API tests pass (uv run pytest tests/test_api.py, no server needed)
[PASS] API answers /health at http://localhost:8000
[PASS] /ready is 200 and serves the same version as @champion
       API version 3, @champion version 3
[PASS] /predict returns a probability; bad input gets HTTP 422
       {"churn_probability":0.9032,"churn":true,"threshold":0.5,"model_version":"3"}
[PASS] /metrics counts predictions (churn_predictions_total)
[PASS] tag v0.6.0 exists locally and on Gitea
s08: 8/8 checks passed
```

اجرای آن حدود ۲۰ ثانیه طول می‌کشد (آزمون‌های API را هم اجرا می‌کند). خروجی را همراه با تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `[Errno 48] ... address already in use` (در Linux/WSL: `[Errno 98]`)، حتی بعد از `model_loaded` و `Application startup complete` | پورت ۸۰۰۰ را برنامه‌ی دیگری، یا یک `make serve` قدیمی، گرفته است | آن سرور را با `Ctrl+C` ببندید، یا `make serve PORT=8001` (و در `curl` هم پورت را عوض کنید) |
| `/ready` جواب `503` می‌دهد و `{"detail":"model not loaded"}` | مدل هنگام روشن شدن بار نشد؛ علت در خط `model_load_failed` لاگ سرور است | علت را بخوانید (دو حالت پایین)، رفعش کنید و سرور را restart کنید |
| لاگ: `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false is not set` | `.env` در ترمینال سرور بار نشده بود | در ترمینال ۲ `Ctrl+C`، بعد `set -a; source .env; set +a` و دوباره `make serve` |
| لاگ: `MLflow server not reachable at http://localhost:5050` | سرور MLflow خاموش است | `cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow` و بعد restart سرور API |
| `/ready` بعد از روشن کردن MLflow هنوز `503` است | مدل فقط هنگام روشن شدن سرویس بار می‌شود | `Ctrl+C` و `make serve` |
| `@champion` عوض شد ولی `/model-info` نسخه‌ی قبلی را نشان می‌دهد | alias فقط یک بار هنگام روشن شدن بررسی می‌شود | `Ctrl+C` و `make serve`؛ `verify.sh s08` هم تا آن موقع `FAIL` می‌دهد |
| `curl` در ترمینال ۲ کار نمی‌کند یا ترمینال «گیر کرده» | ترمینال ۲ با سرور مشغول است | `curl` و بقیه‌ی دستورها را در ترمینال ۱ بزنید |
| `curl: (7) Failed to connect to localhost port 8000` | سرور هنوز بالا نیامده (۷ تا ۱۰ ثانیه) یا خاموش شده | ترمینال ۲ را نگاه کنید؛ منتظر `Uvicorn running on ...` بمانید |
| `422` با `"loc":["body","contract"]` و `Field required` | فیلدی جا افتاده | فایل JSON را با `examples/customer.json` مقایسه کنید |
| `422` با `extra_forbidden` | فیلدی فرستاده‌اید که در `Customer` نیست | آن فیلد را بردارید؛ `extra="forbid"` عمدی است |
| `MISMATCH field ...` در `make contract` | `Customer` با signature مدل فرق دارد | فیلد یا نوعش را در `api.py` یا مدل را در Registry بررسی کنید |
| `make contract` یا بار شدن مدل خطا می‌دهد که `@champion` پیدا نشد | Registry خالی است (مثلاً `down -v` زده شده) یا alias ندارد | گام‌های جلسه‌ی ۷ را تکرار کنید (`make register` و `make promote`) |
| `StarletteDeprecationWarning: Using httpx with starlette.testclient is deprecated` | `httpx` نصب شده، نه `httpx2` | `uv add --dev httpx2==2.13.1` |
| `uv run dvc exp run -S train.C=...` در `make runs` run تازه نمی‌سازد | همین آزمایش قبلاً اجرا شده و DVC نتیجه را از run-cache برداشته؛ مرحله‌ی `evaluate` اجرا نشد | `uv run dvc exp run -f -S train.C=...` (با `-f`، یعنی اجبار) |
| `warning: build_system.requires = ["uv-build...` | نسخه‌ی `uv` با پروژه‌ی قدیمی‌تر فرق دارد | بی‌خطر |
| `pytest` حدود ۱۵ تا ۲۰ ثانیه طول می‌کشد | آزمون Registry یک پایگاه موقت می‌سازد | عادی است |
| `verify.sh s08` در بررسی سرور `FAIL` می‌دهد | API روشن نیست یا روی پورت دیگری است | `make serve` در ترمینال ۲؛ برای پورت دیگر: `API_URL=http://localhost:8001 ~/mlops-lab/scripts/verify.sh s08` |
| tag `v0.6.0` روی commit قدیمی است (پیش از merge زده شده) | tag را پیش از `git switch main && git pull` ساخته‌اید | `git tag -d v0.6.0 && git push origin :refs/tags/v0.6.0`، بعد روی `main` به‌روز دوباره tag و push |
| `verify.sh s08` در بررسی tag یا commit `FAIL` می‌دهد | commit یا tag ساخته نشده، یا فایل‌ها بعد از commit تغییر کرده‌اند | `git status`؛ گام ۵ را کامل کنید |

برای جلسه‌ی بعد Registry و پروژه را نگه دارید (`docker compose down -v` نزنید). جلسه‌ی ۹ همین سرویس را در یک **Docker image** می‌گذارد و امنیت آن را بررسی می‌کند.

</div>
