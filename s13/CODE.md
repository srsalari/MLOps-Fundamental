<div dir="rtl">

# توضیح کد جلسه‌ی ۱۳

در این جلسه کد پایتون مدل و API تغییر نمی‌کند. چیزهای تازه چهار دسته‌اند: سه فایل workflow برای CI، پوشه‌ی `monitoring/` برای Prometheus و Grafana، سه اسکریپت کوچک پایتون، و هدف‌های تازه‌ی Makefile.

فایل‌های این جلسه:

- پوشه‌ی `.gitea/workflows/`: سه فایل `ci.yaml`، `ml-ci.yaml` و `retrain.yaml` (گام ۱ و ۲).
- پوشه‌ی `monitoring/`: `docker-compose.yml`، تنظیم Prometheus (`prometheus.yml` و `alerts.yml`)، تنظیم Grafana (`provisioning/`) و فایل داشبورد `churn-api.json` (گام ۳ و ۵).
- پوشه‌ی `scripts/`: `pr_comment.py`، `loadgen.py` و `drift_report.py`.
- پوشه‌ی `tests/`: `test_pr_comment.py` و `test_drift_summary.py`.
- فایل `Makefile`: هدف‌های تازه.
- فایل `preflight.sh`: بررسی آمادگی پیش از کلاس (کد آموزشی نیست و اینجا توضیح داده نمی‌شود).

کامنت‌های داخل فایل‌ها عمداً انگلیسی هستند. شرح فارسی همه‌چیز در همین فایل است.

---

## مفهوم پایه: workflow چیست؟

یک workflow یک فایل YAML است که به Gitea می‌گوید «وقتی این اتفاق افتاد، این کارها را به‌ترتیب انجام بده». ساختارش سه لایه است:

```text
workflow   (یک فایل)       on: چه رویدادی آن را شروع می‌کند
  job      (یک ماشین)       runs-on: روی کدام نوع runner
    step   (یک دستور)       run: خود دستور shell
```

هر **job** در یک container تازه (از image به نام `mlops/ci-job:1.0`) اجرا می‌شود و بعد از پایان دور انداخته می‌شود. به همین دلیل job هیچ چیزی از اجرای قبلی به یاد ندارد: هر بار پروژه را دوباره checkout و کتابخانه‌ها را دوباره نصب می‌کند. (ما فقط cache کتابخانه‌ها را با یک volume نگه می‌داریم.)

---

## فایل `.gitea/workflows/ci.yaml`

**کار فایل:** برای هر push روی `main` و هر Pull Request، پنج مرحله را اجرا می‌کند: lint، test، build، scan و (فقط روی `main`) push.

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
```

- `name`: نامی که در تب Actions می‌بینید.
- `on.push.branches: [main]`: با هر push روی `main` شروع می‌شود.
- `on.pull_request`: با هر Pull Request (باز شدن و هر push تازه به شاخه‌ی PR) شروع می‌شود.

```yaml
env:
  GITEA_INTERNAL: http://gitea:3000
  UV_LINK_MODE: copy
  MLFLOW_DISABLE_AGENT_HINT: "1"
```

- `env` در سطح workflow: متغیرهایی که همه‌ی stepها می‌بینند.
- `GITEA_INTERNAL`: آدرس Gitea **از دید container job**. داخل job، `localhost` خود job است، نه لپ‌تاپ. job در شبکه‌ی Docker به نام `mlops-lab` است و Gitea را با نام سرویس `gitea` می‌بیند.
- `UV_LINK_MODE: copy`: `uv` فایل‌ها را کپی کند، نه hard link (cache و پروژه روی دو volume جدا هستند و link کار نمی‌کند).
- `MLFLOW_DISABLE_AGENT_HINT`: پیام‌های اضافه‌ی MLflow را خاموش می‌کند.

```yaml
jobs:
  ci:
    runs-on: ubuntu-latest
