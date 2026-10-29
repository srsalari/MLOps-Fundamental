# آزمایشگاه جلسه‌ی ۶ — MLflow Tracking و اتصال آن به پروژه

در این آزمایشگاه سرور MLflow را با Compose بالا می‌آورید (متادیتا در SQLite، artifactها روی SeaweedFS)، مرحله‌ی `evaluate` پایپ‌لاین DVC را طوری تغییر می‌دهید که هر اجرا را در MLflow ثبت کند، چند آزمایش `dvc exp run` اجرا می‌کنید و نتیجه‌ها را در UI مقایسه می‌کنید.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۵ سالم باشد: پایپ‌لاین سه مرحله‌ای کار می‌کند، `main` شامل tag `v0.3.0` است، SeaweedFS و Gitea روشن‌اند.
2. مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s06
```

3. سلامت پروژه را بسنجید:

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
uv run dvc status
```

انتظار: `Data and pipelines are up to date.`

همه‌ی دستورهای بعد در پوشه‌ی `~/work/churn-mlops` اجرا می‌شوند، مگر جایی که گفته شده. اگر ترمینال را بستید، خط `K=...` را دوباره بزنید.

فایل‌ها را با VS Code (`code .`) یا `nano` ویرایش کنید.

## مفهوم‌ها در یک نگاه

| واژه | معنی در MLflow |
|---|---|
| experiment | گروهی از اجراها؛ ما یکی داریم با نام `churn` |
| run | یک اجرا؛ هر بار که `evaluate` اجرا شود یک run ثبت می‌شود |
| param | ورودی اجرا (مثل `train.C`)، یک‌بار ثبت می‌شود |
| metric | عدد نتیجه (مثل `roc_auc`) |
| tag | برچسب متنی (مثل md5 داده) |
| artifact | فایل خروجی اجرا (مثل `metrics.json` و مدل) |

معماری سرور در این آزمایشگاه:

| بخش | کجاست |
|---|---|
| backend store (param، metric، tag) | فایل SQLite داخل volume کانتینر `mlflow` |
| artifact store (فایل‌ها) | سطل `s3://mlflow` روی SeaweedFS |
| دسترسی کلاینت به artifact | از راه خود سرور (`--serve-artifacts`)؛ کلاینت روی لپ‌تاپ کلید S3 نمی‌خواهد |

## نتیجه‌ی نهایی

- سرور MLflow روی `http://localhost:5050` با experiment به نام `churn`
- چهار run (یکی از `dvc repro` و سه تا از `dvc exp run`) با param، metric، tag، `metrics.json` و مدل
- artifactها روی `s3://mlflow` در SeaweedFS
- کد در Git با tag نسخه‌ی `v0.4.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
|---|---|---|
| `churn/evaluate.py` | `src/churn/` | همان مرحله‌ی `evaluate` به‌علاوه‌ی ثبت run در MLflow (جای فایل قبلی) |
| `scripts/list_runs.py` | `scripts/` | چاپ جدول run‌ها در ترمینال |
| `tests/test_tracking.py` | `tests/` | سه آزمون برای ثبت run (بدون نیاز به سرور) |
| `Makefile` | ریشه‌ی پروژه | هدف تازه‌ی `make runs` |

توضیح خط‌به‌خط کد این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — بالا آوردن سرور MLflow (۱۰ دقیقه)

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow
```

بار اول، Compose تصویر `mlops/mlflow-server:3.17.2` را می‌سازد؛ چند دقیقه طول می‌کشد. وضعیت را ببینید:

```bash
docker compose ps
```

انتظار: دو سرویس `seaweedfs` (با `healthy`) و `mlflow` در حالت `Up`؛ پورت‌ها `127.0.0.1:8333` برای S3 و `127.0.0.1:5050` برای MLflow.

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK`

به پروژه برگردید و شاخه‌ی تازه بسازید:

```bash
cd ~/work/churn-mlops && git switch -c feature/mlflow-tracking
```

سه متغیر را به فایل `.env` پروژه اضافه کنید (این فایل در `.gitignore` است):

```bash
cat >> .env <<'EOF'
MLFLOW_TRACKING_URI=http://localhost:5050
MLFLOW_DISABLE_AGENT_HINT=1
MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false
EOF
```

| متغیر | کار |
|---|---|
| `MLFLOW_TRACKING_URI` | نشانی سرور؛ کد ما اگر این متغیر نباشد همین مقدار را پیش‌فرض می‌گیرد |
| `MLFLOW_DISABLE_AGENT_HINT` | خط راهنمای اضافه‌ی MLflow 3.16 را هنگام import خاموش می‌کند |
| `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD` | دانلود artifact از راه سرور؛ بدون آن `load_model` از روی لپ‌تاپ آویزان می‌شود (عیب‌یابی را ببینید) |

```bash
set -a; source .env; set +a
```

در هر ترمینال تازه این دستور را دوباره بزنید (مثل جلسه‌ی ۴). حالا سطل‌های SeaweedFS را ببینید:

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls
```

