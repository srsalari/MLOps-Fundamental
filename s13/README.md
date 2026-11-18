<div dir="rtl">

# آزمایشگاه جلسه‌ی ۱۳ — CI هوشمند، مانیتورینگ و drift

تا جلسه‌ی ۱۲ سرویس را ساختید، بسته‌بندی کردید و روی Kubernetes بردید. ولی هنوز همه‌چیز را **با دست** اجرا می‌کنید: lint و test را یادتان باشد بزنید، image را خودتان build و scan کنید، و اگر سرویس خراب شود فقط وقتی می‌فهمید که کسی به شما بگوید. در این جلسه سه کار را خودکار می‌کنید.

اول، **CI**: هر بار که کدی وارد `main` می‌شود، یک ماشین (runner روی Gitea Actions) به‌ترتیب lint، test، build، scan و push را اجرا می‌کند. دوم، **CI مخصوص ML**: هر Pull Request که پارامتر مدل را عوض کند، مدل را دوباره آموزش می‌دهد و جدول تغییر metricها را خودش به‌صورت یک کامنت روی همان PR می‌نویسد؛ و یک workflow زمان‌بندی‌شده (retrain) مدل تازه می‌سازد و آن را `@challenger` می‌کند. سوم، **مانیتورینگ**: Prometheus اعداد API را جمع می‌کند، Grafana آن‌ها را به شکل سه نمودار Rate / Errors / Duration نشان می‌دهد، و در آخر با Evidently می‌بینید که داده‌ی نسخه‌ی ۲ چقدر با نسخه‌ی ۱ فرق دارد (**data drift**).

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۱۲ سالم باشد: `main` شامل tag `v0.10.0` است (پوشه‌ی `chart/`، فایل `k8s/ingress.yaml` و هدف‌های helm در Makefile).
2. سرویس‌های آزمایشگاه روشن باشند: SeaweedFS، MLflow و Gitea (`docker compose ps` در `~/mlops-lab/compose`). `docker compose down -v` نزده باشید.
3. <bdi dir="rtl">registry محلی (`localhost:5001`) روشن باشد و `churn-api:0.7.0` را داشته باشد (از جلسه‌ی ۹ و ۱۱). image `churn-api:0.7.0` روی لپ‌تاپ هم باشد (`docker image ls churn-api`).</bdi>
4. <bdi dir="rtl">cluster جلسه‌ی ۱۱ و ۱۲ **لازم نیست** روشن باشد. این جلسه فقط Docker می‌خواهد. اگر کم‌حافظه‌اید، `kind` را خاموش کنید (`docker stop mlops-control-plane`).</bdi>
5. **حافظه‌ی Docker حداقل ۶ گیگابایت.** در اوج کلاس این‌ها با هم روشن‌اند: MLflow و SeaweedFS و Gitea (از قبل)، runner و یک container برای هر job، و Prometheus و Grafana و API. سهم تازه‌ی این جلسه تقریباً ۱ تا ۱٫۲ گیگابایت است (جدول اندازه‌گیری در گام ۳).
6. **اینترنت یا PyPI mirror لازم است.** هر job در CI کتابخانه‌های پروژه را با `uv sync` می‌گیرد و `docker build` هم همین کار را می‌کند. بدون اینترنت از مدرس بپرسید (مدرس mirror یا cache آماده می‌کند).
7. <bdi dir="rtl">image برای job‌ها یعنی `mlops/ci-job:1.0` روی لپ‌تاپ باشد (از بسته‌ی آفلاین دوره با `~/mlops-lab/scripts/install-from-bundle.sh` نصب می‌شود). بدون آن runner هیچ job را شروع نمی‌کند.</bdi>
8. بررسی آمادگی را اجرا کنید:

```bash
~/mlops-lab/s13/preflight.sh
```

اگر خطایی داد، پیام آن راه‌حل را می‌گوید. بعد مخزن دوره را به‌روز کنید:

```bash
git -C ~/mlops-lab pull
```

> دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell.

## مفهوم‌ها در یک نگاه

| مفهوم | یک جمله |
| --- | --- |
| **CI** (Continuous Integration) | هر تغییر کد خودکار آزموده می‌شود، تا خرابی همان لحظه پیدا شود نه هفته‌ی بعد |
| **Gitea Actions** | CI داخل خود Gitea؛ فایل‌های YAML در پوشه‌ی `.gitea/workflows/` تعریف می‌کنند چه چیزی، چه وقت اجرا شود |
| **runner** | برنامه‌ای که job را از Gitea می‌گیرد و در یک container تازه اجرا می‌کند. اینجا `laptop-runner` با image به نام `mlops/ci-job:1.0` |
| **pipeline** | زنجیره‌ی lint، test، build، scan و push. اگر یک مرحله قرمز شود، بعدی‌ها اجرا نمی‌شوند |
| **metrics-diff** | جدول «metric روی main چقدر بود و روی این PR چقدر شد». تصمیم‌گیرنده‌ی Merge عدد را می‌بیند، نه حدس |
| **retrain زمان‌بندی‌شده** | یک workflow که با ساعت (cron) یا با دکمه اجرا می‌شود، مدل را دوباره می‌سازد و فقط `@challenger` می‌کند. ارتقا به `@champion` هنوز کار آدم است |
| **RED** | سه سؤال برای هر سرویس: **R**ate (چند درخواست در ثانیه)، **E**rrors (چند درصد خراب)، **D**uration (چقدر طول کشید) |
| **Prometheus** | هر ۵ تا ۱۵ ثانیه به آدرس `/metrics` سرویس سر می‌زند و عددها را با زمان ذخیره می‌کند (روش pull) |
| **Grafana** | از Prometheus می‌پرسد و نمودار می‌کشد. داشبورد ما یک فایل JSON در Git است، نه کلیک‌های دستی |
| **alert rule** | یک سؤال Prometheus که اگر مدتی جوابش «بله» باشد، alert روشن (`firing`) می‌شود |
| **data drift** | داده‌ی امروز با داده‌ای که مدل با آن آموزش دید فرق کرده است. Evidently این فرق را ستون‌به‌ستون می‌سنجد |