```

- یک job به نام `ci`. مقدار `runs-on: ubuntu-latest` یک **برچسب** است؛ runner ما این برچسب را به image `mlops/ci-job:1.0` وصل کرده (در `compose/gitea-runner/config.yaml`).

```yaml
      - name: checkout
        run: |
          git init -q .
          git remote add origin "http://ci:${{ secrets.GITHUB_TOKEN }}@gitea:3000/${{ github.repository }}.git"
          git fetch -q --depth=1 origin "${{ github.sha }}"
          git checkout -q FETCH_HEAD
          git log --oneline -1
```

- مرحله‌ی اول باید کد را به job بیاورد. معمولاً برای این کار از `uses: actions/checkout@v4` استفاده می‌کنند، ولی `uses:` از اینترنت (GitHub) دانلود می‌کند. ما چهار دستور `git` ساده می‌نویسیم.
- `${{ ... }}` یک **عبارت** است که Gitea پیش از اجرا مقدارش را می‌گذارد. `github.repository` برابر `student/churn-mlops` و `github.sha` برابر hash دقیق commit است.
- `secrets.GITHUB_TOKEN`: یک توکن موقت که Gitea برای همین اجرا می‌سازد و بعد باطل می‌کند. نام `GITHUB_TOKEN` برای سازگاری با GitHub است. این توکن در لاگ به `***` تبدیل می‌شود.
- گزینه‌ی `--depth=1`: فقط همان یک commit را بگیر (سریع‌تر).

```yaml
      - name: install dependencies
        run: uv sync --frozen
      - name: lint
        run: make lint
      - name: test
        run: make test
```

- `uv sync --frozen`: دقیقاً کتابخانه‌های `uv.lock` را نصب کن و اگر `uv.lock` با `pyproject.toml` نمی‌خواند خطا بده (نه اینکه بی‌صدا عوضش کند).
- `make lint` و `make test` **همان** دستورهایی‌اند که روی لپ‌تاپ می‌زنید. این عمدی است: CI نباید یک «نسخه‌ی دیگر» از کار باشد. اگر روی لپ‌تاپ سبز است و در CI قرمز، تفاوت در محیط است، نه در دستور.

```yaml
      - name: build image
        run: make image TAG=ci-${GITHUB_SHA::7}
      - name: scan image (Trivy)
        run: make scan TAG=ci-${GITHUB_SHA::7}
```

- `make image` همان build جلسه‌ی ۹ است. به job سوکت Docker لپ‌تاپ داده شده، پس این build روی Docker خود لپ‌تاپ اجرا می‌شود (نه یک Docker داخل Docker).
- `TAG=ci-${GITHUB_SHA::7}`: tag از هفت حرف اول hash commit ساخته می‌شود (مثلاً `ci-1a2b3c4`). نسخه‌ی `0.7.0` ما دستی است؛ نسخه‌ی CI به commit گره خورده تا همیشه بدانیم این image از کدام کد آمده.
- Trivy بررسی می‌کند که فایل `.trivyignore` کنار پروژه هست یا نه. اگر باشد، هر شناسه‌ی CVE داخلش گزارش نمی‌شود؛ این یک استثنای آگاهانه است و باید کامنت و تاریخ داشته باشد. در این جلسه چنین فایلی نداریم: با پین `mlflow 3.17.2` سه یافته‌ی قبلی (که با پین `3.16.0` دیده شده بودند) از بین رفتند. اگر scan قرمز شد، اول کتابخانه را ارتقا دهید.
- `make scan` همان Trivy جلسه‌ی ۹ است، با پایگاه داده‌ی آفلاین داخل image job. با هر آسیب‌پذیری `HIGH` یا `CRITICAL` که راه‌حل دارد، کد خروج ۱ می‌دهد و job متوقف می‌شود (مرحله‌ی بعد اجرا نمی‌شود).

```yaml
      - name: push image
        if: github.ref == 'refs/heads/main'
        run: make push TAG=ci-${GITHUB_SHA::7}