انتظار: هر دو سطل `dvc` و `mlflow` در فهرست باشند. اگر `mlflow` نبود، بسازید:

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 mb s3://mlflow
```

مرورگر را روی `http://localhost:5050` باز کنید. در MLflow نسخه‌ی 3.16 بالای نوار کناری دو دکمه هست: **GenAI** و **Model training**. UI اول صفحه‌ی GenAI (Traces، Judges، …) را نشان می‌دهد؛ روی **Model training** کلیک کنید تا فهرست Runها دیده شود. هنوز فقط experiment به نام `Default` هست؛ `churn` را اولین اجرا می‌سازد. اگر پنل «MLflow Assistant» باز شد، با ضربدر ببندید.

> **نکته:** اسکرین‌شات‌ها و خروجی‌های این جلسه با MLflow 3.16.0 گرفته شده‌اند. پین دوره اکنون 3.17.2 است و نمای اولیه‌ی UI (دکمه‌های GenAI و Model training) روی 3.17.2 هنوز دوباره بررسی نشده است.

## گام ۲ — اتصال کد به MLflow (۱۰ دقیقه)

MLflow را با نسخه‌ی دقیق به پروژه اضافه کنید:

```bash
uv add mlflow==3.17.2
```

انتظار: در پایان فهرست بسته‌ها `+ mlflow==3.17.2` (حدود ۴۸ بسته‌ی تازه). فایل‌های `pyproject.toml` و `uv.lock` عوض می‌شوند.

فایل‌های آماده را کپی کنید:

```bash
cp $K/churn/evaluate.py src/churn/ && cp $K/scripts/list_runs.py scripts/ && cp $K/tests/test_tracking.py tests/ && cp $K/Makefile .
```

> اگر به `Makefile` خودتان هدف دیگری اضافه کرده‌اید، فقط هدف `runs` را از فایل جدید به آن اضافه کنید.

دو خط به `.gitignore` اضافه کنید. MLflow اگر نشانی سرور را نشناسد (مثلاً در CLI بدون `.env`) فایل `mlflow.db` را در پوشه‌ی جاری می‌سازد، و آزمون‌ها ممکن است پوشه‌ی `mlruns` بسازند:

```bash
printf 'mlflow.db\nmlruns/\n' >> .gitignore
```

حالا `src/churn/evaluate.py` را بخوانید. تابع‌ها این‌اند:

| تابع | کار |
|---|---|
| `score` | بدون تغییر نسبت به جلسه‌ی ۵ |
| `flatten` | `params.yaml` تودرتو را به کلیدهای `train.C`، `eval.threshold`، … تبدیل می‌کند |
| `data_md5` | md5 داده‌ی خام را از فایل `data/raw/churn.csv.dvc` می‌خواند |
| `check_server` | اگر سرور جواب ندهد، با پیام روشن همان لحظه متوقف می‌شود |
| `log_run` | param، metric، tag، دو فایل و مدل را در MLflow ثبت می‌کند |

آنچه در هر run ثبت می‌شود:

| نوع | مقدار |
|---|---|
| params | همه‌ی `params.yaml` (`data.test_size`، `train.C`، `eval.threshold`، …) |
| metrics | `roc_auc` و `f1` |
| tags | `data_md5` (نسخه‌ی داده)؛ commit و شاخه‌ی Git را خود MLflow به‌صورت `mlflow.source.git.*` ثبت می‌کند |
| artifacts | `metrics.json` و `params.yaml` |
| مدل | `mlflow.sklearn.log_model` با `signature` (نوع ستون‌های ورودی و خروجی) و `input_example` (پنج ردیف نمونه) |

دو تصمیم طراحی:

