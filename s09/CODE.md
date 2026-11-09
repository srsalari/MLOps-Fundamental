<div dir="rtl">

# توضیح کد جلسه‌ی ۹

در جلسه‌ی ۸ سرویس API روی لپ‌تاپ اجرا می‌شد. در این جلسه آن را داخل یک **Docker image** می‌گذاریم: بسته‌ای که پایتون، کتابخانه‌ها و کد را با هم دارد و همه‌جا یکسان اجرا می‌شود. کد پایتون تغییر نمی‌کند؛ این جلسه فقط فایل‌های «بسته‌بندی» دارد.

فایل‌های این جلسه:

- فایل `Dockerfile`: دستور ساخت image در دو مرحله. مهم‌ترین فایل این جلسه است.
- فایل `dockerignore` (در پروژه با نام `.dockerignore`): چیزهایی که هرگز وارد image نمی‌شوند.
- فایل `Makefile`: چهار هدف تازه (`image`، `scan`، `run-image`، `push`) و چند متغیر.
- فایل `Dockerfile.naive`: نسخه‌ی ساده‌لوحانه فقط برای مقایسه.
- فایل `preflight.sh`: بررسی آمادگی پیش از کلاس (کد آموزشی نیست و این‌جا توضیح داده نمی‌شود).

ارتباط با جلسه‌ها: image همان `churn.api:app` جلسه‌ی ۸ را اجرا می‌کند. مدل در image نیست و هنگام روشن شدن از MLflow (جلسه‌ی ۷) گرفته می‌شود. در جلسه‌ی ۱۱ همین image را روی Kubernetes می‌بریم.

کامنت‌های داخل فایل‌ها عمداً انگلیسی هستند، چون ویرایشگرهای کد متن را چپ‌به‌راست نشان می‌دهند. شرح فارسی همه‌چیز در همین فایل است.

---

## مفاهیم پایه: لایه و cache

هر دستور `RUN` و `COPY` در Dockerfile یک **لایه** می‌سازد. Docker هنگام ساخت از بالا به پایین می‌رود؛ اگر یک لایه و همه‌ی ورودی‌هایش عوض نشده باشد، نتیجه‌ی قبلی را از cache برمی‌دارد. اما اگر یک لایه عوض شود، **همه‌ی لایه‌های بعد از آن** دوباره ساخته می‌شوند. به همین دلیل چیزهایی که کم عوض می‌شوند (کتابخانه‌ها) را بالا و چیزهایی که زیاد عوض می‌شوند (کد خودمان) را پایین می‌گذاریم.

```text
مرحله‌ی build (بعد از ساخت دور ریخته می‌شود)      مرحله‌ی runtime (image نهایی)
  python + uv                                        python (تازه)
  -> نصب کتابخانه‌ها در /app/.venv  --- COPY ---->   /app/.venv
  -> نصب کد ما در همان .venv                         کاربر app، HEALTHCHECK، CMD
```

---

## فایل `Dockerfile`

**کار فایل:** دو مرحله دارد. مرحله‌ی اول (`build`) با ابزار `uv` پوشه‌ی `.venv` را می‌سازد. مرحله‌ی دوم (`runtime`) فقط آن پوشه را برمی‌دارد. نتیجه: ابزار ساخت (`uv`) در image نهایی نیست، پس هم کوچک‌تر است و هم آسیب‌پذیری‌های `uv` وارد آن نمی‌شود.

**اجرا:**

```bash
make image
```

دستور `make image` همان `docker build -t churn-api:0.7.0 .` است.

### خط اول

Dockerfile با یک کامنت توضیحی شروع می‌شود. عمداً خط ویژه‌ی `syntax` را نگذاشته‌ایم: آن خط باعث می‌شود Docker در هر build از Docker Hub یک frontend بگیرد و بدون اینترنت build شکست می‌خورد. این Dockerfile چیزی از قابلیت‌های آن نیاز ندارد.

### مرحله‌ی ۱: `build`

```dockerfile
FROM python:3.12-slim-bookworm AS build
```