```

- `if:` یک شرط روی همین step است. `github.ref` برای push روی main برابر `refs/heads/main` است و برای PR چیز دیگری. پس کد PR هنوز وارد registry نمی‌شود.
- `make push` به `localhost:5001` می‌فرستد. چون Docker لپ‌تاپ کار می‌کند، `localhost` همان لپ‌تاپ است.

---

## فایل `.gitea/workflows/ml-ci.yaml`

**کار فایل:** روی هر PR که چیزی مربوط به مدل را عوض کند، مدل را دوباره می‌سازد و metricها را با `main` مقایسه می‌کند.

```yaml
on:
  pull_request:
    paths:
      - "params.yaml"
      - "dvc.yaml"
      - "src/**"
      - "data/**"
      - ".gitea/workflows/ml-ci.yaml"
```

- `paths`: این workflow فقط وقتی شروع می‌شود که PR یکی از این مسیرها را عوض کرده باشد. تغییر README آموزش دوباره نمی‌خواهد.

```yaml
env:
  MLFLOW_TRACKING_URI: sqlite:///ci-mlflow.db
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

- `MLFLOW_TRACKING_URI: sqlite:///ci-mlflow.db`: run‌ای که CI می‌سازد در یک دیتابیس موقت داخل job ثبت می‌شود. هر PR روی سرور اصلی MLflow اجرای آزمایشی نمی‌ریزد. (کد `evaluate.py` جلسه‌ی ۶ هر آدرسی را می‌پذیرد، فقط برای آدرس `http` وجود سرور را چک می‌کند.)
- دو کلید S3: DVC از متغیرهای استاندارد `AWS_*` می‌خواند. مقدارها از secretهای مخزن می‌آیند، نه از کد.

stepهای مهم:

```yaml
      - name: checkout (the PR code and the main branch for the comparison)
        run: |
          ...
          git fetch -q origin main:refs/remotes/origin/main "${{ github.sha }}"
```

- این بار دو چیز لازم است: کد PR و شاخه‌ی `main` (برای مقایسه). `refs/remotes/origin/main` همان نامی است که `dvc metrics diff` بعداً با آن `main` را پیدا می‌کند.

```yaml
      - name: point DVC at the S3 server inside the Docker network
        run: uv run dvc remote modify --local storage endpointurl http://seaweedfs:8333
```

- در `.dvc/config` آدرس `http://localhost:8333` است (برای لپ‌تاپ درست است). داخل job باید `http://seaweedfs:8333` باشد. گزینه‌ی `--local` آن را در `.dvc/config.local` می‌نویسد که فقط در همین job است و در Git نمی‌رود.

```yaml
      - name: pull the data
        run: uv run dvc pull data/raw/churn.csv.dvc
      - name: retrain (dvc repro)
        run: uv run dvc repro
```

- فقط داده‌ی خام را می‌گیرد، بعد سه مرحله‌ی DVC (preprocess، train، evaluate) را اجرا می‌کند.

```yaml
      - name: compare the metrics with main
        run: |
          uv run dvc metrics diff origin/main --all --md | tee metrics-diff.md
```

- `dvc metrics diff origin/main`: `metrics.json` شاخه‌ی `main` را با نسخه‌ی تازه‌ی همین job مقایسه می‌کند. `--md` یعنی خروجی جدول Markdown و `--all` یعنی metricهای بدون تغییر هم بیایند. `tee` همزمان روی صفحه و در فایل می‌نویسد.

```yaml
      - name: comment on the pull request
        env:
          GITEA_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPO: ${{ github.repository }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
        run: uv run python scripts/pr_comment.py metrics-diff.md
```

- اسکریپت `pr_comment.py` اطلاعاتش را از این سه متغیر می‌گیرد. `github.event.pull_request.number` شماره‌ی PR است.

---

## فایل `.gitea/workflows/retrain.yaml`

**کار فایل:** مدل را با آخرین داده می‌سازد و به‌عنوان `@challenger` ثبت می‌کند.

```yaml
on:
  schedule:
    - cron: "0 3 * * 1"
  workflow_dispatch:
```