- **سرور اجباری است.** اگر `evaluate` بی‌سرور بی‌صدا رد می‌شد، `dvc repro` موفق به نظر می‌رسید ولی run گم می‌شد. پس `check_server` با خطای روشن متوقف می‌کند. برای آزمون‌ها سرور لازم نیست: آن‌ها `MLFLOW_TRACKING_URI` را روی یک فایل SQLite موقت می‌گذارند.
- **`mlflow` فقط در `evaluate.py` است** و `dvc.yaml` عوض نمی‌شود. فایل `evaluate.py` از قبل وابستگی مرحله‌ی `evaluate` است.

```bash
uv run ruff check . && uv run ruff format --check .
```

انتظار: `All checks passed!` و `files already formatted`.

```bash
uv run pytest -q
```

انتظار: همه‌ی آزمون‌ها سبز؛ سه آزمون بیشتر از جلسه‌ی ۵. حدود نیم دقیقه طول می‌کشد و دو `warning` درباره‌ی SQLAlchemy و ستون‌های عددی عادی است.

## گام ۳ — اولین run از پایپ‌لاین (۱۵ دقیقه)

```bash
uv run dvc status
```

```
evaluate:
	changed deps:
		modified:           src/churn/evaluate.py
```

DVC می‌داند فقط `evaluate` عوض شده. `preprocess` و `train` دوباره اجرا نمی‌شوند:

```bash
uv run dvc repro
```

انتظار (خلاصه؛ چند خط `INFO` و یک `UserWarning` از MLflow هم چاپ می‌شود که بی‌خطر است):

```
'data/raw/churn.csv.dvc' didn't change, skipping
Stage 'preprocess' didn't change, skipping
Stage 'train' didn't change, skipping
Running stage 'evaluate':
> uv run python -m churn.evaluate
2026/10/15 20:41:49 INFO mlflow.tracking.fluent: Experiment with name 'churn' does not exist. Creating a new experiment.
{'roc_auc': 0.7493, 'f1': 0.701}
🏃 View run C=0.1 thr=0.5 at: http://localhost:5050/#/experiments/1/runs/0d53991549b34f3483520bcf5f68aba4
🧪 View experiment at: http://localhost:5050/#/experiments/1
mlflow: run 0d539915 logged to experiment 'churn' at http://localhost:5050
Updating lock file 'dvc.lock'
```

متریک همان جلسه‌ی ۵ است؛ پایپ‌لاین عوض نشد، فقط حالا ثبت می‌شود. شناسه‌ی run شما فرق دارد. جدول را در ترمینال ببینید:

```bash
make runs
```

```
  run_id          name   C threshold  roc_auc    f1
0d539915 C=0.1 thr=0.5 0.1       0.5   0.7493 0.701
```

### در UI چه می‌بینید

در `http://localhost:5050`، حالت **Model training**، experiment `churn`، روی نام run کلیک کنید:

- **Overview:** بخش Metrics با `roc_auc` و `f1`؛ بخش Parameters با شش param؛ Tags با `data_md5`؛ بخش Source با نام شاخه و commit. چون کد را هنوز commit نکرده‌اید، commit همان `2834c33` (یا commit آخر شما در `main`) است، یعنی پیش از این تغییر.
- **Artifacts:** دو فایل `metrics.json` و `params.yaml`.
- **Logged models:** یک مدل به نام `model` با وضعیت Ready. در MLflow 3 مدل هم‌رده‌ی run است و در پوشه‌ی خودش ذخیره می‌شود، نه زیر `artifacts` همان run. روی مدل کلیک کنید: `MLmodel`، `signature` و `input_example` را ببینید.

### artifactها روی S3

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls s3://mlflow/ --recursive
```

انتظار:

```
2026-10-15 20:41:50         38 1/0d53991549b34f3483520bcf5f68aba4/artifacts/metrics.json
2026-10-15 20:41:50        120 1/0d53991549b34f3483520bcf5f68aba4/artifacts/params.yaml
2026-10-15 20:41:53       1418 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/MLmodel
2026-10-15 20:41:53       2304 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/conda.yaml
2026-10-15 20:41:53        372 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/input_example.json
2026-10-15 20:41:53      97937 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/model.skops
2026-10-15 20:41:53        107 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/python_env.yaml
2026-10-15 20:41:53       1854 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/requirements.txt
2026-10-15 20:41:53        767 1/models/m-725474ca4ea1430a9f56dc2b61c960f0/artifacts/serving_input_example.json
```

مسیرها: عدد اول شماره‌ی experiment است؛ بعد `<run_id>/artifacts/` برای فایل‌های run و `models/<model_id>/artifacts/` برای مدل. مدل با فرمت `skops` ذخیره می‌شود (نه pickle). فایل‌ها روی لپ‌تاپ شما نیستند: کلاینت آن‌ها را به سرور می‌فرستد و سرور در `s3://mlflow` می‌نویسد.

