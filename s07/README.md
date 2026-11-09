<div dir="rtl">

# آزمایشگاه جلسه‌ی ۷ — Model Registry و Promotion با دروازه‌ی ارزیابی

در این آزمایشگاه مدل‌هایی را که در جلسه‌ی ۶ با MLflow ثبت کردید در **Model Registry** با نام `churn` نسخه‌دار می‌کنید، به نسخه‌ها alias می‌دهید (`@challenger` و `@champion`) و با یک **دروازه‌ی ارزیابی** (evaluation gate) فقط مدلی را champion می‌کنید که از آستانه‌ی متریک‌ها رد شود. در پایان مدل champion را با نشانی `models:/churn@champion` از روی لپ‌تاپ بار می‌کنید؛ جلسه‌ی ۸ سرویس FastAPI همین نشانی را بار می‌کند.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۶ سالم باشد: `main` شامل tag `v0.4.0` است و سرور MLflow چهار run در experiment `churn` دارد (`docker compose down -v` نزده باشید).
2. مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s07
```

3. سرویس‌ها را روشن کنید:

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow
```

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK`

همه‌ی دستورهای بعد در پوشه‌ی `~/work/churn-mlops` اجرا می‌شوند، مگر جایی که گفته شده. اگر ترمینال را بستید، خط `K=...` و دستور `source` گام ۱ را دوباره بزنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell.

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| registered model | یک «نام» برای مدل در Registry؛ ما یکی داریم: `churn` |
| version | هر بار که مدلی را ثبت می‌کنید یک نسخه‌ی تازه (۱، ۲، ۳، …) ساخته می‌شود؛ نسخه‌ها هرگز عوض نمی‌شوند |
| alias | برچسب متحرک که به **یک** نسخه اشاره می‌کند، مثل `@champion`؛ جابه‌جا کردن alias یعنی انتشار |
| `@challenger` | نسخه‌ی تازه‌ای که می‌خواهد جای champion را بگیرد |
| `@champion` | نسخه‌ای که سرویس‌ها از آن استفاده می‌کنند |
| tag | برچسب کلید/مقدار روی نسخه (مثل `roc_auc` یا `gate=passed`) |
| description | یادداشت انتشار (release note) نسخه |
| signature | قرارداد ورودی و خروجی مدل (نام و نوع ستون‌ها) که در جلسه‌ی ۶ با مدل ثبت شد |
| Stage | روش قدیمی (Staging/Production)؛ در MLflow 3 «deprecated» است و از آن استفاده نمی‌کنیم |

دروازه‌ی ارزیابی این جلسه (در `params.yaml`):

| قانون | مقدار | معنی |
| --- | --- | --- |
| `min_roc_auc` | 0.745 | کیفیت رتبه‌بندی مدل نباید از این کمتر باشد |
| `min_f1` | 0.69 | f1 با آستانه‌ی 0.5 نباید از این کمتر باشد |
| `max_roc_auc_drop` | 0.001 | challenger حداکثر به این اندازه می‌تواند از roc_auc مدل champion فعلی بدتر باشد |

## نتیجه‌ی نهایی

- مدل `churn` در Registry با دست‌کم سه نسخه
- یک نسخه که دروازه آن را رد کرده (`gate=failed`) و یک نسخه با `@champion` که از دروازه گذشته
- بار شدن `models:/churn@champion` از روی لپ‌تاپ با `make predict`
- کد در Git با tag نسخه‌ی `v0.5.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `churn/registry.py` | `src/churn/` | ثبت مدل، alias، دروازه‌ی ارزیابی و promotion |
| `scripts/predict_champion.py` | `scripts/` | بار کردن `models:/churn@champion` و پیش‌بینی پنج ردیف |
| `scripts/shap_plot.py` | `scripts/` | اختیاری: نمودار SHAP مدل champion به‌عنوان artifact |
| `tests/test_registry.py` | `tests/` | چهار آزمون (دروازه و ثبت، بدون نیاز به سرور) |
| `Makefile` | ریشه‌ی پروژه | هدف‌های تازه‌ی `register`، `promote`، `models` و `predict` |