- `cron: "0 3 * * 1"`: پنج فیلد: دقیقه، ساعت، روز ماه، ماه، روز هفته. یعنی «دقیقه‌ی ۰، ساعت ۳، هر روز ماه، هر ماه، دوشنبه‌ها». ساعت به وقت **UTC سرور Gitea** است.
- `workflow_dispatch`: دکمه‌ی `Run Workflow` در Gitea. تعریف‌های `schedule` و `workflow_dispatch` فقط وقتی کار می‌کنند که فایل روی شاخه‌ی پیش‌فرض (`main`) باشد.

```yaml
env:
  MLFLOW_TRACKING_URI: http://mlflow:5000
```

- این بار run روی سرور **اصلی** MLflow (سرویس `mlflow` در شبکه‌ی Docker) ثبت می‌شود، چون می‌خواهیم نسخه‌ی تازه‌ی مدل در Registry باشد.

```yaml
      - name: retrain and log the run to MLflow
        run: uv run dvc repro --force
      - name: register the new model as @challenger
        run: |
          RUN=$(uv run python scripts/list_runs.py | awk 'NR==2 {print $1}')
          echo "newest run: $RUN"
          uv run python -m churn.registry register --run "$RUN"
          uv run python -m churn.registry show
```

- گزینه‌ی `--force`: حتی اگر چیزی عوض نشده، مرحله‌ها را دوباره اجرا کن (retrain یعنی تازه آموزش بده).
- خروجی `list_runs.py` یک جدول است؛ `awk 'NR==2 {print $1}'` ستون اول سطر دوم، یعنی شناسه‌ی جدیدترین run، را برمی‌دارد.
- `registry register` نسخه‌ی تازه می‌سازد و فقط `@challenger` می‌گذارد. این workflow **عمداً** `promote` ندارد.

---

## فایل `scripts/pr_comment.py`

**کار فایل:** یک کامنت روی PR می‌نویسد یا اگر قبلاً نوشته، همان را به‌روز می‌کند.

- `MARKER = "<!-- metrics-diff -->"`: یک نشانه‌ی پنهان (کامنت HTML، در Gitea دیده نمی‌شود) که اول متن کامنت می‌آید.
- `build_body(table)`: متن نهایی را می‌سازد: نشانه، یک عنوان و جدول. اگر جدول خالی باشد، یک پیام ساده می‌گذارد. این تابع **خالص** است (فقط متن می‌گیرد و متن می‌دهد)، پس بدون شبکه تست می‌شود.
- `find_comment(comments)`: در فهرست کامنت‌ها، اولی را که `MARKER` دارد برمی‌گرداند، یا `None`.
- `call(method, url, token, payload)`: یک درخواست HTTP به API گیتی با `urllib` (کتابخانه‌ی استاندارد، پس نصب اضافه لازم نیست). هدر `Authorization: token ...` توکن job را می‌فرستد.
- `main()`: فهرست کامنت‌های PR را می‌خواند. اگر کامنت نشانه‌دار هست، `PATCH` (ویرایش)؛ وگرنه `POST` (ساختن).

چرا نشانه؟ بدون آن هر push تازه یک کامنت جدید می‌گذاشت و بعد از ده push، ده کامنت داشتید.

## فایل `scripts/loadgen.py`

**کار فایل:** ترافیک ساختگی به `/predict` می‌فرستد.

- `customer(rng, bad)`: یک مشتری تصادفی می‌سازد. با `bad=True` مقدار `tenure_months` را `-5` می‌کند که قرارداد ورودی (`ge=0`) را می‌شکند و API با `422` جواب می‌دهد.
- `send(url, body)`: یک `POST` می‌فرستد و فقط **کد وضعیت** را برمی‌گرداند. خطاهای ۴xx و ۵xx در `urllib` به‌صورت استثنا می‌آیند؛ اینجا گرفته می‌شوند و عدد برمی‌گردانند. اگر API اصلاً جواب ندهد، کد `0`.
- `main()`: با `--rps` سرعت، با `--seconds` مدت و با `--bad-rate` سهم درخواست‌های غلط را می‌گیرد. `random.Random(seed)` ترافیک را تکرارپذیر می‌کند. در پایان تعداد هر کد وضعیت را چاپ می‌کند.

## فایل `scripts/drift_report.py`