مسیر یک تغییر در این جلسه:

```text
git push  ->  Gitea  ->  runner (container mlops/ci-job)  ->  lint -> test -> build -> scan -> push (registry 5001)
Pull Request که params.yaml را عوض می‌کند  ->  dvc repro  ->  کامنت metrics-diff روی PR
API (container)  <-- /metrics --  Prometheus (9090)  -->  Grafana (3001)
data-v1  +  data-v2  ->  Evidently  ->  reports/drift-v1-v2.html
```

## نتیجه‌ی نهایی

- پوشه‌ی `.gitea/workflows/` با سه workflow: `ci.yaml`، `ml-ci.yaml` و `retrain.yaml`
- <bdi dir="rtl">runner روشن و یک اجرای سبز CI روی `main` که image به نام `churn-api:ci-<sha>` را به registry فرستاد</bdi>
- یک Pull Request با کامنت خودکار metrics-diff، و یک اجرای retrain که نسخه‌ی تازه‌ی مدل را `@challenger` کرد
- پوشه‌ی `monitoring/` با Prometheus، Grafana و API؛ داشبورد «Churn API: RED metrics» که از فایل JSON بالا می‌آید
- گزارش `reports/drift-v1-v2.html` از Evidently
- یک alert نمونه (`ChurnApiDown`) که دیدید روشن می‌شود
- همه‌ی این‌ها در پروژه، با tag نسخه‌ی `v0.11.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| فایل `.gitea/workflows/ci.yaml` | همان مسیر | pipeline پایه: lint، test، build، scan، push |
| فایل `.gitea/workflows/ml-ci.yaml` | همان مسیر | آموزش دوباره روی هر PR و کامنت metrics-diff |
| فایل `.gitea/workflows/retrain.yaml` | همان مسیر | retrain زمان‌بندی‌شده (یا با دکمه) و ثبت `@challenger` |
| `monitoring/` | همان مسیر | compose و تنظیم Prometheus، تنظیم Grafana و فایل JSON داشبورد |
| `scripts/pr_comment.py` | پوشه‌ی `scripts/` | نوشتن یا به‌روز کردن کامنت روی PR از طریق API گیتی |
| `scripts/loadgen.py` | پوشه‌ی `scripts/` | تولید ترافیک ساختگی برای داشبورد |
| `scripts/drift_report.py` | پوشه‌ی `scripts/` | گزارش drift با Evidently |
| `tests/test_pr_comment.py`، `tests/test_drift_summary.py` | پوشه‌ی `tests/` | تست‌های این دو اسکریپت (بدون شبکه) |
| `Makefile` | ریشه‌ی پروژه (جای Makefile جلسه‌ی ۱۲) | هدف‌های تازه‌ی `runner-up`، `mon-up`، `mon-down`، `mon-status`، `api-break`، `api-fix`، `load`، `drift` |
| `preflight.sh` | اجرا از همین پوشه | بررسی آمادگی پیش از کلاس |

توضیح خط‌به‌خط همه‌ی فایل‌ها به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — runner و pipeline پایه‌ی CI (۱۸ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git describe --tags
```

انتظار: `v0.10.0` (اگر تکلیف جلسه‌ی ۱۲ را merge کرده‌اید چیزی مثل `v0.10.0-2-g1a2b3c4` می‌بینید؛ مشکلی نیست)

```bash
git switch -c feature/ci-monitoring
```

### فایل‌های جلسه را کپی کنید

```bash
S=~/mlops-lab/s13
```

```bash
cp -r $S/.gitea $S/monitoring .
```

```bash
cp $S/scripts/*.py scripts/ && cp $S/tests/*.py tests/ && cp $S/Makefile .
```

یک بار همه را به چشم ببینید:

```bash
ls .gitea/workflows
```

انتظار: `ci.yaml  ml-ci.yaml  retrain.yaml`

فایل `ci.yaml` را در ویرایشگر باز کنید و بخوانید. دو نکته‌ی مهم: (۱) مرحله‌ی checkout با `git` ساده نوشته شده، نه `uses: actions/checkout`، چون `uses:` از اینترنت دانلود می‌کند و در کلاس کار نمی‌کند. (۲) مرحله‌ی `push image` فقط روی `main` اجرا می‌شود (`if: github.ref == 'refs/heads/main'`)؛ کدِ یک PR هنوز وارد registry نمی‌شود.

### اول runner را روشن کنید

<bdi dir="rtl">runner باید یک بار در Gitea ثبت‌نام کند. Gitea برای این کار یک **توکن ثبت‌نام** می‌دهد. توکن را بسازید و در فایل `.env` مخزن دوره بگذارید (آن فایل در Git نیست):</bdi>

```bash
cd ~/mlops-lab/compose
```

```bash
TOKEN=$(docker exec -u git gitea gitea actions generate-runner-token)
```

```bash
grep -v '^RUNNER_TOKEN=' .env > .env.tmp && echo "RUNNER_TOKEN=$TOKEN" >> .env.tmp && mv .env.tmp .env
```

```bash
cd ~/work/churn-mlops && make runner-up
```

انتظار: چند خط `Container gitea-runner ... Started` و در آخر `Started`. ثبت‌نام را در لاگ ببینید:

```bash
docker logs --tail 4 gitea-runner
```

انتظار (زمان‌ها فرق دارند):

```text
level=info msg="Runner registered successfully."
SUCCESS
level=info msg="Starting runner daemon"
level=info msg="runner: laptop-runner, with version: v0.6.1, with labels: [ubuntu-latest], declare successfully"
```

در Gitea (`http://localhost:3000`) از منوی کاربر **Site Administration**، بعد **Actions** و **Runners** بروید: `laptop-runner` با وضعیت `Idle` باید در فهرست باشد.

### دو secret برای CI

