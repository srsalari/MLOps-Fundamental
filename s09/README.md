<div dir="rtl">

# آزمایشگاه جلسه‌ی ۹ — Docker image امن برای API

در جلسه‌ی ۸ سرویس FastAPI را روی لپ‌تاپ خودتان اجرا کردید. در این آزمایشگاه همان سرویس را داخل یک **Docker image** می‌گذارید تا روی هر ماشینی (و در جلسه‌ی ۱۱ روی Kubernetes) دقیقاً یکسان اجرا شود. image را **کوچک** می‌سازید (چند مرحله‌ای)، با کاربر **غیر root** اجرا می‌کنید، با یک `.dockerignore` جلوی رفتن فایل‌های محرمانه (مثل `.env`) را می‌گیرید، کنار MLflow روی یک شبکه‌ی Docker بالا می‌آورید، با **Trivy** (به‌صورت آفلاین) آسیب‌پذیری‌هایش را اسکن می‌کنید، حداقل دو مورد را درست می‌کنید و در پایان `churn-api:0.7.0` را به registry محلی (`localhost:5001`) push می‌کنید.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۸ سالم باشد: `main` شامل tag `v0.6.0` است، مدل `churn` در Registry alias `@champion` دارد و سرویس‌های جلسه‌های قبل (SeaweedFS و MLflow) را پاک نکرده‌اید (`docker compose down -v` نزده باشید).
2. بررسی آمادگی را اجرا کنید:

```bash
~/mlops-lab/s09/preflight.sh
```

اگر خطایی داد، پیام آن راه‌حل را می‌گوید. بعد مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s09
```

در این جلسه همه‌ی کار در یک ترمینال انجام می‌شود، چون container در پس‌زمینه (`-d`) اجرا می‌شود. اگر ترمینال را بستید، خط `K=...` را دوباره بزنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell؛ Docker هم داخل همان Ubuntu نصب است (جلسه‌ی ۲) و باید روشن باشد. دانشجوهای macOS: Docker Desktop (یا Colima) باید در حال اجرا باشد.

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| image | یک «بسته‌ی» فقط‌خواندنی از برنامه و همه‌ی چیزهایی که برای اجرا لازم دارد (پایتون، کتابخانه‌ها، کد) |
| container | یک نمونه‌ی در حال اجرا از یک image؛ از یک image می‌شود چند container ساخت |
| Dockerfile | دستورالعمل ساخت image، خط به خط (هر دستور یک لایه می‌سازد) |
| لایه (layer) | نتیجه‌ی یک دستور Dockerfile؛ اگر چیزی عوض نشود، Docker لایه را از cache برمی‌دارد و دوباره نمی‌سازد |
| multi-stage build | چند `FROM` در یک Dockerfile: مرحله‌ی اول ابزار می‌خواهد و می‌سازد، مرحله‌ی آخر فقط نتیجه را برمی‌دارد؛ ابزار ساخت وارد image نهایی نمی‌شود |
| base image | image‌ای که از آن شروع می‌کنیم؛ اینجا `python:3.12-slim-bookworm` (Debian 12 کم‌حجم) |
| `.dockerignore` | فهرست چیزهایی که هرگز به Docker داده نمی‌شود (مثل `.env`، `.git`، داده‌ها)؛ کوچک‌تر و امن‌تر |
| کاربر غیر root | داخل container برنامه با کاربر معمولی (`app`، شماره‌ی ۱۰۰۰۱) اجرا شود، نه root؛ اگر کسی به برنامه نفوذ کند کمتر می‌تواند خرابی بسازد |
| HEALTHCHECK | دستوری که Docker هر چند ثانیه اجرا می‌کند تا بداند container سالم است (`healthy`) یا نه |
| شبکه‌ی Docker | container‌هایی که روی یک شبکه‌اند، همدیگر را با نام می‌بینند (`http://mlflow:5000`) |
| registry | انبار image‌ها؛ ما یک registry محلی روی `localhost:5001` می‌گذاریم |
| CVE | شناسه‌ی یک آسیب‌پذیری امنیتی شناخته‌شده (مثل `CVE-2023-45853`) |
| Trivy | اسکنری که پکیج‌های داخل image را با پایگاه داده‌ی CVEها مقایسه می‌کند |
| severity | شدت آسیب‌پذیری: `LOW`، `MEDIUM`، `HIGH`، `CRITICAL` |
| fixable | یعنی نسخه‌ی اصلاح‌شده‌ای از پکیج وجود دارد؛ فقط این‌ها را می‌شود با به‌روز کردن درست کرد |