**کار فایل:** داده‌ی دو نسخه را با Evidently مقایسه می‌کند.

- `fetch(rev, folder)`: با `dvc get . data/raw/churn.csv --rev TAG` فایل داده را **همان‌طور که در آن tag بود** از SeaweedFS می‌گیرد، بدون اینکه پوشه‌ی کار شما را عوض کند (برخلاف `git checkout` و `dvc checkout`).
- `summarize(snapshot)`: خروجی Evidently را به سطرهای ساده تبدیل می‌کند. روش‌های «فاصله» (مثل Wasserstein و Jensen-Shannon) وقتی عدد از آستانه **بزرگ‌تر یا مساوی** باشد drift می‌گویند؛ روش‌های «آزمون آماری» که p-value می‌دهند وقتی عدد از آستانه **کوچک‌تر** باشد. این تابع هم خالص است و تست دارد.
- در `main()` سه خط اصلی:

```python
snapshot = Report([DataDriftPreset()]).run(cur, ref)
snapshot.save_html(str(out))
rows = summarize(snapshot.dict())
```

- `DataDriftPreset()` یک بسته‌ی آماده است که برای هر ستون یک آزمون drift مناسب نوع ستون انتخاب می‌کند. `run(cur, ref)`: **اول داده‌ی فعلی، بعد مرجع.** ترتیب را جابه‌جا نکنید. `save_html` گزارش مستقل را می‌نویسد؛ `dict()` همان اعداد را برای چاپ در ترمینال می‌دهد.
- import کتابخانه‌ی Evidently داخل `main()` است، نه بالای فایل، تا تست‌ها و CI بدون نصب Evidently هم بتوانند `summarize` را import کنند.

---

## پوشه‌ی `monitoring/`

### `docker-compose.yml`

سه سرویس:

- `churn-api-mon`: API جلسه‌ی ۹ (`image: churn-api:0.7.0`). با `MODEL_URI` از محیط، که پیش‌فرض `models:/churn@champion` است. `make api-break` این متغیر را موقتاً `models:/churn/99` می‌کند.
- `prometheus`: image با نسخه‌ی پین‌شده. `--storage.tsdb.retention.time=2d` داده را ۲ روز نگه می‌دارد. `--web.enable-lifecycle` اجازه‌ی reload با `POST /-/reload` می‌دهد.
- `grafana`: با `GF_SECURITY_ADMIN_PASSWORD` رمز آزمایشگاه. دو mount فقط‌خواندنی دارد: `provisioning/` (تنظیم) و `dashboards/` (داشبورد).

بخش `networks.default` با `external: true`: به شبکه‌ای که از قبل هست (`mlops-lab`، همان شبکه‌ی MLflow و Gitea) می‌پیوندد، نه یک شبکه‌ی تازه. به همین دلیل API می‌تواند `http://mlflow:5000` را ببیند. متغیر `LAB_NETWORK` فقط برای آزمایش است.

### `prometheus/prometheus.yml`

- `scrape_interval: 5s`: هر ۵ ثانیه `/metrics` را بخوان (در عمل ۱۵ ثانیه رایج است؛ ۵ برای کلاس تا نمودار زود پر شود).
- `scrape_configs`: دو **job**. `churn-api` به آدرس `churn-api-mon:8000/metrics` (نام سرویس compose و پورت داخل container) و `prometheus` که خودش را می‌خواند. برچسب `job` روی هر نمونه نام همین job است (در PromQL: `{job="churn-api"}`).
- `rule_files`: فایل alertها.

### `prometheus/alerts.yml`

```yaml
- alert: ChurnApiDown
  expr: up{job="churn-api"} == 0
  for: 15s
```

- `up` متریکی است که Prometheus خودش برای هر target می‌سازد: ۱ یعنی scrape موفق، ۰ یعنی ناموفق.
- `for: 15s`: شرط باید ۱۵ ثانیه پشت سر هم درست باشد، تا alert از `Pending` به `Firing` برود. این از آلارم‌های کاذب جلوگیری می‌کند.
- Alertmanager نداریم؛ فقط وضعیت در صفحه‌ی `/alerts` دیده می‌شود.