توضیح خط‌به‌خط کد این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — وضعیت شروع و signature مدل (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git switch -c feature/model-registry
```

یک خط به فایل `.env` اضافه کنید تا نوار پیشرفت دانلود artifactها چاپ نشود:

```bash
echo 'MLFLOW_ENABLE_ARTIFACTS_PROGRESS_BAR=false' >> .env
```

```bash
set -a; source .env; set +a
```

بررسی کنید متغیر مهم جلسه‌ی ۶ هم هست:

```bash
grep MLFLOW .env
```

انتظار (چهار خط):

```
MLFLOW_TRACKING_URI=http://localhost:5050
MLFLOW_DISABLE_AGENT_HINT=1
MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false
MLFLOW_ENABLE_ARTIFACTS_PROGRESS_BAR=false
```

<bdi dir="rtl">run‌های جلسه‌ی ۶ را ببینید:</bdi>

```bash
make runs
```

انتظار (شناسه‌ها در سیستم شما فرق دارند، عددها نه):

```
  run_id           name    C threshold  roc_auc     f1
e023cc9d   C=10 thr=0.5   10       0.5   0.7493 0.6987
3911915c    C=1 thr=0.5    1       0.5   0.7493 0.6991
2b4a0209 C=0.01 thr=0.5 0.01       0.5   0.7489 0.7033
cdd10d5f  C=0.1 thr=0.5  0.1       0.5   0.7493 0.7010
```

شناسه‌ی هشت‌حرفی run‌های `C=0.1` و `C=0.01` را یادداشت کنید؛ در گام‌های بعد لازم‌اند.

در مرورگر `http://localhost:5050` را باز کنید، **Model training** را بزنید، experiment `churn` و بعد run `C=0.1 thr=0.5` را باز کنید. در بخش **Logged models** روی `model` کلیک کنید، تب **Artifacts** را بزنید و فایل `MLmodel` را باز کنید. بخش `signature` آن شش ستون ورودی با نوع (`double`، `string`، `long`) و یک خروجی دارد. این همان signature است که جلسه‌ی ۸ با آن قرارداد API را می‌سازد؛ بعد از ثبت در گام ۲ همین را به‌صورت جدول در بخش **Schema** صفحه‌ی نسخه می‌بینید.

## گام ۲ — اولین ثبت در Registry (۱۵ دقیقه)

فایل‌های آماده را کپی کنید:

```bash
cp $K/churn/registry.py src/churn/ && cp $K/scripts/*.py scripts/ && cp $K/tests/test_registry.py tests/ && cp $K/Makefile .
```

> اگر به `Makefile` خودتان هدف دیگری اضافه کرده‌اید، فقط چهار هدف تازه را از فایل جدید به آن اضافه کنید.

قانون‌های دروازه را به انتهای `params.yaml` اضافه کنید:

```bash
cat >> params.yaml <<'EOF'
gate:
  min_roc_auc: 0.745
  min_f1: 0.69
  max_roc_auc_drop: 0.001
EOF
```

هیچ مرحله‌ای از پایپ‌لاین به بخش `gate` وابسته نیست:

```bash
uv run dvc status
```

انتظار: `Data and pipelines are up to date.`

کیفیت کد و آزمون‌ها:

```bash
uv run ruff check . && uv run ruff format --check .
```

```bash
uv run pytest -q
```

انتظار: `10 passed` (بین ۲۵ تا ۴۵ ثانیه). همین حالا commit کنید؛ **پیش از هر `dvc exp run`** باید `params.yaml` در Git باشد، وگرنه `git restore params.yaml` در گام ۳ بخش `gate` را پاک می‌کند:

```bash
git add src scripts tests params.yaml Makefile && git commit -m "feat: model registry with evaluation gate"
```

حالا مدل run `C=0.1` (همان مدل شاخه‌ی `main`) را ثبت کنید. شناسه‌ی خودتان را جای `cdd10d5f` بگذارید:

```bash
make models
```

انتظار: `no versions of 'churn' yet`

```bash
make register RUN=cdd10d5f
```

انتظار (آخر خروجی):

```
Successfully registered model 'churn'.
Created version '1' of model 'churn'.
registered churn version 1 from run cdd10d5f -> @challenger
version run           C roc_auc     f1 gate    aliases
      1 cdd10d5f    0.1  0.7493  0.701 -       @challenger
```

خط `Waiting up to 300 seconds for model version to finish creation` فقط پیام اطلاع‌رسانی است.

در UI به نشانی `http://localhost:5050/#/models` بروید (صفحه‌ی **Registered Models**). روی `churn` کلیک کنید: ستون **Aliases** برای نسخه‌ی ۱ نشان `@ challenger` دارد. روی **Version 1** کلیک کنید و **Description** (یادداشت انتشار خودکار)، **Tags** و **Schema** را ببینید. کنار نسخه نوشته شده **Stage (deprecated): None**؛ Stageها روش قدیمی‌اند.

> دکمه‌ی **Promote model** در صفحه‌ی نسخه کار دیگری می‌کند (نسخه را به یک registered model دیگر کپی می‌کند). آن را نزنید؛ promotion ما با alias است.

## گام ۳ — دروازه‌ی ارزیابی: یکی رد، یکی قبول (۲۰ دقیقه)

### ۳-۱. اولین champion

```bash
make promote
```

انتظار:

```
challenger: version 1 roc_auc=0.7493 f1=0.701
champion:   none yet
gate passed: @champion -> version 1
version run           C roc_auc     f1 gate    aliases
      1 cdd10d5f    0.1  0.7493  0.701 passed  @challenger,@champion
```

هنوز champion نبود، پس فقط دو قانون اول بررسی شد. یک نسخه می‌تواند هم‌زمان دو alias داشته باشد.

### ۳-۲. یک مدل ضعیف که ظاهرش خوب است

یک آزمایش با `C` خیلی کوچک بسازید:

```bash
uv run dvc exp run -S train.C=0.0001
```

انتظار در میانه‌ی خروجی: `{'roc_auc': 0.7358, 'f1': 0.718}` و خط `mlflow: run ... logged`. پوشه‌ی کار را به حالت commit‌شده برگردانید:

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

```bash
make runs
```

ردیف اول run تازه‌ی `C=0.0001` است. **f1 آن از همه بهتر است** (0.7180). شناسه‌اش را ثبت کنید:

```bash
make register RUN=<شناسه‌ی run C=0.0001>
```

انتظار: `registered churn version 2 ... -> @challenger`. حالا دروازه:

```bash
make promote
```

انتظار:

```
challenger: version 2 roc_auc=0.7358 f1=0.718
champion:   version 1 roc_auc=0.7493 f1=0.701
  FAIL roc_auc 0.7358 < min_roc_auc 0.745
  FAIL roc_auc 0.7358 < champion 0.7493 - max_roc_auc_drop 0.001
gate FAILED: @champion stays on version 1
make: *** [promote] Error 1
```

این خطا **درست** است: دروازه کار کرد. مدل `C=0.0001` تقریباً برای همه «churn» پیش‌بینی می‌کند؛ برای همین f1 بالا رفته ولی roc_auc (توان جدا کردن مشتری‌ها) پایین آمده. اگر دروازه فقط به f1 نگاه می‌کرد، این مدل منتشر می‌شد. کد خروج ۱ یعنی در CI جلسه‌ی ۱۳ هم همین‌جا متوقف می‌شود.

### ۳-۳. یک مدل خوب

<bdi dir="rtl">run `C=0.01` جلسه‌ی ۶ را ثبت کنید (شناسه‌ی خودتان):</bdi>

```bash
make register RUN=2b4a0209
```

```bash
make promote
```

انتظار:

```
challenger: version 3 roc_auc=0.7489 f1=0.7033
champion:   version 1 roc_auc=0.7493 f1=0.701
gate passed: @champion -> version 3
version run           C roc_auc     f1 gate    aliases
      1 cdd10d5f    0.1  0.7493  0.701 passed  
      2 32f91ed4 0.0001  0.7358  0.718 failed  
      3 2b4a0209   0.01  0.7489 0.7033 passed  @challenger,@champion
```

افت roc_auc فقط 0.0004 است (کمتر از 0.001) و f1 بهتر شده؛ پس `@champion` از نسخه‌ی ۱ برداشته شد و روی نسخه‌ی ۳ نشست. در UI صفحه‌ی `churn` را تازه کنید و ستون‌های Tags و Aliases را ببینید.

> برگشت (rollback) هم فقط جابه‌جایی alias است: در UI روی مداد کنار aliasها یا با کد `set_registered_model_alias("churn", "champion", 1)`. این جلسه آن را انجام ندهید.

## گام ۴ — بار کردن `models:/churn@champion` از لپ‌تاپ (۱۵ دقیقه)

```bash
make predict
```

انتظار:

```
loaded models:/churn@champion (version 3, run 2b4a0209) in 1.8 s
signature inputs: ['tenure_months', 'monthly_charges', 'contract', 'internet_service', 'payment_method', 'support_calls']
churn probability: [0.4511, 0.599, 0.615, 0.4741, 0.6896]
```

کد هیچ شماره‌ی نسخه‌ای ندارد؛ فقط alias را می‌شناسد. اگر فردا نسخه‌ی ۴ champion شود، همین دستور مدل تازه را بار می‌کند. سرویس جلسه‌ی ۸ دقیقاً همین کار را می‌کند.

اسکریپت پیش از بار کردن بررسی می‌کند که متغیر دانلود درست باشد. ببینید بدون آن چه می‌شود (فقط در همین ترمینال):

```bash
env -u MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD make predict
```

انتظار:

```
MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false is not set: load_model would hang.
Fix: set -a; source .env; set +a
make: *** [predict] Error 1
```

بدون این بررسی، `load_model` بی‌صدا آویزان می‌ماند (سرور نشانی `http://seaweedfs:8333/...` می‌دهد که فقط داخل شبکه‌ی Docker معنی دارد).

### اختیاری — نمودار SHAP (اگر وقت ماند)

<bdi dir="rtl">SHAP نشان می‌دهد هر ویژگی چقدر پیش‌بینی را بالا یا پایین می‌برد. بسته‌ی `shap` را به پروژه اضافه نمی‌کنیم؛ `uv` آن را فقط برای همین اجرا نصب می‌کند (اینترنت یا بسته‌ی آفلاین لازم است):</bdi>

```bash
uv run --with shap==0.54.1 python scripts/shap_plot.py
```

انتظار (بار اول تا یک دقیقه طول می‌کشد، بعد حدود ۸ ثانیه):

```
shap_summary.png logged to run 2b4a0209 (version 3, @champion)
```

فایل `shap_summary.png` را باز کنید و در UI در تب **Artifacts** همان run ببینید. مهم‌ترین ویژگی‌ها `monthly_charges` و `tenure_months` هستند. فایل را از Git بیرون نگه دارید:

```bash
echo 'shap_summary.png' >> .gitignore
```

## گام ۵ — commit، Pull Request و بررسی (۱۵ دقیقه)

```bash
git status --short
```

انتظار: خالی (یا فقط `.gitignore` اگر بخش اختیاری را انجام دادید؛ آن را commit کنید):

```bash
git add .gitignore && git commit -m "chore: ignore shap plot"
```

```bash
uv run dvc status
```

انتظار: `Data and pipelines are up to date.` (این جلسه چیزی برای `dvc push` نداریم.)

```bash
git push -u origin feature/model-registry
```

در Gitea Pull Request بسازید و در توضیح بنویسید:

```
Model registry for churn with an evaluation gate (params.yaml: gate).
v1 C=0.1 passed, v2 C=0.0001 blocked (roc_auc 0.7358), v3 C=0.01 passed -> @champion.
models:/churn@champion loads from the laptop (make predict).
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.5.0 -m "Session 7: model registry"
```

```bash
git push origin v0.5.0
```

---

## بررسی پایان کار

```bash
~/mlops-lab/scripts/verify.sh s07
```

انتظار:

```
[PASS] MLflow server answers at http://localhost:5050
[PASS] registered model 'churn' has at least 2 versions
       versions: 3
[PASS] alias @champion exists, passed the gate and has a release note
       @champion = version 3  roc_auc 0.7489  f1 0.7033
[PASS] the gate blocked at least one version (tag gate=failed)
[PASS] champion model files on the artifact store; .env has MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false
[PASS] registry.py, predict_champion.py, tests and params.yaml (gate) committed
[PASS] tag v0.5.0 exists locally and on Gitea
s07: 7/7 checks passed
```

خروجی را همراه با تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `expected 1 run starting with 'cdd10d5f', found 0` | شناسه‌ی run اشتباه است یا از سیستم دیگری کپی شده | `make runs` و شناسه‌ی هشت‌حرفی خودتان |
| `argument --run: expected one argument` | `make register` بدون `RUN=` زده شد | `make register RUN=<شناسه>` |
| `KeyError: 'gate'` در `make promote` | بخش `gate` در `params.yaml` نیست (معمولاً با `git restore params.yaml` پاک شده) | بخش را دوباره اضافه و commit کنید |
| `no @challenger yet` | هنوز مدلی ثبت نشده | اول `make register RUN=...` |
| `gate FAILED` و `make: *** [promote] Error 1` | challenger از دروازه رد شد | عادی است؛ champion عوض نمی‌شود. دلیل در خط‌های `FAIL` آمده |
| `version 1 is already @champion` | challenger همان champion است | نسخه‌ی تازه ثبت کنید |
| `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false is not set` | `.env` در این ترمینال بار نشده یا خط آن نیست | `set -a; source .env; set +a` |
| `load_model` در کد خودتان بی‌صدا آویزان می‌شود | همان متغیر بالا تنظیم نیست | همان راه‌حل؛ بررسی `check_download_setting()` را صدا بزنید |
| `MLflow server not reachable at http://localhost:5050` | سرور خاموش است | `cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow` |
| `make runs` فقط run‌های کمی نشان می‌دهد یا Registry خالی است | `docker compose down -v` زده شده و volume پاک شده | `uv run dvc repro --force --single-item evaluate` و چند `dvc exp run` (راهنمای جلسه‌ی ۶، گام ۴) |
| `dvc exp run -S train.C=0.0001` run تازه نساخت (`is cached - skipping run`) | همین آزمایش قبلاً اجرا شده | از run موجود در `make runs` استفاده کنید، یا `--force` |
| UI صفحه‌ی GenAI نشان می‌دهد | حالت پیش‌فرض MLflow 3.16 | روی **Model training** کلیک کنید، یا مستقیم `http://localhost:5050/#/models` |
| خط `Waiting up to 300 seconds for model version to finish creation` | پیام اطلاع‌رسانی MLflow | بی‌خطر |
| `pytest` بین ۲۵ تا ۴۵ ثانیه طول می‌کشد | ثبت مدل در آزمون‌ها کند است | عادی است |
| `uv run --with shap...` خطای دانلود می‌دهد | اینترنت یا بسته‌ی آفلاین نیست | بخش اختیاری را رها کنید |

برای جلسه‌ی بعد Registry را نگه دارید (`docker compose down -v` نزنید). جلسه‌ی ۸ سرویس FastAPI مدل `models:/churn@champion` را بار می‌کند.

</div>