نکته‌ی مهم: مدل **داخل image نیست**. container هنگام روشن شدن مدل `@champion` را از MLflow می‌گیرد (مثل جلسه‌ی ۸). پس image فقط کد و کتابخانه‌ها را دارد و برای عوض شدن مدل لازم نیست image دوباره ساخته شود.

## نتیجه‌ی نهایی

- <bdi dir="rtl">image با نام `churn-api:0.7.0` (چند مرحله‌ای، حدود 1.29GB، کاربر `app`، دارای HEALTHCHECK)</bdi>
- <bdi dir="rtl">container روی `http://localhost:8001` کنار MLflow، با `/ready` سالم</bdi>
- اسکن Trivy که برای آسیب‌پذیری‌های قابل‌رفع (HIGH و CRITICAL) سبز است
- <bdi dir="rtl">image در registry محلی `localhost:5001/churn-api:0.7.0`</bdi>
- کد در Git با tag نسخه‌ی `v0.7.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `Dockerfile` | ریشه‌ی پروژه | ساخت image در دو مرحله (build و runtime) |
| `dockerignore` | `.dockerignore` در ریشه‌ی پروژه | فهرست چیزهایی که وارد image نشوند (نام فایل مقصد با نقطه شروع می‌شود) |
| `Makefile` | ریشه‌ی پروژه (جای Makefile جلسه‌ی ۸) | هدف‌های تازه‌ی `image`، `scan`، `run-image` و `push` |
| `Dockerfile.naive` | فقط برای مقایسه | نسخه‌ی «ساده‌لوحانه»؛ برای ساخت لازم نیست |
| `preflight.sh` | اجرا از همین پوشه | بررسی آمادگی پیش از کلاس |

توضیح خط‌به‌خط فایل‌های این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — وضعیت شروع و ابزارها (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git describe --tags
```

انتظار: `v0.6.0` (اگر تکلیف جلسه‌ی ۸ را merge کرده‌اید چیزی مثل `v0.6.0-2-g1a2b3c4` می‌بینید؛ مشکلی نیست)

```bash
git switch -c feature/container-image
```

سرویس‌های جلسه‌های قبل را روشن کنید (container ما باید MLflow را روی شبکه‌ی `mlops-lab` ببیند):

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow
```

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK`

```bash
cd ~/work/churn-mlops
```

حالا ابزار اسکن را بررسی کنید:

```bash
trivy --version
```

انتظار: خطی که با `Version: 0.74.0` شروع می‌شود. (اگر دستور پیدا نشد، `trivy` نصب نیست: `~/mlops-lab/scripts/install-from-bundle.sh` را از بسته‌ی دوره اجرا کنید.)

<bdi dir="rtl">Trivy برای کار آفلاین به یک **پایگاه داده‌ی آسیب‌پذیری** روی دیسک نیاز دارد (حدود 1.5GB). این پایگاه با بسته‌ی دوره می‌آید و Trivy آن را از پوشه‌ای می‌خواند که متغیر `TRIVY_CACHE_DIR` نشان می‌دهد. `Makefile` این جلسه خودش `TRIVY_CACHE_DIR` را برابر `~/.cache/trivy` می‌گذارد، همان جایی که `install-from-bundle.sh` پایگاه را می‌ریزد. بدون این متغیر، Trivy در macOS در `~/Library/Caches/trivy` دنبال پایگاه می‌گردد و آن را پیدا نمی‌کند. اگر پایگاه را جای دیگری گذاشته‌اید، هنگام `make scan` متغیر را بدهید: `make scan TRIVY_CACHE_DIR=/مسیر/شما`.</bdi>

بررسی کنید پایگاه آنجاست:

```bash
ls ~/.cache/trivy/db
```

انتظار: دو فایل `metadata.json` و `trivy.db`

یک تفاوت مهم با اسکن‌های «آنلاین»: در همه‌ی دستورهای Trivy این جلسه گزینه‌ی `--skip-db-update` هست، یعنی «پایگاه داده را از اینترنت به‌روز نکن، همان که روی دیسک است را استفاده کن». این کار هم سریع است و هم در کلاس بدون اینترنت جواب می‌دهد.

## گام ۲ — Dockerfile و `.dockerignore` (۱۵ دقیقه)

فایل‌های آماده را کپی کنید:

```bash
cp $K/Dockerfile .
```

```bash
cp $K/dockerignore .dockerignore
```

```bash
cp $K/Makefile .
```