<bdi dir="rtl">CI فردا باید داده‌ی DVC را از SeaweedFS بگیرد. کلیدها را **داخل کد نمی‌گذاریم**؛ در Gitea به‌عنوان secret نگه می‌داریم. مقدارها همان‌هایی‌اند که در `.env` پروژه دارید:</bdi>

```bash
grep '^AWS_' .env
```

در Gitea مخزن `churn-mlops` را باز کنید: **Settings**، **Actions**، **Secrets**، **Add Secret**. دو secret بسازید، با نام و مقدار دقیقاً این‌ها (مقدار از خروجی بالا):

| نام secret | مقدار |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | مقدار `AWS_ACCESS_KEY_ID` از `.env` |
| `AWS_SECRET_ACCESS_KEY` | مقدار `AWS_SECRET_ACCESS_KEY` از `.env` |

<bdi dir="rtl">secret بعد از ذخیره دیگر نمایش داده نمی‌شود و در لاگ job به‌صورت `***` می‌آید.</bdi>

### اولین اجرای pipeline

```bash
make lint && make test
```

انتظار: `All checks passed!` و بعد `26 passed` (دو تست‌فایل تازه اضافه شده‌اند؛ تعداد دقیق ممکن است کمی فرق کند). اگر روی لپ‌تاپ سبز نیست، CI هم سبز نمی‌شود.

```bash
git add -A && git commit -m "ci: Gitea Actions pipeline, metrics-diff, retrain, monitoring"
```

```bash
git push -u origin feature/ci-monitoring
```

در Gitea برای شاخه‌ی `feature/ci-monitoring` یک Pull Request بسازید (عنوان: `CI and monitoring`). کمی بعد در همان صفحه‌ی PR (یا تب **Actions** مخزن) دو اجرا می‌بینید: `ci` و `ml-ci` (چون خود فایل `ml-ci.yaml` تغییر کرده، آن هم شروع می‌شود). runner فقط یک job را در هر لحظه می‌گیرد؛ پس دومی منتظر می‌ماند. روی اجرای `ci` کلیک کنید و مرحله‌ها را ببینید:

```text
checkout  ->  install dependencies  ->  lint  ->  test  ->  build image  ->  scan image (Trivy)  ->  (push image: روی PR رد می‌شود)
```

زمان‌های ما (لپ‌تاپ Apple Silicon، اینترنت خانگی): نصب کتابخانه‌ها ۲۰ تا ۴۰ ثانیه، lint یک ثانیه، test حدود ۱۵ ثانیه، build حدود یک و نیم دقیقه، scan حدود ۲۰ ثانیه؛ در مجموع ۲ تا ۳ دقیقه برای اولین اجرا.

> **درباره‌ی scan (Trivy):** Trivy مرحله‌ی scan را واقعاً جدی می‌گیرد. با پایگاه داده‌ی تازه و پین قدیمی `mlflow 3.16.0`، سه آسیب‌پذیری گزارش شد (`CVE-2026-116692`، `CVE-2026-116690` و `CVE-2026-53995`) که در نسخه‌های ۳٫۱۷ رفع شده‌اند. دوره پین را به `mlflow 3.17.2` بالا برد و این سه مورد با همین ارتقا از بین رفتند (روی lock file بررسی شد؛ اسکن image در CI باید سبز باشد). اگر scan شما قرمز شد، جدول لاگ را بخوانید، ستون‌های `Library` و `Fixed Version` را نگاه کنید و کتابخانه را ارتقا دهید (`uv lock --upgrade-package NAME`). فایل استثنای `.trivyignore` فقط آخرین راه است: برای آسیب‌پذیری‌ای که هنوز راه‌حل ندارد، با کامنت و تاریخ و با نظر مدرس. هرگز خود مرحله‌ی scan را از workflow پاک نکنید.

وقتی `ci` سبز شد، PR را Merge کنید (Merge در Gitea). Merge یک اجرای تازه‌ی `ci` روی `main` شروع می‌کند، این بار با مرحله‌ی push. بعد از چند دقیقه، registry را ببینید:

```bash
curl -s http://localhost:5001/v2/churn-api/tags/list
```

انتظار: چیزی مثل `{"name":"churn-api","tags":["0.7.0","ci-1a2b3c4"]}` (هفت حرف hash commit روی `main`).

```bash
git switch main && git pull
```

---

## گام ۲ — CI مخصوص ML: metrics-diff و retrain (۱۷ دقیقه)

### یک PR که مدل را عوض می‌کند

```bash
git switch -c feature/tune-c
```

مقدار `C` (قدرت regularization) را از `0.1` به `0.5` ببرید. این دستور فقط همان یک خط را عوض می‌کند:

```bash
sed -i.bak 's/^  C: 0.1$/  C: 0.5/' params.yaml && rm params.yaml.bak
```

```bash
git diff params.yaml
```

انتظار: یک خط `-  C: 0.1` و یک خط `+  C: 0.5`

نکته: لازم نیست خودتان `make train` بزنید. CI خودش مدل را دوباره می‌سازد. فقط تغییر پارامتر را commit کنید و بفرستید:

```bash
git commit -am "feat: try C=0.5" && git push -u origin feature/tune-c
```

در Gitea یک Pull Request از `feature/tune-c` به `main` بسازید. دو اجرا شروع می‌شود (`ci` و `ml-ci`). اجرای `ml-ci` را باز کنید و مرحله‌ها را ببینید: `pull the data` داده را از SeaweedFS می‌گیرد، `retrain (dvc repro)` سه مرحله‌ی DVC را اجرا می‌کند (این بار run در یک دیتابیس موقت MLflow داخل job ثبت می‌شود، نه روی سرور اصلی)، و `compare the metrics with main` جدول را می‌سازد.

بعد از حدود دو دقیقه، صفحه‌ی خود PR را تازه کنید. یک کامنت از کاربر `gitea-actions` می‌بینید:

```text
### Metrics change

| Path         | Metric   | origin/main   | workspace   | Change   |
|--------------|----------|---------------|-------------|----------|
| metrics.json | f1       | 0.701         | 0.6991      | -0.0019  |
| metrics.json | roc_auc  | 0.7493        | 0.7493      | 0.0      |
```