### `grafana/provisioning/`

- `datasources/prometheus.yml`: به Grafana می‌گوید یک data source با `uid: prometheus-lab` به آدرس `http://prometheus:9090` وجود دارد. `uid` ثابت است تا فایل داشبورد بتواند به آن اشاره کند.
- `dashboards/dashboards.yml`: می‌گوید داشبوردها را از پوشه‌ی `/var/lib/grafana/dashboards` بخوان.

### `grafana/dashboards/churn-api.json`

داشبورد یک فایل JSON است: فهرست `panels`، هر کدام با `title`، `type` و `targets` که هر target یک عبارت PromQL است. چهار عبارت اصلی:

```text
Rate     sum(rate(http_requests_total{job="churn-api",handler!="/metrics"}[1m]))
Errors   sum(rate(http_requests_total{...,status="5xx"}[1m])) / sum(rate(http_requests_total{...}[1m]))
Duration histogram_quantile(0.95, sum by (le) (rate(http_request_duration_highr_seconds_bucket{job="churn-api"}[1m])))
Up       min(up{job="churn-api"})
```

- `http_requests_total`: شمارنده. `rate(...[1m])` یعنی «در میانگین یک دقیقه‌ی گذشته، چند در ثانیه بالا رفت».
- `handler!="/metrics"`: خود scrape‌های Prometheus را از شمارش بیرون می‌گذارد.
- `status="5xx"`: کتابخانه‌ی instrumentator کدها را گروه‌بندی می‌کند: `2xx`، `4xx`، `5xx`.
- `histogram_quantile(0.95, ...)`: از روی **سطل‌های زمان** (`_bucket`) زمانی را حدس می‌زند که ۹۵٪ درخواست‌ها از آن سریع‌ترند. `le` یعنی «کمتر یا مساوی» و هر سطل تعداد درخواست‌های سریع‌تر از یک زمان معین است.
- چرا Git؟ چون داشبورد را مثل کد بازبینی، بازیابی و روی لپ‌تاپ دیگر دوباره بالا می‌آورید. اگر در رابط Grafana پنلی را عوض کنید و Save بزنید، فایل عوض نمی‌شود (`allowUiUpdates` فقط اجازه‌ی تغییر در رابط را می‌دهد)؛ برای ماندن باید JSON را export و در فایل بگذارید.

---

## فایل `Makefile` (هدف‌های تازه)

| هدف | کار |
|---|---|
| `runner-up` | `docker compose --profile ci up -d gitea-runner` در `~/mlops-lab/compose` |
| `mon-up` | `docker compose -f monitoring/docker-compose.yml up -d` |
| `mon-down` | همان با `down` (هرگز `-v`) |
| `mon-status` | `docker compose ps` و وضعیت targetهای Prometheus (متغیر `PROM_URL`) |
| `api-break` | `MODEL_URI=models:/churn/99 ... up -d churn-api-mon`: API را با مدل ناموجود دوباره می‌سازد |
| `api-fix` | همان بدون `MODEL_URI`، پس `@champion` |
| `load` | `loadgen.py` با `RPS`، `DURATION` و `BAD` |
| `drift` | `uv run --group drift python scripts/drift_report.py` |

متغیرها: `MON` (دستور compose)، `API_URL` (پیش‌فرض `http://localhost:8003`)، `PROM_URL` (پیش‌فرض `http://localhost:9090`)، `RPS`، `DURATION`، `BAD`.

## تست‌ها

- `tests/test_pr_comment.py`: بدنه‌ی کامنت با نشانه شروع می‌شود، جدول خالی پیام می‌گیرد، و `find_comment` کامنت نشانه‌دار را پیدا می‌کند.
- `tests/test_drift_summary.py`: روش فاصله با عدد بزرگ‌تر از آستانه drift است و روش p-value با عدد کوچک‌تر از آستانه drift است. هر دو بدون شبکه و بدون Evidently اجرا می‌شوند، پس در `make test` و CI هم می‌دوند.

</div>