> اگر به `Makefile` خودتان هدف دیگری اضافه کرده‌اید، فقط چهار هدف تازه (`image`، `scan`، `run-image`، `push`) و متغیرهای بالای آن‌ها (`IMAGE`، `TAG`، `REGISTRY`، `NETWORK`، `MLFLOW_IN_DOCKER`، `TRIVY_CACHE_DIR`) را اضافه کنید.

فایل `Dockerfile` را در ویرایشگر باز کنید. ساختار آن این است (توضیح خط‌به‌خط در [CODE.md](CODE.md)):

| بخش | کار |
| --- | --- |
| `FROM ... AS build` | مرحله‌ی اول: پایتون + ابزار `uv`؛ کتابخانه‌های پروژه را در `/app/.venv` نصب می‌کند |
| `COPY pyproject.toml uv.lock README.md` و بعد `uv sync` | اول فقط فایل‌های وابستگی را کپی می‌کنیم تا لایه‌ی کتابخانه‌ها cache شود |
| `COPY src` و `uv sync --no-editable` | بعد کد خودمان را نصب می‌کنیم |
| `FROM ... AS runtime` | مرحله‌ی دوم: یک پایتون تازه؛ فقط پوشه‌ی `.venv` از مرحله‌ی اول کپی می‌شود (`uv` و ابزار ساخت نمی‌آیند) |
| `useradd --uid 10001 app` و `USER app` | برنامه با کاربر غیر root اجرا می‌شود |
| `ENV ...` | تنظیم‌هایی که MLflow و پایتون لازم دارند (از جمله `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false` که از جلسه‌ی ۸ می‌شناسید) |
| `HEALTHCHECK` | هر ۱۰ ثانیه آدرس `/health` را صدا می‌زند |
| `CMD` | اجرای uvicorn روی `0.0.0.0:8000` (داخل container باید روی همه‌ی نشانی‌ها گوش دهد) |

یک نکته: فایل `README.md` هم کپی می‌شود، چون `pyproject.toml` پروژه `readme = "README.md"` دارد و بدون آن نصب پروژه خطا می‌دهد.

فایل `.dockerignore` هم باز کنید. هر خط یک چیز است که **هرگز** وارد build نمی‌شود: `.git`، `.venv`، `.env`، داده‌ها (`data/`)، مدل‌ها (`models/`)، `mlruns/` و cacheها. مهم‌ترین خط‌ها `.env` و `.env.*` هستند، چون کلیدهای آزمایشگاه در `.env` است.

حالا image را بسازید:

```bash
make image
```

انتظار (حدود ۵۰ ثانیه در بار اول؛ اعداد و زمان‌ها در سیستم شما فرق دارند): در میان خروجی خط‌هایی مثل این می‌آید:

```
Prepared 89 packages in 8.23s
Installed 89 packages in 479ms
warning: build_system.requires = ["uv-build>=0.11.11,<0.12.0"] does not contain the current uv version 0.12.15
   Built churn @ file:///app
Bytecode compiled 8293 files in 86ms
```

خط `warning: build_system.requires ...` بی‌خطر است. این مرحله بسته‌ها را از اینترنت (PyPI) یا آینه‌ی دوره می‌گیرد، پس به شبکه نیاز دارد. اگر بار دوم `make image` بزنید و چیزی عوض نشده باشد، همه‌ی لایه‌ها از cache می‌آیند و چند ثانیه بیشتر طول نمی‌کشد.

اندازه‌ی image را ببینید:

```bash
docker images churn-api:0.7.0
```

ستون اندازه باید حدود `1.29GB` باشد (در نسخه‌های قدیمی‌تر Docker نام ستون `SIZE` است و در نسخه‌های تازه `DISK USAGE` و `CONTENT SIZE`). بیشترِ آن همان `.venv` است (حدود 840MB، چون MLflow، scikit-learn، pandas، matplotlib و pyarrow سنگین‌اند).

بررسی کنید برنامه با چه کاربری اجرا می‌شود:

```bash
docker run --rm --entrypoint id churn-api:0.7.0
```

انتظار:

```
uid=10001(app) gid=10001(app) groups=10001(app)
```

داخل `/app` چه چیزی هست؟

```bash
docker run --rm --entrypoint ls churn-api:0.7.0 -a /app
```

انتظار:

```
.
..
.venv
```

فقط `.venv`؛ نه کد منبع، نه `.env`، نه `.git`. و ابزار ساخت `uv` در image نهایی نیست:

```bash
docker run --rm --entrypoint sh churn-api:0.7.0 -c 'which uv || echo "uv not found"'
```