(عددهای شما ممکن است در رقم‌های آخر فرق کنند.) ستون `origin/main` عدد شاخه‌ی اصلی و ستون `workspace` عدد همین PR است. تصمیم Merge حالا با عدد است: `f1` کمی بدتر شد، `roc_auc` تغییری نکرد.

یک بار دیگر روی همین شاخه تغییر بدهید تا ببینید کامنت تکرار نمی‌شود، **به‌روز می‌شود**:

```bash
sed -i.bak 's/^  C: 0.5$/  C: 0.2/' params.yaml && rm params.yaml.bak && git commit -am "feat: try C=0.2" && git push
```

بعد از اجرای تازه‌ی `ml-ci`، همان کامنت (نه یک کامنت جدید) عدد `C=0.2` را نشان می‌دهد. این کار را اسکریپت `scripts/pr_comment.py` با یک نشانه‌ی پنهان `<!-- metrics-diff -->` در متن کامنت انجام می‌دهد.

این PR را **Merge نکنید** و ببندید (Close)؛ فقط برای دیدن metrics-diff بود. بعد:

```bash
git switch main
```

### <bdi dir="rtl">retrain زمان‌بندی‌شده</bdi>

فایل `.gitea/workflows/retrain.yaml` را بخوانید. بخش `on:` دو راه شروع دارد: `schedule` با `cron: "0 3 * * 1"` (هر دوشنبه ساعت ۳ بامداد به وقت UTC سرور) و `workflow_dispatch` (دکمه). در کلاس منتظر دوشنبه نمی‌مانیم؛ با دکمه اجرا می‌کنیم. در Gitea مخزن را باز کنید: **Actions**، از فهرست سمت چپ **retrain**، دکمه‌ی **Run Workflow**، شاخه‌ی `main`، **Run Workflow**.

نکته: Gitea اجرای دستی workflow را فقط وقتی می‌پذیرد که فایل روی شاخه‌ی پیش‌فرض (`main`) باشد. ما آن را در گام ۱ Merge کردیم.

بعد از حدود یک دقیقه (کمتر از یک دقیقه وقتی کتابخانه‌ها از قبل دانلود شده‌اند) اجرا سبز می‌شود. نتیجه روی سرور اصلی MLflow است:

```bash
make models
```

انتظار: یک **نسخه‌ی تازه** (مثلاً ۳) با alias `@challenger`، و `@champion` سر جای خودش:

```text
version run           C roc_auc     f1 gate    aliases
      1 1d127c83    0.1  0.7493  0.701 passed
      2 f0ed36f4   0.01  0.7489 0.7033 passed  @champion
      3 73a1aa0d    0.1  0.7493  0.701 -       @challenger
```

(شناسه‌ها و عددهای شما فرق می‌کنند.) دو نکته. اول، داده و پارامتر همان است، پس retrain همان metricها را می‌دهد: این یعنی پایپ‌لاین **بازتولیدپذیر** است (جلسه‌ی ۵). دوم، workflow عمداً `make promote` را اجرا نمی‌کند: ماشین مدل را آماده می‌کند، ولی تصمیم ارتقا به `@champion` با دروازه‌ی جلسه‌ی ۷ و یک آدم است.

---

## گام ۳ — مانیتورینگ با Prometheus و Grafana (۲۰ دقیقه)

<bdi dir="rtl">API ما از جلسه‌ی ۸ یک آدرس `/metrics` دارد (کتابخانه‌ی `prometheus-fastapi-instrumentator` و دو متریک خودمان). تا حالا کسی آن را نمی‌خواند. حالا Prometheus می‌خواند.</bdi>

نیازی به تغییر کد API نیست. اول نگاه کنید داخل `/metrics` چیست. API مانیتورینگ را روشن می‌کنیم (کنار Prometheus و Grafana):

```bash
make mon-up
```

انتظار: چند خط `Container ... Started` برای `churn-api-mon`، `prometheus` و `grafana`. اگر دفعه‌ی اول Prometheus و Grafana را از اینترنت می‌گیرد، چند دقیقه طول می‌کشد (حدود ۱٫۸ گیگابایت؛ مدرس معمولاً از قبل لود کرده است).

```bash
make mon-status
```

انتظار (بعد از حدود ۱۲ ثانیه):

```text
NAME                              IMAGE                     ...   STATUS                    PORTS
mlops-monitoring-churn-api-mon-1  churn-api:0.7.0           ...   Up 20 seconds (healthy)   127.0.0.1:8003->8000/tcp
mlops-monitoring-grafana-1        grafana/grafana:13.0.12   ...   Up 20 seconds             127.0.0.1:3001->3000/tcp
mlops-monitoring-prometheus-1     prom/prometheus:v3.13.4   ...   Up 21 seconds             127.0.0.1:9090->9090/tcp
churn-api up
prometheus up
```

دو خط آخر یعنی Prometheus دو هدف (target) دارد و هر دو `up` هستند.

```bash
curl -s http://localhost:8003/ready
```

انتظار: `{"status":"ready","model_version":"2"}` (نسخه‌ی `@champion` شما).

نگاهی به متریک‌های خام (فقط خطی که درباره‌ی `/predict` است):

```bash
curl -s http://localhost:8003/metrics | grep '^http_requests_total'
```

انتظار: چند سطر مثل `http_requests_total{handler="/health",method="GET",status="2xx"} 1.0`. هر درخواست یکی به این **شمارنده (counter)** اضافه می‌کند. شمارنده فقط بالا می‌رود؛ Prometheus با `rate()` سرعت بالا رفتن را حساب می‌کند.

### ترافیک بسازید

داشبورد بدون ترافیک خالی است. ترمینال دوم را باز کنید و ۱۰ درصد درخواست غلط (که جواب `422` می‌گیرد) به‌همراه درخواست‌های درست بفرستید:

```bash
cd ~/work/churn-mlops && make load RPS=5 DURATION=120 BAD=0.1
```