### `dvc repro` و run: یک دام مهم

```bash
uv run dvc repro
```

```
Stage 'evaluate' didn't change, skipping
Data and pipelines are up to date.
```

```bash
make runs
```

هنوز یک run هست. ثبت در MLflow یک **اثر جانبی** است و DVC از آن خبر ندارد: DVC فقط وقتی `evaluate` را اجرا می‌کند که ورودی‌هایش عوض شده باشند، پس بدون تغییر هیچ run تازه‌ای نمی‌آید. run تازه می‌خواهید؟ پارامتر را عوض کنید (گام ۴).

کد و `dvc.lock` را commit کنید (hash تازه‌ی `evaluate.py` در `dvc.lock` ثبت شده):

```bash
git add pyproject.toml uv.lock dvc.lock src/churn/evaluate.py scripts tests Makefile .gitignore
```

```bash
git commit -m "feat: log every evaluation run to MLflow"
```

## گام ۴ — سه آزمایش و مقایسه (۲۵ دقیقه)

`dvc exp run -S` پارامتر را موقتاً عوض می‌کند و پایپ‌لاین را اجرا می‌کند؛ چون `evaluate` هم اجرا می‌شود، هر آزمایش یک run تازه در MLflow می‌سازد. مثل جلسه‌ی ۵ بعد از هر آزمایش به حالت commit‌شده برگردید، وگرنه پارامترها روی هم انباشته می‌شوند.

آزمایش اول:

```bash
uv run dvc exp run -S train.C=0.01
```

انتظار (خلاصه؛ نام آزمایش DVC در اجرای شما فرق دارد):

```
Reproducing experiment 'bared-bout'
'data/raw/churn.csv.dvc' didn't change, skipping
Stage 'preprocess' didn't change, skipping
Running stage 'train':
> uv run python -m churn.train
train: fitted on 6400 rows with {'C': 0.01, 'max_iter': 500}
Running stage 'evaluate':
> uv run python -m churn.evaluate
{'roc_auc': 0.7489, 'f1': 0.7033}
🏃 View run C=0.01 thr=0.5 at: http://localhost:5050/#/experiments/1/runs/c57f5f0ee5454bf6a6430cd33ef70255
mlflow: run c57f5f0e logged to experiment 'churn' at http://localhost:5050

Ran experiment(s): bared-bout
Experiment results have been applied to your workspace.
```

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

دو آزمایش دیگر، هر کدام بعد از دستور برگشت:

```bash
uv run dvc exp run -S train.C=1
```

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

```bash
uv run dvc exp run -S train.C=10
```

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

مقدار `train.C=0.1` را در run گام ۳ دارید. جدول در ترمینال:

```bash
make runs
```

انتظار (شناسه‌ها فرق دارند، عددها نه):

```
  run_id           name    C threshold  roc_auc     f1
a612d9d0   C=10 thr=0.5   10       0.5   0.7493 0.6987
8642ddf9    C=1 thr=0.5    1       0.5   0.7493 0.6991
c57f5f0e C=0.01 thr=0.5 0.01       0.5   0.7489 0.7033
0d539915  C=0.1 thr=0.5  0.1       0.5   0.7493 0.7010
```

همین مقایسه را DVC هم نشان می‌دهد (برای مقایسه با MLflow):

```bash
uv run dvc exp show --no-pager --only-changed --md --drop '^data/|^models/|^src/|Created'
```

```
| Experiment               | roc_auc   | f1     | train.C   |
|--------------------------|-----------|--------|-----------|
| workspace                | 0.7493    | 0.701  | 0.1       |
| feature/mlflow-tracking  | 0.7493    | 0.701  | 0.1       |
| ├── 6456413 [blind-sign] | 0.7493    | 0.6987 | 10        |
| ├── 13017cf [felon-dent] | 0.7493    | 0.6991 | 1         |
| └── 220ab5c [bared-bout] | 0.7493    | 0.7033 | 0.01      |
```