انتظار: `uv not found`

> **اختیاری (برای کنجکاوها): مقایسه با Dockerfile ساده.** فایل `$K/Dockerfile.naive` نسخه‌ی «اولین تلاش» است: همه‌چیز را `COPY . .` می‌کند، با root اجرا می‌شود و `uv` را نگه می‌دارد. مدرس آن را ساخته است و اندازه‌اش 2.16GB شد (در برابر 1.29GB)، کاربرش `uid=0(root)` بود و فایل `.env` داخل image بود. نکته‌ی جالب: Trivy در آن image **هیچ secret** پیدا نکرد، حتی وقتی کلیدهای آزمایشگاه در `.env` بودند. یعنی اسکنر جلوی لو رفتن کلید را نمی‌گیرد؛ محافظ واقعی همان `.dockerignore` است. اگر می‌خواهید خودتان ببینید: `docker build -f $K/Dockerfile.naive -t churn-api:naive .` (حدود یک دقیقه و 2GB دیسک). این image را برای بقیه‌ی آزمایشگاه لازم ندارید.

## گام ۳ — اجرای container کنار MLflow (۱۵ دقیقه)

```bash
make run-image
```

این هدف همان `docker run -d --name churn-api --network mlops-lab -p 127.0.0.1:8001:8000 -e MLFLOW_TRACKING_URI=http://mlflow:5000 churn-api:0.7.0` است. معنی گزینه‌ها:

| گزینه | معنی |
| --- | --- |
| `-d` | در پس‌زمینه اجرا شود |
| `--name churn-api` | نام container |
| `--network mlops-lab` | به همان شبکه‌ای وصل شود که MLflow و SeaweedFS در آن‌اند |
| `-p 127.0.0.1:8001:8000` | پورت ۸۰۰۰ داخل container روی پورت ۸۰۰۱ لپ‌تاپ شما (فقط از خود ماشین قابل دسترس) |
| `-e MLFLOW_TRACKING_URI=http://mlflow:5000` | نشانی MLflow از دید container |

چرا `http://mlflow:5000` و نه `http://localhost:5050`؟ داخل container، `localhost` یعنی خود container، نه لپ‌تاپ شما. MLflow روی شبکه‌ی `mlops-lab` با نام `mlflow` و پورت داخلی ۵۰۰۰ شناخته می‌شود؛ پورت ۵۰۵۰ فقط روی لپ‌تاپ شما باز است.

چند ثانیه صبر کنید (چند بار بزنید) تا وضعیت `healthy` شود:

```bash
docker ps --filter name=churn-api
```

انتظار: ستون `STATUS` اول `Up 3 seconds (health: starting)` و بعد از حدود ۷ تا ۱۰ ثانیه `Up 9 seconds (healthy)`. (زمان‌ها فرق دارند.)

لاگ container را ببینید:

```bash
docker logs churn-api
```

انتظار (`ts`، `run_id` و `seconds` در سیستم شما فرق دارند):

```
INFO:     Started server process [1]
INFO:     Waiting for application startup.
{"ts": "2026-10-23 13:46:04,849", "level": "INFO", "event": "model_loaded", "uri": "models:/churn@champion", "name": "churn", "version": "2", "run_id": "631363babaf845a69a53d08e0de7713b", "seconds": 0.78}
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
{"ts": "2026-10-23 13:46:07,515", "level": "INFO", "event": "request", "method": "GET", "path": "/health", "status": 200, "ms": 1.0}
```

خط `model_loaded` یعنی مدل از MLflow بار شد. خط آخر (`GET /health`) از `HEALTHCHECK` است: Docker هر ۱۰ ثانیه `/health` را صدا می‌زند و هر بار یک خط در لاگ می‌ماند. عادی است. شماره‌ی `version` در سیستم شما همان نسخه‌ی `@champion` خودتان است.

حالا از بیرون container صدایش بزنید (پورت ۸۰۰۱):

```bash
curl -s localhost:8001/ready
```

انتظار (شماره‌ی نسخه در سیستم شما فرق دارد): `{"status":"ready","model_version":"2"}`

```bash
curl -s -X POST localhost:8001/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار:

```
{"churn_probability":0.9032,"churn":true,"threshold":0.5,"model_version":"2"}
```

همان عددی که در جلسه‌ی ۸ با `make serve` گرفتید (۰٫۹۰۳۲). یعنی container همان رفتار را دارد.

مرورگر: `http://localhost:8001/docs` را هم باز کنید؛ همان Swagger جلسه‌ی ۸.