انتظار در پایان (۱۲۰ ثانیه بعد): یک خط status codes با حدود ۶۰۰ درخواست که بیشترشان ۲۰۰ هستند

در ترمینال اول ادامه دهید. Prometheus را باز کنید: `http://localhost:9090`. در کادر Expression بنویسید و **Execute** بزنید:

```text
sum(rate(http_requests_total{handler!="/metrics"}[1m]))
```

انتظار: یک عدد حدود `5` (درخواست در ثانیه). تب **Graph** نمودارش را می‌کشد.

### داشبورد Grafana

<bdi dir="rtl">Grafana را باز کنید: `http://localhost:3001`. نام کاربری `admin` و رمز `mlops-lab` (فقط برای آزمایشگاه). از منوی چپ **Dashboards** و بعد **Churn API: RED metrics**. این داشبورد را شما با دست نساختید: فایل `monitoring/grafana/dashboards/churn-api.json` را Grafana هنگام شروع خوانده است (فایل‌های `provisioning/` به Grafana می‌گویند کدام data source و کدام پوشه).</bdi>

چهار عدد بالا را بخوانید:

| پنل | معنی |
| --- | --- |
| Requests per second (R) | حدود `5` req/s در حالت عادی |
| 5xx error ratio (E) | `0%`: هیچ خطای سمت سرور نداریم |
| Latency p95 (D) | چند میلی‌ثانیه (در لپ‌تاپ ما حدود ۱۴ms): ۹۵٪ درخواست‌ها از این سریع‌ترند |
| API up | `1` |

نمودار «Errors: share of 4xx and 5xx» خط ۴xx را حدود `10%` نشان می‌دهد (همان درخواست‌های غلط ما). این خطا **تقصیر فراخوان** است، نه سرویس. فرق ۴xx و ۵xx را همیشه جدا نگه دارید: برای alert معمولاً ۵xx مهم است.

### خراب کردن سرویس و دیدن خطا روی داشبورد

```bash
make api-break
```

این دستور API را با مدلی که وجود ندارد (`models:/churn/99`) دوباره بالا می‌آورد. سرویس زنده است ولی مدل ندارد:

```bash
curl -s -i http://localhost:8003/ready | head -1
```

انتظار: `HTTP/1.1 503 Service Unavailable`

```bash
make load RPS=5 DURATION=40
```

انتظار: `status codes: {503: 200}` (همه‌ی درخواست‌های درست ۵۰۳ گرفتند؛ ممکن است یک یا دو `0` هم ببینید، یعنی لحظه‌ای که API هنوز بالا نیامده بود). در داشبورد، عدد **5xx error ratio** تا `100%` بالا می‌رود و قرمز می‌شود. این همان چیزی است که در محیط واقعی مدیر شما را بیدار می‌کند.

```bash
make api-fix
```

بعد از چند ثانیه سرویس برگشته است (`curl http://localhost:8003/ready` دوباره `ready`). ترافیک سالم دوباره بفرستید تا نمودار برگردد: `make load DURATION=30`.

> **حافظه:** اندازه‌گیری ما با `docker stats` بعد از چند دقیقه کار: Prometheus حدود ۵۵ تا ۱۳۰ مگابایت، Grafana حدود ۱۸۰ تا ۵۲۰ مگابایت، API حدود ۱۳۵ تا ۱۸۰ مگابایت، runner حدود ۲۰ مگابایت. جمع تقریباً ۰٫۴ تا ۰٫۸ گیگابایت (بدون job‌های CI که هر کدام موقتاً ۱۰۰ تا ۵۰۰ مگابایت می‌گیرند).

---

## گام ۴ — گزارش drift با Evidently (۱۰ دقیقه)

مدل با داده‌ی نسخه‌ی ۱ آموزش دید. داده‌ی نسخه‌ی ۲ (جلسه‌ی ۴) مشتری‌های جدیدتر، گران‌تر و کم‌وفاتر دارد. سؤال: «آیا داده‌ی تازه آن‌قدر فرق دارد که مدل را نباید باور کنیم؟» Evidently ستون‌به‌ستون مقایسه می‌کند.

ابتدا یک شاخه‌ی تازه بسازید (تغییر مستقیم روی `main` نکنید):

```bash
git switch -c feature/drift
```

کتابخانه جزو کتابخانه‌های **اصلی** پروژه نیست (حدود ۲۳۰ مگابایت در `.venv` اضافه می‌کند و در image سرویس نباید باشد)؛ پس در یک گروه جدا به نام `drift` نصب می‌شود:

```bash
uv add --group drift "evidently==0.7.23"
```

انتظار: چند ده خط `+ نام==نسخه` و در آخر `Installed ... packages`. دو فایل `pyproject.toml` و `uv.lock` عوض شده‌اند (اولی ۳ خط، دومی حدود هزار خط).

گزارش HTML حدود ۴ مگابایت است و جایش در Git نیست:

```bash
echo "reports/" >> .gitignore
```

```bash
make drift
```

انتظار (بار اول چند ثانیه بیشتر طول می‌کشد؛ ما ۹ ثانیه دیدیم):

```text
reference data-v1: 5000 rows   current data-v2: 8000 rows
column             method                             score  drift
tenure_months      Wasserstein distance (normed)     0.5846  YES
monthly_charges    Wasserstein distance (normed)     0.7171  YES
contract           Jensen-Shannon distance           0.0031  no
internet_service   Jensen-Shannon distance           0.0101  no
payment_method     Jensen-Shannon distance           0.0071  no
support_calls      Jensen-Shannon distance           0.0147  no
churn              Jensen-Shannon distance           0.1163  YES
3 of 7 columns drifted
report: reports/drift-v1-v2.html  (open it in a browser)
```

اسکریپت داده‌ی هر دو tag را با `dvc get` از SeaweedFS می‌گیرد (پس MLflow لازم نیست ولی SeaweedFS باید روشن باشد). گزارش را باز کنید:

```bash
open reports/drift-v1-v2.html
```