شروع مرحله‌ی اول. image پایه `python:3.12-slim-bookworm` است: پایتون ۳٫۱۲ روی Debian 12 (نام رمز `bookworm`). نسخه‌ی `slim` ابزارهای اضافه (کامپایلر و ...) را ندارد و کوچک‌تر است. `AS build` به این مرحله اسم می‌دهد تا مرحله‌ی بعد بتواند از آن چیزی کپی کند.

```dockerfile
COPY --from=ghcr.io/astral-sh/uv:0.12.15 /uv /usr/local/bin/uv
```

ابزار `uv` را از image رسمی `uv` (نسخه‌ی ثابت `0.12.15`) فقط یک فایل کپی می‌کنیم: `/uv` را در `/usr/local/bin/uv` می‌گذاریم. با `COPY --from=` می‌شود از image دیگری فایل برداشت. نسخه‌ی ثابت می‌گذاریم تا ساخت‌ها قابل‌تکرار باشند.

```dockerfile
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PYTHON_DOWNLOADS=never
```

سه تنظیم برای `uv`:

- `UV_COMPILE_BYTECODE=1`: فایل‌های پایتون را از قبل به bytecode (`.pyc`) تبدیل می‌کند. image کمی بزرگ‌تر می‌شود ولی راه‌اندازی سریع‌تر است.
- `UV_LINK_MODE=copy`: فایل‌ها را کپی می‌کند، نه hard link. لازم است چون در مرحله‌ی بعد پوشه را به جای دیگر کپی می‌کنیم و link ها خراب می‌شوند.
- `UV_PYTHON_DOWNLOADS=never`: `uv` پایتون جداگانه دانلود نکند و از همین پایتون image استفاده کند.

```dockerfile
WORKDIR /app
```

پوشه‌ی کاری داخل image. اگر نباشد ساخته می‌شود و دستورهای بعدی در آن اجرا می‌شوند.

```dockerfile
# Dependencies first: this layer is reused while pyproject.toml/uv.lock do not change.
COPY pyproject.toml uv.lock README.md ./
```

اول فقط فایل‌های وابستگی را کپی می‌کنیم. تا زمانی که این سه فایل عوض نشده، لایه‌ی بعدی (نصب کتابخانه‌ها، که زمان‌برترین کار است) از cache می‌آید. فایل `README.md` هم لازم است، چون `pyproject.toml` پروژه `readme = "README.md"` دارد و بدون آن نصب پروژه خطا می‌دهد.

```dockerfile
RUN uv sync --frozen --no-dev --no-install-project
```

نصب کتابخانه‌ها در `/app/.venv`. گزینه‌ها:

- `--frozen`: دقیقاً همان نسخه‌های `uv.lock` را نصب کن، قفل را عوض نکن و اگر با `pyproject.toml` نمی‌خواند خطا بده.
- `--no-dev`: کتابخانه‌های توسعه (`pytest`، `ruff`، `dvc`، ...) نصب نشوند. در image تولیدی لازم نیستند و سطح حمله را بزرگ می‌کنند.
- `--no-install-project`: خود پروژه (`churn`) را هنوز نصب نکن، فقط وابستگی‌ها. چون کد هنوز کپی نشده.

```dockerfile
# Then our own code.
COPY src ./src
```

حالا کد خودمان را کپی می‌کنیم. این لایه با هر تغییر کد عوض می‌شود، ولی لایه‌ی کتابخانه‌ها بالاتر است و دست‌نخورده می‌ماند.

```dockerfile
RUN uv sync --frozen --no-dev --no-editable
```

این بار خود پروژه نصب می‌شود. `--no-editable` یعنی کد واقعاً داخل `.venv` کپی شود (نه یک اشاره به پوشه‌ی `src`). به همین دلیل در image نهایی پوشه‌ی `src` لازم نیست.

### مرحله‌ی ۲: `runtime`

```dockerfile
FROM python:3.12-slim-bookworm AS runtime
```