**چه می‌شد اگر شبکه را اشتباه می‌دادید؟** اگر container را بدون `--network mlops-lab` یا با آدرس `localhost:5050` اجرا کنید، لاگ خط `model_load_failed` با پیام `MLflow server not reachable at ...` می‌دهد، container همچنان `healthy` می‌ماند (چون `/health` فقط زنده‌بودن را می‌سنجد) ولی `/ready` جواب `503` می‌دهد. همان تفاوت liveness و readiness جلسه‌ی ۸.

حالا container را بردارید (برای گام‌های بعد لازم نیست). **همیشه نام کامل** بنویسید:

```bash
docker rm -f churn-api
```

انتظار: `churn-api`

اگر بعداً خواستید دوباره اجرا کنید، فقط `make run-image` را بزنید.

## گام ۴ — اسکن با Trivy و اصلاح (۲۰ دقیقه)

> این گام برای `uv lock` و ساخت دوباره‌ی image به اینترنت یا آینه‌ی PyPI دوره نیاز دارد.

اول اسکن را اجرا کنید:

```bash
make scan
```

این هدف `trivy image` را با گزینه‌های `--skip-db-update --offline-scan --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` اجرا می‌کند. معنی:

| گزینه | معنی |
| --- | --- |
| `--skip-db-update --offline-scan` | بدون اینترنت، با پایگاه داده‌ی روی دیسک |
| `--severity HIGH,CRITICAL` | فقط موارد مهم |
| `--ignore-unfixed` | مواردی که هنوز نسخه‌ی اصلاح‌شده ندارند را نشمار (کاری از دست ما برنمی‌آید) |
| `--exit-code 1` | اگر مورد باقی ماند، با خطا تمام شود (برای CI و «دروازه»ی کیفیت) |

انتظار: اسکن **رد می‌شود**. خروجی یک جدول بلند است (چون Trivy هر فایل metadata پایتون را یک ردیف نشان می‌دهد؛ بیشترِ ردیف‌ها صفر مورد دارند). به خط‌های `Total:` نگاه کنید. بخش `Python (python-pkg)` حدود ۲۸ مورد را نشان می‌دهد (۵ مورد CRITICAL و ۲۳ مورد HIGH) و آخرِ خروجی:

```
make: *** [scan] Error 1
```

<bdi dir="rtl">`Error 1` یعنی «آسیب‌پذیری قابل‌رفع پیدا شد»؛ مشکل ابزار نیست، همان چیزی است که می‌خواستیم ببینیم.</bdi>

یک نکته درباره‌ی خروجی: بخش Python بیشترِ موارد را از دو کتابخانه می‌آورد: **`certifi`** و **`pillow`**. (`pillow` را MLflow از طریق matplotlib وارد می‌کند.) اگر image ساده را اسکن می‌کردیم، مورد سومی هم بود: خود `uv` در image. در image ما `uv` اصلاً نیست، چون **multi-stage** آن را در مرحله‌ی build جا گذاشته. این اولین «اصلاح» ما بود، پیش از اسکن.

برای دیدن جزئیات، فقط موارد CRITICAL را با جدول کامل ببینید (ستون‌های نسخه‌ی نصب‌شده، نسخه‌ی اصلاح‌شده و عنوان):

```bash
trivy image --skip-db-update --offline-scan --skip-version-check -q --scanners vuln --severity CRITICAL --table-mode detailed churn-api:0.7.0
```

انتظار: دو بخش. بخش `churn-api:0.7.0 (debian 12.15)` با `Total: 2 (CRITICAL: 2)` و بخش `Python (python-pkg)` که `certifi` و `pillow` را با ستون «Fixed Version» نشان می‌دهد. اگر در ستون نسخه‌ی اصلاح‌شده عددی هست، می‌شود آن را درست کرد.

### ۴-۱. اصلاح: به‌روز کردن دو کتابخانه

```bash
uv lock --upgrade-package certifi --upgrade-package pillow
```

انتظار (نسخه‌ی شما ممکن است تازه‌تر باشد، چون `certifi` تقریباً هر هفته نسخه می‌دهد):

```
Resolved 173 packages in 793ms
Updated certifi v2026.7.22 -> v2026.10.23
Updated pillow v12.3.0 -> v13.0.0
```

این دستور فقط این دو بسته را در `uv.lock` به نسخه‌ی تازه می‌برد و بقیه را دست نمی‌زند. تغییر را ببینید:

```bash
git diff --stat
```