تفاوت دو ابزار: DVC آزمایش را به **commit و پارامتر** وصل می‌کند و فایل‌ها را بازتولید می‌کند. MLflow همه‌ی اجراها را در یک **UI** با نمودار، artifact و مدل نشان می‌دهد. نام آزمایش DVC (مثل `blind-sign`) در MLflow ثبت نمی‌شود؛ run را از روی param و زمان پیدا می‌کنید.

### مقایسه در UI

1. در `http://localhost:5050` حالت **Model training**، experiment `churn`.
2. چهار run را با چک‌باکس تیک بزنید و دکمه‌ی **Compare** (کنار Rename و Delete) را بزنید.
3. در صفحه‌ی مقایسه param‌ها و metricها کنار هم می‌آیند؛ `train.C`، `roc_auc` و `f1` را بخوانید.
4. به فهرست run‌ها برگردید و با آیکون نمودار (دومین آیکون بالای فهرست) نمودار run‌ها را ببینید. از منوی **Columns** می‌توانید param و metric را به جدول فهرست اضافه کنید.

سه چیز را بخوانید:

- `roc_auc` برای `train.C` از ۰٫۰۱ تا ۱۰ تقریباً ثابت است (۰٫۷۴۸۹ تا ۰٫۷۴۹۳).
- بهترین `f1` مال `C=0.01` است (۰٫۷۰۳۳) و بدترین مال `C=10` (۰٫۶۹۸۷)؛ تفاوت‌ها کوچک‌اند.
- هر چهار run روی یک داده و یک split ثبت شده‌اند: `data_md5` یکی است. در Tags همین را مقایسه کنید.

### اگر آزمایشی را تکرار کنید

```bash
uv run dvc exp run -S train.C=0.01
```

```
Stage 'train' is cached - skipping run, checking out outputs
Stage 'evaluate' is cached - skipping run, checking out outputs
```

DVC نتیجه‌ی همین ترکیب را در run-cache دارد و کد را اجرا نمی‌کند؛ پس **run تازه‌ای در MLflow نمی‌آید**. اگر عمداً run تکراری می‌خواهید:

```bash
uv run dvc exp run -S train.C=0.01 --force
```

و برای ثبت دوباره‌ی همان وضعیت پوشه‌ی کار، بدون اجرای مرحله‌های دیگر:

```bash
uv run dvc repro --force --single-item evaluate
```

بعد از هر کدام `git restore params.yaml dvc.lock metrics.json && uv run dvc checkout` بزنید.

## گام ۵ — commit، Pull Request و بررسی (۱۵ دقیقه)

پوشه‌ی کار باید تمیز باشد (آزمایش‌ها فقط در DVC مانده‌اند):

```bash
git status --short
```

انتظار: هیچ خروجی. حالا وضعیت remote و push:

```bash
uv run dvc status --cloud
```

انتظار: `Cache and remote 'storage' are in sync.` (این جلسه خروجی تازه‌ای برای `dvc push` نداریم.)

```bash
git push -u origin feature/mlflow-tracking
```

در Gitea Pull Request بسازید و در توضیح بنویسید:

```
evaluate logs params, metrics, tags, metrics.json and the model to MLflow (experiment churn).
4 runs: train.C 0.01/0.1/1/10, roc_auc 0.7489-0.7493, f1 0.6987-0.7033.
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.4.0 -m "Session 6: MLflow tracking"
```

```bash
git push origin v0.4.0
```

```bash
uv run dvc repro
```

انتظار: همه‌ی مرحله‌ها `didn't change, skipping`.

---

## بررسی پایان کار

```bash
~/mlops-lab/scripts/verify.sh s06
```

انتظار:

```
[PASS] MLflow server answers at http://localhost:5050
[PASS] experiment 'churn' exists
[PASS] at least 3 finished runs with roc_auc, f1 and train.C
       runs with metrics: 4
[PASS] latest run has metrics.json and a model on the artifact store (S3)
[PASS] mlflow pinned in pyproject.toml; evaluate.py, uv.lock and dvc.lock committed
[PASS] tag v0.4.0 exists locally and on Gitea
s06: 6/6 checks passed
```