شروع مرحله‌ی دوم، دوباره از همان image پایه ولی **تازه**. هر چیزی که در مرحله‌ی اول بود (`uv`، cache، فایل‌های موقت) اینجا نیست، مگر چیزی که خودمان کپی کنیم. image نهایی همین مرحله است.

```dockerfile
RUN useradd --create-home --uid 10001 app
```

یک کاربر معمولی به نام `app` با شماره‌ی ۱۰۰۰۱ می‌سازد. شماره‌ی بزرگ و ثابت عمدی است: در Kubernetes (جلسه‌ی ۱۱) می‌شود «فقط با کاربر غیر root اجرا کن» را کنترل کرد و شماره‌ی عددی لازم است. `--create-home` پوشه‌ی خانه می‌سازد، چون بعضی کتابخانه‌ها (مثل MLflow) در آن cache می‌نویسند.

```dockerfile
WORKDIR /app
```

پوشه‌ی کاری مرحله‌ی دوم.

```dockerfile
COPY --from=build --chown=app:app /app/.venv /app/.venv
```

مهم‌ترین خط: فقط پوشه‌ی `.venv` را از مرحله‌ی `build` برمی‌دارد. `--chown=app:app` مالک فایل‌ها را کاربر `app` می‌کند (وگرنه مالک root می‌شدند). نتیجه: داخل `/app` فقط `.venv` هست.

```dockerfile
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false \
    MLFLOW_ENABLE_ARTIFACTS_PROGRESS_BAR=false \
    MLFLOW_DISABLE_AGENT_HINT=1
```