انتظار: `uv.lock` عوض شده (حدود ۱۴۵ خط). `Makefile` هم در فهرست است، چون آن را در گام ۲ کپی کردید و هنوز commit نشده؛ طبیعی است.

پیش از ساخت دوباره، مطمئن شوید چیزی خراب نشد:

```bash
uv run pytest -q
```

انتظار: `21 passed` (بین ۲۵ تا ۷۰ ثانیه، بسته به لپ‌تاپ؛ چند هشدار هم طبیعی است)

<bdi dir="rtl">image را دوباره بسازید (لایه‌ی کتابخانه‌ها چون `uv.lock` عوض شد دوباره ساخته می‌شود، حدود ۴۰ ثانیه):</bdi>

```bash
make image
```

و دوباره اسکن کنید:

```bash
make scan
```

انتظار: این بار **تمام می‌شود بدون `Error 1`**. بخش Python صفر مورد دارد.

دوباره جزئیات CRITICAL را ببینید:

```bash
trivy image --skip-db-update --offline-scan --skip-version-check -q --scanners vuln --severity CRITICAL --table-mode detailed churn-api:0.7.0
```

انتظار (فقط Debian مانده؛ ستون‌های وسطِ جدول را کوتاه کرده‌ایم):

```
churn-api:0.7.0 (debian 12.15)
==============================
Total: 2 (CRITICAL: 2)
│ libsqlite3-0 │ CVE-2025-7458  │ CRITICAL │ affected     │ 3.40.1-2+deb12u2  │ │ sqlite: SQLite integer overflow │
│ zlib1g       │ CVE-2023-45853 │          │ will_not_fix │ 1:1.2.13.dfsg-1   │ │ zlib: integer overflow and resultant heap-based buffer overflow in zipOpenNewFileInZip4_6 │
```

### ۴-۲. چرا ۶۳ مورد Debian ماند؟

اگر `--ignore-unfixed` را برندارید هنوز ۶۳ مورد Debian (۶۱ مورد HIGH و ۲ مورد CRITICAL) هست. ستون وضعیت (`Status`) علت را می‌گوید:

| وضعیت | معنی |
| --- | --- |
| `affected` | آسیب‌پذیری شناخته‌شده است و Debian هنوز اصلاحیه‌ای نداده |
| `will_not_fix` | Debian تصمیم گرفته برای این نسخه اصلاحیه ندهد (معمولاً ریسک پایین یا اصلاح خیلی پرهزینه) |

یعنی با تغییر ما قابل‌رفع نیست. گزینه‌های واقعی: base image تازه‌تر (وقتی Debian اصلاحیه داد)، base دیگر (مثلاً `distroless`)، یا **قبول ریسک با مستندسازی** (در تکلیف انجام می‌دهید). به همین دلیل `--ignore-unfixed` را در دروازه گذاشته‌ایم: دروازه‌ای که همیشه قرمز باشد را همه نادیده می‌گیرند.

## گام ۵ — registry، push و پایان (۱۵ دقیقه)

یک registry محلی روشن کنید. نام و گزینه‌ها عمداً همان اسکریپت `scripts/kind-up.sh` است تا در جلسه‌ی ۱۱ (Kubernetes با kind) دوباره از همین registry استفاده کنیم:

```bash
docker run -d --restart=always -p 127.0.0.1:5001:5000 --network bridge --name kind-registry registry:3.1.0
```

(اگر خطا داد که نام `kind-registry` از قبل هست، یعنی پیش‌تر ساخته‌اید؛ `docker start kind-registry` را بزنید.)

```bash
curl -s localhost:5001/v2/_catalog
```

انتظار: `{"repositories":[]}`

حالا push:

```bash
make push
```

انتظار (شناسه‌ی لایه‌ها و digest در سیستم شما فرق دارند):

```
c3b6dd5ab597: Pushed
41b2195c3553: Pushed
b3f6342d167d: Pushed
0.7.0: digest: sha256:d70bf27e603914ff237e037c6a9f7156c6966458263ac140ace4da465cbb32bb size: 856
```

این هدف دو کار می‌کند: `docker tag` (نام تازه‌ی `localhost:5001/churn-api:0.7.0` به همان image) و `docker push`. چون registry روی `localhost` است، Docker بدون تنظیم اضافه (`insecure-registries`) آن را می‌پذیرد. push در Docker Desktop حدود ۲ ثانیه طول می‌کشد.

```bash
curl -s localhost:5001/v2/_catalog
```

انتظار: `{"repositories":["churn-api"]}`

```bash
curl -s localhost:5001/v2/churn-api/tags/list
```