(در Linux و WSL: `xdg-open reports/drift-v1-v2.html` یا فایل را در مرورگر ویندوز با Explorer باز کنید.)

در گزارش، بالای صفحه «Drift is detected for 42.86% of columns (3 out of 7)» را می‌بینید و برای هر ستون دو نمودار توزیع (مرجع و فعلی). چیزهایی که باید بتوانید توضیح دهید:

- <bdi dir="rtl">`tenure_months` و `monthly_charges` **drift** دارند: مشتری‌های نسخه‌ی ۲ کم‌سابقه‌تر و گران‌ترند. این همان تغییری است که با `--drift` در جلسه‌ی ۱ ساختیم.</bdi>
- ستون `churn` (برچسب) هم کمی فرق کرده: نرخ ریزش بالا رفته.
- ستون‌های دسته‌ای (`contract`، `payment_method`...) تقریباً ثابت‌اند.
- ۳ ستون از ۷ تا drift دارند و این کمتر از **۵۰٪** است؛ پس Evidently برای کل داده نتیجه‌ی «dataset drift» را **نه** می‌گوید. آستانه‌ی ۵۰٪ پیش‌فرض است؛ در عمل خودتان آن را برای پروژه تعیین می‌کنید.
- <bdi dir="rtl">drift یعنی «داده فرق کرده»، نه «مدل بد شده». برای بد شدن مدل باید برچسب واقعی برسد (ماه‌ها بعد). drift هشدار زودهنگام است.</bdi>

---

## گام ۵ — یک alert، commit و tag (۱۰ دقیقه)

فایل `monitoring/prometheus/alerts.yml` یک rule نمونه دارد: `ChurnApiDown` اگر Prometheus ۱۵ ثانیه نتواند API را بخواند، روشن می‌شود. ببینید آیا Prometheus آن را خوانده:

```bash
curl -s http://localhost:9090/api/v1/rules | grep -o '"name":"ChurnApiDown"'
```

انتظار: `"name":"ChurnApiDown"`

صفحه‌ی `http://localhost:9090/alerts` را باز کنید: ChurnApiDown با رنگ سبز (`Inactive`). حالا API را قطع کنید:

```bash
docker stop mlops-monitoring-churn-api-mon-1
```

صفحه‌ی alerts را هر چند ثانیه تازه کنید. ما این‌ها را دیدیم: بعد از حدود ۱۲ ثانیه `Pending` (زرد)، بعد از حدود ۲۴ ثانیه `Firing` (قرمز). تأخیر به خاطر `for: 15s` در rule و `scrape_interval: 5s` است: Prometheus می‌خواهد مطمئن شود خرابی گذراست یا نه. در محیط واقعی Alertmanager در این لحظه ایمیل یا پیام می‌فرستد؛ ما فقط وضعیت را می‌بینیم.

```bash
docker start mlops-monitoring-churn-api-mon-1
```

بعد از ۱۵ ثانیه alert دوباره سبز است. نوشتن یک rule دوم (نرخ خطا) **تکلیف** است.

### <bdi dir="rtl">commit و tag</bdi>

وضعیت Git:

```bash
git status --short
```

انتظار: `M .gitignore`، `M pyproject.toml`، `M uv.lock`. (فایل‌های `.gitea`، `monitoring` و غیره در گام ۱ commit شده‌اند.) اگر چیز دیگری ماند، اول ببینید چیست.

```bash
git add -A && git commit -m "feat: drift report with Evidently (dependency group drift)"
```

```bash
git push -u origin feature/drift
```

یک Pull Request بسازید. کامنت `ml-ci` ظاهر نمی‌شود (فایل‌های ML عوض نشده‌اند) ولی `ci` اجرا می‌شود؛ سبز شدن را ببینید، Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.11.0 -m "Session 13: CI, monitoring and drift"
```

```bash
git push origin v0.11.0
```

---

## بررسی پایان کار

<bdi dir="rtl">Prometheus و Grafana روشن باشند (`make mon-up`)، و ترافیک و یک خطا را قبلاً دیده باشند (گام ۳). بعد:</bdi>

```bash
~/mlops-lab/scripts/verify.sh s13
```

این بررسی از API گیتی می‌خواند و **نام کاربری و رمز Gitea** شما را در ترمینال می‌پرسد (رمز نمایش داده و ذخیره نمی‌شود). انتظار: همه‌ی خط‌ها `[PASS]` باشند (۱۶ بررسی). اگر خطی `[FAIL]` شد، متن زیر آن می‌گوید چه چیزی کم است؛ جدول عیب‌یابی را ببینید. خروجی را همراه با تکلیف برای مدرس بفرستید.

## معیار پایان کار

- [ ] شاخه‌ی `feature/ci-monitoring` ساخته شد و با Pull Request وارد `main` شد
- [ ] runner در Gitea با وضعیت `Idle` است و می‌دانید چرا job داخل یک container تازه اجرا می‌شود
- [ ] اجرای `ci` روی `main` سبز است و `curl http://localhost:5001/v2/churn-api/tags/list` یک tag به نام `ci-...` دارد
- [ ] می‌توانید بگویید چرا `uses: actions/checkout` را در workflow‌ها نگذاشتیم
- [ ] روی یک PR که `params.yaml` را عوض کرد، کامنت metrics-diff را دیدید و فهمیدید push دوم کامنت را به‌روز می‌کند
- [ ] workflow `retrain` را با دکمه اجرا کردید و `make models` یک `@challenger` تازه نشان داد
- [ ] می‌دانید چرا retrain خودش `@champion` را عوض نمی‌کند
- [ ] `make mon-status` هر دو target را `up` نشان داد و داشبورد «Churn API: RED metrics» را در Grafana دیدید
- [ ] با `make api-break` خطای ۵xx را روی داشبورد دیدید و با `make api-fix` برگرداندید
- [ ] فرق ۴xx و ۵xx و معنی R و E و D را می‌توانید با یک جمله بگویید
- [ ] `ChurnApiDown` را با قطع API به `Firing` رساندید
- [ ] `reports/drift-v1-v2.html` ساخته شد و می‌توانید بگویید کدام ستون‌ها drift دارند و چرا «dataset drift» نشد
- [ ] `~/mlops-lab/scripts/verify.sh s13` همه‌ی بررسی‌ها را `PASS` داد
- [ ] tag `v0.11.0` روی `main` است و push شده