متغیرهای محیطی image. علامت `\` در انتهای خط یعنی دستور در خط بعد ادامه دارد.

- `PATH=...`: پوشه‌ی `bin` داخل `.venv` اول جست‌وجو شود. به این ترتیب `uvicorn` و `python` بدون نوشتن مسیر کامل پیدا می‌شوند (و بدون `uv run`).
- `PYTHONUNBUFFERED=1`: خروجی پایتون فوراً چاپ شود، نه با تأخیر در بافر. برای دیدن لاگ با `docker logs` لازم است.
- `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false`: همان تنظیم جلسه‌ی ۷ و ۸ که `.env` می‌گذاشت. در image باید داخل خود image باشد، چون `.env` به image نمی‌رود. کد `registry.py` وجود آن را چک می‌کند.
- `MLFLOW_ENABLE_ARTIFACTS_PROGRESS_BAR=false`: نوار پیشرفت دانلود در لاگ نیاید.
- `MLFLOW_DISABLE_AGENT_HINT=1`: MLflow پیام راهنمای اضافه در لاگ نگذارد.

```dockerfile
USER app
```

از این خط به بعد (و هنگام اجرای container) کاربر `app` است، نه root. اگر کسی از راه یک باگ به برنامه نفوذ کند، دسترسی‌اش محدود به همین کاربر است.

```dockerfile
EXPOSE 8000
```

مستندسازی: برنامه روی پورت ۸۰۰۰ گوش می‌دهد. خودش پورت را باز نمی‌کند؛ باز کردن با `-p` در `docker run` است.

```dockerfile
HEALTHCHECK --interval=10s --timeout=3s --start-period=20s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
```

Docker هر ۱۰ ثانیه این دستور را اجرا می‌کند. اگر بدون خطا تمام شود container سالم (`healthy`) است. گزینه‌ها:

- `--interval=10s`: هر ۱۰ ثانیه یک بار.
- `--timeout=3s`: اگر دستور بیش از ۳ ثانیه طول کشید، شکست حساب شود.
- `--start-period=20s`: در ۲۰ ثانیه‌ی اول، شکست‌ها شمرده نمی‌شوند (برنامه وقت دارد مدل را بار کند).
- `--retries=3`: بعد از ۳ شکست پشت‌سرهم، وضعیت `unhealthy` می‌شود.

دستور خودش یک خط پایتون است که آدرس `/health` را صدا می‌زند و اگر جواب خطا باشد استثنا می‌دهد. چرا `curl` نه؟ چون image `slim` اصلاً `curl` ندارد و نصب آن یک بسته‌ی اضافه (و آسیب‌پذیری احتمالی اضافه) است. هر بار اجرا یک خط `GET /health` در لاگ API می‌گذارد.

یک نکته: `/health` فقط زنده بودن برنامه را می‌سنجد، نه بار شدن مدل (liveness در برابر readiness جلسه‌ی ۸). پس container بدون MLflow هم `healthy` است ولی `/ready` جواب `503` می‌دهد.

```dockerfile
CMD ["uvicorn", "churn.api:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]
```

دستوری که هنگام روشن شدن container اجرا می‌شود. شکل آرایه (`["..."]`) یعنی بدون shell و مستقیم؛ در نتیجه سیگنال خاموش شدن Docker به خود uvicorn می‌رسد. تفاوت با `make serve` جلسه‌ی ۸: `--host 0.0.0.0` به جای `127.0.0.1`. داخل container اگر روی `127.0.0.1` گوش بدهیم هیچ‌چیز از بیرون container به ما نمی‌رسد؛ `0.0.0.0` یعنی روی همه‌ی نشانی‌های داخل container. محدود کردن دسترسی از بیرون با `-p 127.0.0.1:8001:8000` در `docker run` انجام می‌شود.

---

## فایل `dockerignore` (در پروژه: `.dockerignore`)

**کار فایل:** پیش از ساخت، Docker پوشه‌ی پروژه را (به‌نام «build context») می‌خواند. هر چیزی که اینجا نوشته شود از context حذف می‌شود، پس نه کند می‌کند و نه به image می‌رسد. مهم‌ترین کار: جلوگیری از رفتن `.env` (کلیدها) به image.

نام فایل در پوشه‌ی دوره بدون نقطه است تا قابل‌دیدن باشد؛ هنگام کپی با نام `.dockerignore` ذخیره کنید:

```bash
cp $K/dockerignore .dockerignore
```

```text
# Keep the build context small and never send secrets to the image.
```

کامنت: خط‌هایی که با `#` شروع می‌شوند.

```text
.git
```

تاریخچه‌ی Git؛ هم بزرگ است هم ممکن است چیزهای حساس در commit های قدیمی باشد.

```text
.venv
```

محیط مجازی لپ‌تاپ شما. image خودش `.venv` تازه می‌سازد؛ این پوشه برای لپ‌تاپ شماست (ممکن است برای سیستم‌عامل دیگری باشد) و بسیار بزرگ است.

```text
.env
.env.*
!.env.example
```

فایل `.env` (کلیدهای آزمایشگاه) و هر فایل `.env.چیزی` حذف می‌شود. علامت `!` یعنی استثنا: فایل `.env.example` که فقط نمونه است و راز ندارد مجاز است. **این مهم‌ترین خط‌های فایل هستند.** در آزمایش مدرس، Trivy حتی در image‌ای که `.env` داشت هیچ secret پیدا نکرد؛ یعنی اسکنر جای این خط‌ها را نمی‌گیرد.

```text
.dvc/cache
.dvc/tmp
.dvc/config.local
```

cache و فایل‌های موقت DVC و تنظیم محلی (`config.local` ممکن است کلید داشته باشد).

```text
data/
models/
mlruns/
mlflow.db
```

داده‌ها، مدل‌های ذخیره‌شده، خروجی‌های MLflow محلی و پایگاه داده‌ی SQLite. داده از DVC و مدل از MLflow Registry می‌آید و نباید داخل image بسته شود.

```text
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
```

cacheهای پایتون و ابزارها؛ بی‌فایده‌اند.

```text
Dockerfile*
```

خود Dockerfile ها (`Dockerfile` و `Dockerfile.naive`) هم لازم نیستند داخل image بروند. (خود Docker فایل Dockerfile را جدا می‌خواند و به این فهرست وابسته نیست.)

---

## فایل `Makefile`

**کار فایل:** همان Makefile جلسه‌ی ۸ است (هدف‌های `data` تا `serve`) به‌علاوه‌ی چهار هدف تازه. فقط بخش جدید توضیح داده می‌شود.

```makefile
.PHONY: data train lint test runs register promote models predict contract serve image scan push run-image
```

فهرست هدف‌هایی که نام فایل نیستند؛ چهار نام تازه به آن اضافه شده است.

```makefile
IMAGE ?= churn-api
TAG ?= 0.7.0
REGISTRY ?= localhost:5001
NETWORK ?= mlops-lab
MLFLOW_IN_DOCKER ?= http://mlflow:5000
```

پنج متغیر. علامت `?=` یعنی فقط اگر از بیرون مقدار داده نشده باشد (مثلاً `make image TAG=0.7.1`).

| متغیر | معنی |
|---|---|
| `IMAGE` | نام image |
| `TAG` | نسخه‌ی image؛ هم‌نام با tag Git (`v0.7.0`) |
| `REGISTRY` | نشانی registry محلی |
| `NETWORK` | شبکه‌ی Docker که MLflow در آن است (از `compose` دوره) |
| `MLFLOW_IN_DOCKER` | نشانی MLflow **از داخل container**: نام سرویس و پورت داخلی، نه `localhost:5050` |

```makefile
export TRIVY_CACHE_DIR ?= $(HOME)/.cache/trivy
```

محل پایگاه داده‌ی Trivy. کلمه‌ی `export` متغیر را به برنامه‌هایی که make اجرا می‌کند (اینجا `trivy`) هم می‌دهد. مقدار پیش‌فرض `~/.cache/trivy` است، همان جایی که `install-from-bundle.sh` پایگاه را می‌گذارد. بدون این خط، Trivy در macOS در `~/Library/Caches/trivy` می‌گردد.

```makefile
image:
	docker build -t $(IMAGE):$(TAG) .
```

هدف `image`: image را از `Dockerfile` پوشه‌ی جاری می‌سازد. `-t` نام و tag می‌دهد و نقطه‌ی آخر یعنی build context همین پوشه است.

```makefile
scan:
	trivy image --skip-db-update --offline-scan --skip-version-check --scanners vuln \
	  --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 $(IMAGE):$(TAG)
```

هدف `scan`: image را اسکن می‌کند. گزینه‌ها:

- `--skip-db-update --offline-scan`: بدون اینترنت و با پایگاه داده‌ی روی دیسک.
- `--skip-version-check`: بررسی «نسخه‌ی تازه‌ی Trivy» را که به اینترنت وصل می‌شود انجام نده.
- `--scanners vuln`: فقط آسیب‌پذیری پکیج‌ها (نه secret و نه misconfiguration).
- `--severity HIGH,CRITICAL`: فقط موارد مهم.
- `--ignore-unfixed`: مواردی که نسخه‌ی اصلاح‌شده ندارند را نشان نده، چون کاری برایشان نمی‌شود کرد.
- `--exit-code 1`: اگر مورد باقی ماند، با کد خطای ۱ تمام شود. make آن را `Error 1` نشان می‌دهد، و این یعنی «دروازه رد شد».

علامت `\` در پایان خط یعنی دستور در خط بعد ادامه دارد.

```makefile
run-image:
	docker run -d --name churn-api --network $(NETWORK) -p 127.0.0.1:8001:8000 \
	  -e MLFLOW_TRACKING_URI=$(MLFLOW_IN_DOCKER) $(IMAGE):$(TAG)
```

هدف `run-image`: container را در پس‌زمینه (`-d`) با نام `churn-api` روی شبکه‌ی `mlops-lab` اجرا می‌کند. `-p 127.0.0.1:8001:8000` پورت ۸۰۰۰ داخل container را فقط روی `localhost:8001` لپ‌تاپ باز می‌کند (پورت ۸۰۰۰ را برای `make serve` جلسه‌ی ۸ آزاد می‌گذاریم). گزینه‌ی `-e` نشانی MLflow را به‌صورت متغیر محیطی به container می‌دهد.

```makefile
push:
	docker tag $(IMAGE):$(TAG) $(REGISTRY)/$(IMAGE):$(TAG)
	docker push $(REGISTRY)/$(IMAGE):$(TAG)
```

هدف `push`: اول با `docker tag` یک نام دوم به همان image می‌دهد که نشانی registry را دارد (`localhost:5001/churn-api:0.7.0`)، بعد با `docker push` آن را می‌فرستد. یک image می‌تواند چند نام داشته باشد و داده تکرار نمی‌شود.

جلوی خط‌های دستور باید TAB باشد، نه فاصله.

---

## فایل `Dockerfile.naive`

**کار فایل:** «اولین تلاش» که کار می‌کند ولی چند مشکل دارد. فقط برای مقایسه است و در کار اصلی ساخته نمی‌شود. اندازه‌ی آن 2.16GB بود (در برابر 1.29GB image اصلی).

```dockerfile
FROM python:3.12-slim-bookworm
WORKDIR /app
COPY . .
RUN pip install uv==0.12.15 && uv sync --frozen
CMD ["uv", "run", "uvicorn", "churn.api:app", "--host", "0.0.0.0", "--port", "8000"]
```

| خط | مشکل |
|---|---|
| `FROM` (فقط یک مرحله) | هر ابزار ساخت در image نهایی می‌ماند |
| `COPY . .` | کل پوشه‌ی پروژه (با `.env`، `.git`، داده‌ها و `.venv` لپ‌تاپ) داخل image می‌رود؛ بدون `.dockerignore` کلیدها هم می‌روند. همچنین هر تغییر کوچک در هر فایل cache نصب کتابخانه‌ها را باطل می‌کند، چون کتابخانه‌ها و کد در یک لایه‌ی کپی ترکیب‌اند |
| `pip install uv ... && uv sync --frozen` | `uv` در image نهایی می‌ماند (یک آسیب‌پذیری CRITICAL در آن پیدا شد)، کتابخانه‌های توسعه (`dvc`، `pytest`، `ruff`) هم نصب می‌شوند (چون `--no-dev` نیست) و `.venv` حدود 740MB شد |
| نبودن `USER` | برنامه با root اجرا می‌شود (`uid=0`) |
| نبودن `HEALTHCHECK` | Docker نمی‌داند برنامه سالم است یا نه |
| `CMD ["uv", "run", ...]` | برنامه از طریق `uv` اجرا می‌شود، پس `uv` باید در image بماند و هر شروع یک لایه‌ی اضافه از ابزار را وارد مسیر اجرا می‌کند |
| نبودن `ENV` برای MLflow | تنظیم‌های MLflow فقط از فایل `.env` داخل image می‌آیند؛ یعنی برنامه برای کار کردن به همان راز وابسته است که نباید در image باشد |

درس این مقایسه: image ساده کار می‌کند، اما بزرگ‌تر، با دسترسی بیشتر و با آسیب‌پذیری و راز در خودش است. هر خطِ Dockerfile اصلی جوابی به یکی از این مشکل‌هاست.

---

## پرسش‌هایی برای فکر کردن

1. اگر در Dockerfile دو خط `COPY pyproject.toml ...` و `COPY src` را ادغام کنیم (همه‌چیز را یک‌جا کپی کنیم و بعد `uv sync` بزنیم)، با تغییر یک خط در `api.py` چه اتفاقی برای زمان ساخت می‌افتد؟ چرا؟
2. چرا `HEALTHCHECK` به `/health` وصل شده و نه `/ready`؟ اگر به `/ready` وصل بود و MLflow خاموش می‌شد، Docker (یا بعداً Kubernetes) چه می‌کرد و آیا restart کردن container کمک می‌کرد؟
3. اگر `--host 0.0.0.0` را به `127.0.0.1` عوض کنیم، `curl localhost:8001/ready` از لپ‌تاپ جواب می‌دهد؟ چرا؟
4. فرض کنید فایل `.dockerignore` را حذف کردید. چه چیزهایی به image می‌رسد و کدام مورد از همه خطرناک‌تر است؟ (فقط فکر کنید؛ کلید واقعی در image نگذارید.)
5. با `--ignore-unfixed` در `make scan` چه ریسکی را می‌پذیریم؟ چه زمانی این انتخاب غلط است؟

</div>