انتظار: `{"name":"churn-api","tags":["0.7.0"]}`

حالا تغییرها را commit کنید:

```bash
git status --short
```

انتظار: فقط `.dockerignore`، `Dockerfile`، `Makefile` و `uv.lock` (فایل‌های تازه با `??` و تغییرکرده‌ها با `M`)

```bash
git add .dockerignore Dockerfile Makefile uv.lock && git commit -m "feat: container image for the API (multi-stage, non-root)"
```

```bash
git status --short
```

انتظار: خالی.

```bash
git push -u origin feature/container-image
```

در Gitea (`http://localhost:3000`) برای شاخه‌ی `feature/container-image` یک Pull Request بسازید و در توضیح بنویسید:

```
Container image for the inference API.
Multi-stage build (uv only in the build stage), slim base, non-root user (uid 10001),
.dockerignore keeps .env/.git/data out, HEALTHCHECK on /health.
Trivy (offline DB): fixed certifi and pillow with uv lock; remaining Debian findings have no fix.
Makefile: image, scan, run-image, push.
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.7.0 -m "Session 9: container image"
```

```bash
git push origin v0.7.0
```

---

## بررسی پایان کار

بررسی‌ها container را هم می‌خواهند. container گام ۳ را پاک کردید، پس آن را با image نهایی دوباره روشن کنید (MLflow و registry محلی هم باید روشن باشند):

```bash
make run-image
```

حدود ۱۰ ثانیه صبر کنید تا `docker ps --filter name=churn-api` حالت `(healthy)` را نشان دهد. بعد در همان ترمینال:

```bash
~/mlops-lab/scripts/verify.sh s09
```

انتظار: همه‌ی خط‌ها `[PASS]` باشند. اگر خطی `[FAIL]` شد، متن آن می‌گوید چه چیزی کم است؛ جدول عیب‌یابی را ببینید. اجرا کمی طول می‌کشد (اسکن Trivy را هم اجرا می‌کند). خروجی را همراه با تکلیف برای مدرس بفرستید.

## معیار پایان کار