## عیب‌یابی

اصل کلی: برای CI **اول لاگ همان مرحله** در Gitea (Actions، اجرا، مرحله‌ی قرمز). برای مانیتورینگ: `make mon-status` و `docker logs NAME`.

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| اجرا در Gitea همیشه `Waiting` یا `Queued` می‌ماند | runner روشن نیست یا ثبت‌نام نشده | `docker ps --filter name=gitea-runner`. نبود: `make runner-up`. لاگ: `docker logs --tail 20 gitea-runner`. در Gitea (Site Administration، Actions، Runners) باید `Idle` باشد |
| لاگ runner: `Cannot ping the Gitea instance server` یا `Failed to register` | توکن خالی یا قدیمی است | دوباره توکن بسازید (گام ۱) و `make runner-up`؛ اگر لازم شد یک بار `docker compose --profile ci up -d --force-recreate gitea-runner` در `~/mlops-lab/compose` |
| job بلافاصله خطای `failed to create container` یا `Duplicate mount point: /var/run/docker.sock` | `config.yaml` قدیمی runner دارد خودش socket را دوباره سوار می‌کند | `git -C ~/mlops-lab pull` (فایل اصلاح شده است)، بعد `docker compose --profile ci up -d --force-recreate gitea-runner` |
| job: `Error response from daemon: No such image: mlops/ci-job:1.0` یا `pull access denied` | image job روی لپ‌تاپ نیست و در اینترنت هم نیست | `docker image ls mlops/ci-job`. از بسته‌ی آفلاین نصب کنید (`install-from-bundle.sh`) یا از مدرس بپرسید |
| مرحله‌ی checkout: `Unable to clone http://localhost:3000/actions/checkout ... connection refused` | در workflow `uses: actions/checkout@v4` نوشته‌اید | آن را پاک کنید و چهار خط `git init`، `remote add`، `fetch`، `checkout` از `ci.yaml` را بگذارید. `uses:` از اینترنت (یا از یک مخزن `actions/checkout` داخل Gitea که نداریم) دانلود می‌کند |
| checkout: `fatal: unable to access 'http://localhost:3000/...'` | آدرس مخزن را با `localhost` نوشته‌اید. داخل container job، `localhost` خود job است | آدرس داخلی `http://gitea:3000` را بگذارید (مثل `ci.yaml`) |
| مرحله‌ی `install dependencies`: `Failed to fetch` یا `error sending request for url (https://pypi.org/...)` | job به PyPI نمی‌رسد | اینترنت یا mirror مدرس. با mirror: `UV_DEFAULT_INDEX` را در بخش `env:` workflow بگذارید |
| مرحله‌ی `lint` قرمز: `Would reformat` یا `E501` | کدی که push کردید روی لپ‌تاپ هم lint را رد می‌کند | روی لپ‌تاپ `make lint`، بعد `uv run ruff format .` و دوباره commit |
| مرحله‌ی `test` قرمز ولی روی لپ‌تاپ سبز است | فایلی که تست لازم دارد در Git نیست (مثلاً `.gitignore` شده) | `git status --ignored` و `git ls-files`؛ CI فقط چیزی را می‌بیند که commit شده |
| مرحله‌ی `build image`: `failed to resolve source metadata for docker.io/docker/dockerfile:1` | خط اول `Dockerfile` (`# syntax=docker/dockerfile:1`) هر بار از Docker Hub پرسش می‌کند؛ بدون اینترنت یا با اینترنت قطع‌ووصل، build می‌شکند | خط اول Dockerfile را پاک کنید (ما از ویژگی خاص آن استفاده نمی‌کنیم) و commit کنید |
| مرحله‌ی `build image`: `Cannot connect to the Docker daemon` | socket به job نرسیده | `docker compose --profile ci up -d --force-recreate gitea-runner`. در Docker Desktop باید `/var/run/docker.sock` وجود داشته باشد |
| مرحله‌ی `scan image` قرمز با جدول `CRITICAL` یا `HIGH` | Trivy آسیب‌پذیری‌ای با راه‌حل پیدا کرده و کتابخانه‌ی قدیمی مانده است | جدول را بخوانید: ستون‌های `Library` و `Fixed Version` را ببینید و کتابخانه را ارتقا دهید: `uv lock --upgrade-package NAME` و سپس commit. مرحله‌ی scan را حذف نکنید |
| مرحله‌ی `push image`: `connection refused` به `localhost:5001` | registry محلی خاموش است | `docker ps --filter name=kind-registry`؛ خاموش: `docker start kind-registry` (یا `make k8s-up`) |
| `push image` اصلاً اجرا نشد | روی PR نیست؛ فقط روی `main` اجرا می‌شود (`if:`) | طبیعی است. بعد از Merge اجرای روی `main` را ببینید |
| `ml-ci`: `dvc pull` خطای `Unable to locate credentials` یا `403` | secret‌ها نیستند یا نامشان غلط است | در Settings، Actions، Secrets دقیقاً `AWS_ACCESS_KEY_ID` و `AWS_SECRET_ACCESS_KEY`. بعد workflow را دوباره اجرا کنید (re-run) |
| `ml-ci`: `dvc pull` به `localhost:8333` وصل نمی‌شود | مرحله‌ی `point DVC at the S3 server` پاک شده | آدرس داخل شبکه‌ی Docker `http://seaweedfs:8333` است، نه `localhost` |
| `ml-ci`: `unknown Git revision origin/main` | `fetch` شاخه‌ی `main` نشده | همان خط `git fetch ... origin main:refs/remotes/origin/main` را برگردانید |
| `ml-ci` سبز است ولی کامنتی روی PR نیست | کامنت‌گذاری شکست خورده، یا PR از fork است | لاگ مرحله‌ی `comment on the pull request`: `HTTP Error 403` یعنی توکن اجازه ندارد (در این آزمایشگاه PR از همین مخزن است و باید کار کند) |
| `ml-ci` اصلاً اجرا نشد | تغییرات PR با `paths:` نمی‌خواند (مثلاً فقط README عوض شده) | طبیعی است. `params.yaml` یا یک فایل `src/` را عوض کنید |
| retrain: دکمه‌ی `Run Workflow` را نمی‌بینید | فایل روی شاخه‌ی پیش‌فرض مخزن نیست (PR گام ۱ هنوز Merge نشده)، یا شاخه‌ی پیش‌فرض مخزن `main` نیست | PR گام ۱ را Merge کنید. در Gitea: Settings، Branches، Default Branch باید `main` باشد |
| retrain: `MLflow server not reachable at http://mlflow:5000` | MLflow خاموش است | `cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow` و دوباره اجرا |
| `make mon-up`: `network mlops-lab declared as external, but could not be found` | شبکه‌ی آزمایشگاه نیست (سرویس‌های compose هرگز بالا نیامده‌اند) | `cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow` |
| `make mon-up`: `port is already allocated` برای ۹۰۹۰ یا ۳۰۰۱ یا ۸۰۰۳ | برنامه‌ی دیگری آن پورت را دارد (preflight هشدار می‌دهد) | `docker ps --filter publish=9090`. موقتاً پورت را عوض کنید: `PROMETHEUS_PORT=9091 make mon-up` (و `GRAFANA_PORT`، `API_PORT`) |
| Prometheus: target `churn-api` برابر `down` است | API بالا نیامده یا مدل را بار نکرده و دوباره راه‌اندازی می‌شود | `docker logs mlops-monitoring-churn-api-mon-1`. اگر `MLflow` را نمی‌یابد: `docker compose up -d mlflow` در `~/mlops-lab/compose` |
| `curl http://localhost:8003/ready` برابر `503` | `@champion` نیست یا MLflow خاموش بود | `make models` و اگر لازم است `make promote`، بعد `make api-fix` |
| داشبورد Grafana خالی است یا `No data` | ترافیک نیست، یا بازه‌ی زمانی بزرگ است | `make load DURATION=60`؛ بالا سمت راست بازه را `Last 5 minutes` کنید. زیر هر پنل سرخ‌پوش `Query error` یعنی data source؛ `http://localhost:9090/targets` را ببینید |
| Grafana: `Datasource prometheus-lab was not found` | پوشه‌ی `monitoring/grafana/provisioning` نیست یا نادرست mount شده | دستور `docker compose -f monitoring/docker-compose.yml up -d --force-recreate grafana` را در پوشه‌ی پروژه بزنید و فایل `datasources/prometheus.yml` را ببینید |
| بعد از تغییر `alerts.yml` چیزی عوض نشد | Prometheus فایل را فقط موقع شروع یا reload می‌خواند | `curl -X POST http://localhost:9090/-/reload` و بعد `http://localhost:9090/rules` |
| `make load`: `No such file ... scripts/loadgen.py` | فایل‌های جلسه کپی نشده‌اند | `cp $S/scripts/*.py scripts/` (و `S=~/mlops-lab/s13`) |
| `make drift`: `Failed to spawn: dvc` یا `No module named 'evidently'` | گروه `drift` نصب نیست | `uv add --group drift "evidently==0.7.23"`؛ اجرا حتماً با `make drift` (یا `uv run --group drift ...`) |
| `make drift`: `dvc get` خطای `No storage files available` یا `Unable to locate credentials` | داده‌ی یکی از tagها در SeaweedFS نیست، یا کلیدهای S3 در `.dvc/config.local` نیستند | `uv run dvc status -c` و `git tag` (باید `data-v1` و `data-v2` را ببینید). جلسه‌ی ۴، گام ۳ و ۵ |
| `make drift` پیام‌های `SyntaxWarning: invalid escape sequence` | هشدار بی‌ضرر کتابخانه (فقط بار اول که فایل‌ها compile می‌شوند) | نادیده بگیرید؛ اسکریپت ما آن‌ها را خاموش می‌کند و فقط اگر قبل از import چاپ شد دیده می‌شود |
| `verify.sh s13` در بررسی‌های CI و ml-ci و retrain `FAIL` می‌دهد، ولی در Gitea سبز است | verify بدون رمز نمی‌تواند API گیتی را بخواند (بدون terminal یا با Enter خالی) | در یک ترمینال معمولی اجرا کنید و رمز را بدهید، یا `GITEA_USER=student GITEA_PASSWORD='...' ~/mlops-lab/scripts/verify.sh s13` (رمز را در تاریخچه‌ی ترمینال نگذارید؛ ترجیحاً با prompt) |
| `verify.sh s13`: ۵xx دیده نشده یا ترافیک کم است | داشبورد را دیده‌اید ولی `make api-break` و `make load` را نزده‌اید | گام ۳ را از «خراب کردن سرویس» تکرار کنید |
| Windows: دستورها خطای عجیب می‌دهند | از PowerShell استفاده می‌کنید | همه‌ی دستورها را داخل WSL Ubuntu بزنید |
| tag `v0.11.0` روی commit قدیمی است | tag را پیش از `git switch main && git pull` ساخته‌اید | `git tag -d v0.11.0 && git push origin :refs/tags/v0.11.0`، بعد روی `main` به‌روز دوباره tag و push |

**نگه‌دارید:** سرویس‌های آزمایشگاه، registry و runner را تا جلسه‌ی ۱۴ پاک نکنید (`docker compose down -v` ممنوع). جلسه‌ی ۱۴ اجرای سرتاسری از یک clone تمیز است و همین پروژه را می‌خواهد. وقتی کارتان تمام شد، مانیتورینگ را می‌توانید برای صرفه‌جویی در حافظه خاموش کنید:

```bash
make mon-down
```

تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

</div>