نشانی سرور را می‌توان عوض کرد: `MLFLOW_TRACKING_URI=http://... ~/mlops-lab/scripts/verify.sh s06`. خروجی را همراه با تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

## عیب‌یابی

| نشانه | علت | راه‌حل |
|---|---|---|
| `MLflow server not reachable at http://localhost:5050 (ConnectionError).` و بعد `exited with 1` | سرور MLflow خاموش است | `cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow`، بعد `curl -s http://localhost:5050/health` |
| `Invalid Host header - possible DNS rebinding attack detected` | نشانی یا پورت غیر از `localhost:5050` (مثلاً نام دیگر یا پورت عوض‌شده)؛ سرور فقط میزبان‌های فهرست `--allowed-hosts` را می‌پذیرد | از `http://localhost:5050` استفاده کنید؛ برای نشانی دیگر آن را به `--allowed-hosts` در `compose/docker-compose.yml` اضافه و `docker compose up -d mlflow` کنید |
| `load_model` یا `download_artifacts` بدون هیچ خطا آویزان می‌شود (دقیقه‌ها) | سرور برای دانلود، نشانی امضاشده‌ی `http://seaweedfs:8333/...` می‌دهد که از لپ‌تاپ شما قابل دسترسی نیست | `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false` در `.env` و دوباره `set -a; source .env; set +a` |
| UI صفحه‌ی Overview/Traces (GenAI) نشان می‌دهد و run‌ها دیده نمی‌شوند | UI نسخه‌ی 3.16 با حالت GenAI شروع می‌کند | بالای نوار کناری روی **Model training** کلیک کنید |
| `dvc repro` یا `dvc exp run` موفق شد ولی run تازه‌ای در MLflow نیست | مرحله‌ی `evaluate` اجرا نشد: `didn't change, skipping` یا `is cached - skipping run` | پارامتر را عوض کنید، یا `uv run dvc repro --force --single-item evaluate` |
| فایل `mlflow.db` در پوشه‌ی پروژه پیدا شد | دستور MLflow (مثلاً `uv run mlflow runs list`) بدون `MLFLOW_TRACKING_URI` اجرا شد و روی یک پایگاه محلی نوشت | `set -a; source .env; set +a`؛ فایل را پاک کنید؛ خط `mlflow.db` در `.gitignore` هست |
| `uv run mlflow runs list` فهرست خالی می‌دهد | همان علت بالا | `source .env` و دوباره با `--experiment-id 1` |
| بعد از `docker compose down -v` همه‌ی run‌ها و artifactها رفتند | گزینه‌ی `-v` volumeها (SQLite و داده‌ی SeaweedFS) را پاک می‌کند | برای خاموش کردن فقط `docker compose down` بزنید؛ برای شروع تازه بعد از `down -v` سطل‌ها را دوباره بسازید و `dvc push` کنید |
| `An error occurred (NoSuchBucket) ... The specified bucket does not exist` در `aws s3 ls s3://mlflow/` | سطل `mlflow` ساخته نشده یا volume پاک شده | `uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 mb s3://mlflow` |
| `Could not connect to the endpoint URL` برای `aws` یا `dvc` | SeaweedFS خاموش است یا `S3_ENDPOINT_URL` در شل نیست | `docker compose ps`، `source .env` |
| `ruff` یا آزمون خطای import `mlflow` می‌دهد | `uv add mlflow==3.17.2` اجرا نشده یا محیط قدیمی است | `uv add mlflow==3.17.2` و `uv sync` |
| `pytest` خیلی کند است (۳۰ ثانیه) | ثبت مدل (`log_model`) و ساخت فایل‌های `conda.yaml`/`requirements.txt` | عادی است |
| هشدار `Hint: Inferred schema contains integer column(s)` | ستون‌های عددی صحیح در signature؛ فقط راهنمایی MLflow برای مقادیر خالی است | بی‌خطر؛ نادیده بگیرید |
| `verify.sh s06` در بند «latest run has metrics.json and a model» رد می‌شود | آخرین run کامل نیست (مثلاً قطع شده) یا سطل `mlflow` پاک شده | `uv run dvc repro --force --single-item evaluate` تا run کامل تازه ساخته شود |

برای جلسه‌ی بعد پروژه را روی `main` و سالم نگه دارید و run‌ها را پاک نکنید (`docker compose down -v` نزنید).