- [ ] شاخه‌ی `feature/container-image` ساخته شد و با Pull Request وارد `main` شد
- [ ] `Dockerfile` چند مرحله‌ای و `.dockerignore` در ریشه‌ی پروژه commit شدند
- [ ] `docker run --rm --entrypoint id churn-api:0.7.0` کاربر `app` با شماره‌ی ۱۰۰۰۱ را نشان می‌دهد (نه root)
- [ ] container با `make run-image` روی شبکه‌ی `mlops-lab` `healthy` شد و `curl localhost:8001/ready` جواب `ready` داد
- [ ] `/predict` از داخل container همان پیش‌بینی جلسه‌ی ۸ را برای `examples/customer.json` داد
- [ ] `make scan` سبز است (دو کتابخانه‌ی `certifi` و `pillow` به‌روز شدند و `uv.lock` commit شد)
- [ ] می‌توانید توضیح دهید چرا ۶۳ مورد Debian ماند و `--ignore-unfixed` چه می‌کند
- [ ] `churn-api:0.7.0` در `localhost:5001` است (`tags/list`)
- [ ] tag `v0.7.0` روی `main` است و push شده
- [ ] `~/mlops-lab/scripts/verify.sh s09` همه‌ی بررسی‌ها را `PASS` داد

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `make scan` یا `trivy`: `--skip-db-update cannot be specified on the first run` یا «DB not found» | پایگاه داده‌ی Trivy روی دیسک نیست یا در پوشه‌ی دیگری است | `ls ~/.cache/trivy/db` را ببینید (باید `trivy.db` باشد). پایگاه را با `~/mlops-lab/scripts/install-from-bundle.sh` از بسته‌ی دوره بگذارید، یا اگر پایگاه جای دیگری است `make scan TRIVY_CACHE_DIR=/مسیر/شما`. با اینترنت: `trivy image --download-db-only --db-repository ghcr.io/aquasecurity/trivy-db` |
| `Error response from daemon: ... port is already allocated` یا `address already in use` برای ۸۰۰۱ | برنامه‌ی دیگر یا container قدیمی `churn-api` پورت ۸۰۰۱ را گرفته | `docker ps -a --filter name=churn-api`؛ اگر خودِ `churn-api` است: `docker rm -f churn-api`. اگر برنامه‌ی دیگری است آن را ببندید |
| `docker: Error response from daemon: Conflict. The container name "/churn-api" is already in use` | container قبلی هنوز هست (حتی خاموش) | `docker rm -f churn-api` و دوباره `make run-image` |
| container `unhealthy` است یا `/ready` جواب `503` می‌دهد؛ در `docker logs churn-api` خط `model_load_failed` هست | MLflow خاموش است، یا container روی شبکه‌ی `mlops-lab` نیست، یا آدرس `localhost:5050` داده شده | `curl -s http://localhost:5050/health` باید `OK` باشد؛ بعد `docker rm -f churn-api` و `make run-image` (شبکه و آدرس درست در Makefile است). اگر شبکه‌ی `mlops-lab` وجود ندارد: `cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow` |
| `/ready` بعد از روشن کردن MLflow هنوز `503` | مدل فقط هنگام روشن شدن container بار می‌شود | `docker rm -f churn-api` و دوباره `make run-image` |
| `make scan` با `make: *** [scan] Error 1` تمام می‌شود | **این خطا نیست، نتیجه است**: آسیب‌پذیری قابل‌رفع پیدا شد | جدول را بخوانید؛ ستون «Fixed Version» را ببینید و بسته را با `uv lock --upgrade-package ...` به‌روز کنید (گام ۴) |
| `docker push`: `connection refused` به `localhost:5001` | registry روشن نیست | `docker ps --filter name=kind-registry`؛ اگر نیست `docker start kind-registry` یا دستور `docker run` گام ۵ |
| `docker run ... --name kind-registry`: `port is already allocated` برای ۵۰۰۱ | برنامه‌ی دیگری، یا یک registry قدیمی، پورت ۵۰۰۱ را گرفته | `docker ps --filter publish=5001` را ببینید؛ اگر از قبل `kind-registry` دارید همان را `docker start` کنید، وگرنه برنامه‌ی دیگر را ببندید |
| `no space left on device` یا build کند و ناگهان قطع می‌شود | دیسک Docker پر شده؛ این جلسه حدود 5GB فضا لازم دارد | `docker system df` را ببینید. فقط image‌ها و cache **خودتان** را پاک کنید: `docker rmi churn-api:naive` (اگر ساخته‌اید) و `docker builder prune`. از `docker system prune` استفاده نکنید، چون ممکن است چیزهای سایر پروژه‌ها را هم پاک کند |
| `docker build`: نمی‌تواند بسته دانلود کند (`failed to resolve`, `connection error`, `Failed to fetch`) | اینترنت یا آینه‌ی PyPI در دسترس نیست | شبکه را بررسی کنید؛ در کلاس از مدرس بپرسید آینه‌ی دوره کدام است. image پایه‌ی `ghcr.io/astral-sh/uv:0.12.15` هم باید دانلود یا از بسته‌ی دوره بار شده باشد |
| `uv lock --upgrade-package ...` خطا می‌دهد یا چیزی را عوض نمی‌کند | به PyPI دسترسی ندارید، یا نسخه‌ی تازه‌ای نیست | شبکه را بررسی کنید؛ اگر نسخه‌ی تازه‌ای نبود `make scan` را ببینید که آیا اصلاً مشکلی باقی است |
| `Cannot connect to the Docker daemon` | Docker روشن نیست | macOS: Docker Desktop (یا Colima با `colima start`) را روشن کنید. Ubuntu و WSL: `sudo systemctl start docker`؛ دستورها را داخل WSL Ubuntu بزنید، نه PowerShell |
| `docker build`: `COPY failed ... README.md` یا `src: not found` | در ریشه‌ی پروژه نیستید، یا `.dockerignore` فایلی را که لازم بود حذف کرده | `pwd` باید `~/work/churn-mlops` باشد؛ `.dockerignore` را با نسخه‌ی `$K/dockerignore` مقایسه کنید |
| `warning: build_system.requires = ["uv-build...` | نسخه‌ی `uv` با ابزار ساخت پروژه فرق دارد | بی‌خطر |
| `verify.sh s09` در یکی از بررسی‌ها `FAIL` می‌دهد | image، registry، commit یا tag کم است | متن همان خط را بخوانید؛ گام مربوط (۲ تا ۵) را کامل کنید |
| tag `v0.7.0` روی commit قدیمی است (پیش از merge زده شده) | tag را پیش از `git switch main && git pull` ساخته‌اید | `git tag -d v0.7.0 && git push origin :refs/tags/v0.7.0`، بعد روی `main` به‌روز دوباره tag و push |

برای جلسه‌ی بعد registry محلی (`kind-registry`) و image را نگه دارید و `docker compose down -v` نزنید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

</div>
