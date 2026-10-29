# آزمایشگاه جلسه‌ی ۵ — پایپ‌لاین DVC و بازتولیدپذیری

در این آزمایشگاه کد آموزش را به سه مرحله‌ی جدا (`preprocess`، `train`، `evaluate`) می‌شکنید، آن‌ها را در `dvc.yaml` به هم وصل می‌کنید و می‌بینید DVC فقط مرحله‌هایی را دوباره اجرا می‌کند که ورودی‌شان عوض شده است. بعد چند آزمایش با پارامتر مختلف اجرا و مقایسه می‌کنید.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۴ سالم باشد: داده‌ی نسخه‌ی ۲ با DVC ردیابی شده، `main` شامل tag `v0.2.0` است و SeaweedFS روشن است.
2. مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s05
```

3. سلامت پروژه را بسنجید:

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
uv run dvc status
```

انتظار: `Data and pipelines are up to date.`

```bash
uv run python -m churn.train --config configs/params.yaml
```

انتظار: `{'roc_auc': 0.7493, 'f1': 0.6991}` (عدد داده‌ی نسخه‌ی ۲).

همه‌ی دستورهای بعد در پوشه‌ی `~/work/churn-mlops` اجرا می‌شوند. اگر ترمینال را بستید، خط `K=...` را دوباره بزنید.

فایل‌ها را با VS Code (`code .`) یا `nano` ویرایش کنید.

## نتیجه‌ی نهایی

- سه مرحله‌ی `preprocess`، `train`، `evaluate` در `dvc.yaml` و فایل `dvc.lock` در Git
- `dvc repro` بدون تغییر هیچ مرحله‌ای را اجرا نمی‌کند
- پنج آزمایش با `dvc exp run` و جدول مقایسه
- مخزن روی Gitea با Pull Request ادغام‌شده و tag نسخه‌ی `v0.3.0`، و خروجی‌ها روی remote

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
|---|---|---|
| `churn/preprocess.py` | `src/churn/` | خواندن داده‌ی خام و تقسیم به train و test |
| `churn/train.py` | `src/churn/` | آموزش مدل روی train (جای فایل قبلی) |
| `churn/evaluate.py` | `src/churn/` | امتیازدهی test و نوشتن `metrics.json` |
| `params.yaml` | ریشه‌ی پروژه | همه‌ی پارامترها (جای `configs/params.yaml`) |
| `dvc.yaml` | ریشه‌ی پروژه | تعریف سه مرحله و وابستگی‌هایشان |
| `Makefile` | ریشه‌ی پروژه | `make train` حالا `dvc repro` را اجرا می‌کند |
| `tests/test_pipeline.py` | `tests/` | سه آزمون برای تقسیم داده و متریک |

توضیح خط‌به‌خط کد این جلسه به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — شاخه و بازآرایی کد (۱۵ دقیقه)

```bash
git switch -c feature/dvc-pipeline
```

فایل پارامترها از `configs/` به ریشه می‌رود، چون DVC به‌طور پیش‌فرض `params.yaml` ریشه را می‌خواند:

```bash
git rm -q configs/params.yaml && cp $K/params.yaml .
```

```bash
cp $K/churn/*.py src/churn/ && cp $K/dvc.yaml $K/Makefile . && cp $K/tests/test_pipeline.py tests/
```

> اگر در تکلیف جلسه‌ی ۲ هدف‌های `lint` و `test` را به `Makefile` اضافه کرده بودید، فایل جدید همان‌ها را دارد.

فایل `.gitignore` را باز کنید و خط `metrics.json` را **پاک کنید**. از این پس `metrics.json` خروجی یک مرحله‌ی DVC است و باید در Git باشد تا بتوان متریک‌های commitهای مختلف را مقایسه کرد. خط‌های `models/`، `.env`، `.venv/` و `__pycache__/` بمانند.

سه فایل `src/churn/preprocess.py`، `train.py` و `evaluate.py` را بخوانید. هر کدام یک کار می‌کند و فقط از `params.yaml` و فایل‌های مرحله‌ی قبل می‌خواند.

```bash
uv run ruff check . && uv run ruff format --check .
```

انتظار: `All checks passed!` و `files already formatted`.

```bash
uv run pytest -q
```

انتظار: همه‌ی آزمون‌ها سبز؛ سه آزمون بیشتر از جلسه‌ی ۲ (مثلاً `7 passed`). اجرای اول ممکن است چند ثانیه طول بکشد.

```bash
git add .gitignore Makefile params.yaml src tests
```

```bash
git commit -m "refactor: split training into preprocess/train/evaluate modules"
```

فایل `dvc.yaml` را در گام بعد به Git اضافه می‌کنید.

## گام ۲ — `dvc.yaml` و اولین `dvc repro` (۱۵ دقیقه)

فایل `dvc.yaml` که در گام ۱ کپی کردید را باز کنید. هر مرحله چهار بخش دارد:

| کلید | معنی |
|---|---|
| `cmd` | دستوری که مرحله را اجرا می‌کند |
| `deps` | فایل‌هایی که اگر عوض شوند مرحله باید دوباره اجرا شود |
| `params` | کلیدهای `params.yaml` که این مرحله می‌خواند (فقط همین‌ها حساب می‌شوند) |
| `outs` / `metrics` | خروجی‌هایی که DVC ذخیره و ردیابی می‌کند؛ `cache: false` یعنی خود فایل در Git بماند |

حالا نمودار مرحله‌ها را ببینید:

```bash
uv run dvc dag
```

انتظار:

```
  +------------------------+ 
  | data/raw/churn.csv.dvc | 
  +------------------------+ 
               *             
               *             
               *             
        +------------+       
        | preprocess |       
        +------------+       
         **        **        
       **            **      
      *                **    
+-------+                *   
| train |              **    
+-------+            **      
         **        **        
           **    **          
             *  *            
         +----------+        
         | evaluate |        
         +----------+        
```

داده‌ی خام همان فایل `.dvc` جلسه‌ی ۴ است که حالا ریشه‌ی نمودار شده. اولین اجرای کل پایپ‌لاین:

```bash
uv run dvc repro
```

انتظار (خلاصه):

```
'data/raw/churn.csv.dvc' didn't change, skipping
Running stage 'preprocess':
> uv run python -m churn.preprocess
preprocess: 6400 train rows, 1600 test rows
Generating lock file 'dvc.lock'
Updating lock file 'dvc.lock'

Running stage 'train':
> uv run python -m churn.train
train: fitted on 6400 rows with {'C': 1.0, 'max_iter': 500}
Updating lock file 'dvc.lock'

Running stage 'evaluate':
> uv run python -m churn.evaluate
{'roc_auc': 0.7493, 'f1': 0.6991}
Updating lock file 'dvc.lock'
```

عدد متریک باید همان خروجی پیش از شروع باشد: پایپ‌لاین نتیجه را عوض نکرده است. `dvc.lock` ساخته شد؛ یک نگاه به ابتدای آن بیندازید (md5 فایل‌ها و مقدار پارامترها همان‌جا ثبت می‌شود):

```bash
head -22 dvc.lock
```

```bash
git status --short
```

انتظار: `dvc.yaml`، `dvc.lock`، `metrics.json` و `data/.gitignore` فایل جدیدند. پوشه‌ی `data/processed` و `models` در این فهرست **نیستند**.

```bash
git add dvc.yaml dvc.lock metrics.json data/.gitignore
```

```bash
git commit -m "feat: dvc pipeline preprocess/train/evaluate"
```

```bash
git tag s05-pipeline
```

این tag سبک بعداً برای مقایسه‌ی متریک به کار می‌آید.

## گام ۳ — اجرای هوشمند (۱۵ دقیقه)

**آزمایش ۱ — بدون تغییر.**

```bash
uv run dvc repro
```

انتظار:

```
'data/raw/churn.csv.dvc' didn't change, skipping
Stage 'preprocess' didn't change, skipping
Stage 'train' didn't change, skipping
Stage 'evaluate' didn't change, skipping
Data and pipelines are up to date.
```

**آزمایش ۲ — فقط آستانه.** در `params.yaml` مقدار `threshold` را از `0.5` به `0.35` تغییر دهید و ذخیره کنید. پیش از اجرا بپرسید DVC چه می‌بیند:

```bash
uv run dvc status
```

```
evaluate:
	changed deps:
		params.yaml:
			modified:           eval.threshold
```

```bash
uv run dvc params diff
```

```
Path         Param           HEAD    workspace
params.yaml  eval.threshold  0.5     0.35
```

```bash
uv run dvc repro
```

انتظار: دو مرحله‌ی اول `didn't change, skipping`، و فقط `evaluate` اجرا می‌شود با `{'roc_auc': 0.7493, 'f1': 0.7376}`.

```bash
uv run dvc metrics diff --all
```

```
Path          Metric    HEAD    workspace    Change
metrics.json  f1        0.6991  0.7376       0.0385
metrics.json  roc_auc   0.7493  0.7493       0.0
```

`roc_auc` تکان نخورد (به آستانه وابسته نیست)، `f1` بالا رفت. بدون `--all` فقط ردیف‌های تغییرکرده را می‌بینید.

حالا به حالت commit‌شده برگردید:

```bash
git restore params.yaml dvc.lock metrics.json
```

```bash
uv run dvc status
```

انتظار: `Data and pipelines are up to date.`

**آزمایش ۳ — پاک کردن خروجی‌ها.** DVC خروجی‌های گم‌شده را بدون اجرای دوباره از cache برمی‌گرداند:

```bash
rm -rf data/processed models
```

```bash
uv run dvc repro
```

انتظار:

```
'data/raw/churn.csv.dvc' didn't change, skipping
Stage 'preprocess' is cached - skipping run, checking out outputs

Stage 'train' is cached - skipping run, checking out outputs

Stage 'evaluate' didn't change, skipping
```

به عبارت `cached - skipping run` دقت کنید: هیچ کدی اجرا نشد، فایل‌ها از cache برگشتند.

| تغییر | مرحله‌هایی که دوباره اجرا می‌شوند |
|---|---|
| هیچ | هیچ |
| `eval.threshold` | `evaluate` |
| `train.C` | `train` و `evaluate` |
| `data.test_size` | هر سه |
| ویرایش `src/churn/train.py` | `train` و `evaluate` |

## گام ۴ — آزمایش‌ها (۲۰ دقیقه)

`dvc exp run` یک پارامتر را موقتاً عوض می‌کند، پایپ‌لاین را اجرا می‌کند و نتیجه را بدون commit ثبت می‌کند.

> **دام مهم:** نتیجه‌ی هر آزمایش در پوشه‌ی کار اعمال می‌شود، و آزمایش بعدی از **همان وضعیت** شروع می‌کند، نه از commit. اگر بعد از هر آزمایش به حالت commit‌شده برنگردید، پارامترها روی هم انباشته می‌شوند. بعد از هر آزمایش این دو دستور را بزنید:

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

آزمایش اول:

```bash
uv run dvc exp run -S train.C=0.1
```

انتظار (خلاصه؛ نام آزمایش در اجرای شما فرق دارد):

```
Reproducing experiment 'blown-pith'
'data/raw/churn.csv.dvc' didn't change, skipping
Stage 'preprocess' didn't change, skipping
Running stage 'train':
train: fitted on 6400 rows with {'C': 0.1, 'max_iter': 500}
Running stage 'evaluate':
{'roc_auc': 0.7493, 'f1': 0.701}

Ran experiment(s): blown-pith
Experiment results have been applied to your workspace.
```

`preprocess` رد شد، چون به `train.C` ربطی ندارد. به حالت اول برگردید:

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

چهار آزمایش دیگر، هر کدام بعد از دستور برگشت:

```bash
uv run dvc exp run -S train.C=0.01
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

```bash
uv run dvc exp run -S eval.threshold=0.4
```

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

آزمایش آخر داده‌ی test را عوض می‌کند، پس هر سه مرحله دوباره اجرا می‌شوند:

```bash
uv run dvc exp run -S data.test_size=0.3
```

```bash
git restore params.yaml dvc.lock metrics.json && uv run dvc checkout
```

جدول مقایسه:

```bash
uv run dvc exp show --no-pager --only-changed --md --drop '^data/|^models/|^src/|Created'
```

انتظار (نام‌های آزمایش و hashها در اجرای شما فرق دارند، عددها نه):

```
| Experiment               | roc_auc   | f1     | data.test_size   | train.C   | eval.threshold   |
|--------------------------|-----------|--------|------------------|-----------|------------------|
| workspace                | 0.7493    | 0.6991 | 0.2              | 1         | 0.5              |
| s05-pipeline             | 0.7493    | 0.6991 | 0.2              | 1         | 0.5              |
| ├── 33e9092 [coxal-aril] | 0.7373    | 0.6917 | 0.3              | 1         | 0.5              |
| ├── 61f2d6e [aural-size] | 0.7493    | 0.7319 | 0.2              | 1         | 0.4              |
| ├── d414572 [compo-sand] | 0.7493    | 0.6987 | 0.2              | 10        | 0.5              |
| ├── b95c605 [lying-darg] | 0.7489    | 0.7033 | 0.2              | 0.01      | 0.5              |
| └── 57879fe [muggy-coof] | 0.7493    | 0.701  | 0.2              | 0.1       | 0.5              |
```

بدون `--md` جدول رنگی‌تر است، اما اگر پنجره‌ی ترمینال باریک باشد ستون‌ها با `…` بریده می‌شوند.

سه چیز را از جدول بخوانید:

- `train.C` از ۰٫۰۱ تا ۱۰ تقریباً `roc_auc` را عوض نکرد (۰٫۷۴۸۹ تا ۰٫۷۴۹۳). مدل به این پارامتر حساس نیست.
- `f1` با آستانه‌ی ۰٫۴ از ۰٫۶۹۹۱ به ۰٫۷۳۱۹ رفت، ولی `roc_auc` ثابت ماند. آستانه مدل را بهتر نکرد؛ فقط نقطه‌ی کار را جابه‌جا کرد.
- آزمایش `data.test_size=0.3` عدد `roc_auc` پایین‌تری دارد (۰٫۷۳۷۳)، اما با بقیه **قابل مقایسه نیست**: داده‌ی test عوض شده است.

یکی از آزمایش‌ها را به پوشه‌ی کار بیاورید. نام آزمایش `train.C=0.1` را از ستون Experiment جدول خودتان بردارید (به‌جای `NAME`):

```bash
uv run dvc exp apply NAME
```

```bash
uv run dvc params diff
```

```
Path         Param    HEAD    workspace
params.yaml  train.C  1.0     0.1
```

```bash
uv run dvc metrics diff
```

```
Path          Metric    HEAD    workspace    Change
metrics.json  f1        0.6991  0.701        0.0019
```

## گام ۵ — commit، push و بررسی (۱۰ دقیقه)

```bash
git add params.yaml dvc.lock metrics.json
```

```bash
git commit -m "feat: tune train.C to 0.1 (f1 0.6991 -> 0.701)"
```

خروجی‌های مرحله‌ها (`data/processed` و `models/model.joblib`) را روی remote بفرستید:

```bash
uv run dvc push
```

انتظار: `4 files pushed` (دو فایل train و test، فهرست پوشه‌ی `data/processed` و مدل). داده‌ی خام را در جلسه‌ی ۴ فرستاده بودید.

```bash
uv run dvc status --cloud
```

انتظار: `Cache and remote 'storage' are in sync.`

```bash
git push -u origin feature/dvc-pipeline
```

در Gitea Pull Request بسازید. در توضیح، جدول پیش و پس از متریک را بگذارید:

```
Split train.py into preprocess/train/evaluate stages (dvc.yaml).
train.C 1.0 -> 0.1: roc_auc 0.7493 -> 0.7493, f1 0.6991 -> 0.701.
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
uv run dvc checkout
```

```bash
git tag -a v0.3.0 -m "Session 5: DVC pipeline"
```

```bash
git push origin v0.3.0
```

```bash
uv run dvc repro
```

انتظار: همه‌ی مرحله‌ها `didn't change, skipping`.

---

## بررسی پایان کار

```bash
~/mlops-lab/scripts/verify.sh s05
```

انتظار:

```
[PASS] dvc.yaml has the stages preprocess, train and evaluate
[PASS] dvc.yaml, dvc.lock and params.yaml are committed in Git
[PASS] dvc status: pipeline is up to date (nothing to re-run)
[PASS] metrics.json is tracked, has roc_auc and f1, dvc metrics/params work
[PASS] dvc push done: local cache and remote 'storage' are in sync
[PASS] tag v0.3.0 exists locally and on Gitea
s05: 6/6 checks passed
```

خروجی این دستور را همراه با تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

## عیب‌یابی

| نشانه | علت | راه‌حل |
|---|---|---|
| `ERROR: failed to reproduce 'train': failed to run: uv run python -m churn.train, exited with 1` | خود دستور مرحله خطا داده؛ علت در Traceback **بالای** این خط است | Traceback را بخوانید، کد یا پارامتر را درست کنید، دوباره `uv run dvc repro` |
| `TypeError: build_model() got an unexpected keyword argument 'max_itr'` | غلط املایی در کلید زیر `train:` در `params.yaml` | کلیدها باید دقیقاً `C` و `max_iter` باشند |
| `ModuleNotFoundError: No module named 'joblibb'` یا `No module named churn.evaluate` | غلط املایی در import، یا فایل مرحله به `src/churn/` کپی نشده | `ls src/churn` را ببینید؛ گام ۱ را دوباره بزنید |
| `ERROR: failed to reproduce 'preprocess': output 'data/processed' is already tracked by SCM (e.g. Git)` | فایل‌های `data/processed` وارد Git شده‌اند (مثلاً با `git add -f`) | `git rm -r --cached data/processed` و commit؛ بعد `uv run dvc repro` |
| `'./dvc.yaml' validation failed: ... extra keys not allowed, in stages -> preprocess -> dep` | کلید اشتباه در `dvc.yaml` (باید `deps` باشد) یا تورفتگی نادرست | شماره‌ی خط را در پیام ببینید؛ فاصله به‌جای Tab |
| `DVC failed to load some metrics for following revisions: 'HEAD'` | `metrics.json` در Git نیست، چون هنوز در `.gitignore` است | خط `metrics.json` را از `.gitignore` پاک کنید و `git add metrics.json` |
| `The following paths are ignored by one of your .gitignore files: metrics.json` | همان علت بالا، هنگام `git add` | خط `metrics.json` را از `.gitignore` پاک کنید |
| `dvc status` یا `dvc repro` بعد از clone/switch همه‌ی مرحله‌ها را دوباره اجرا می‌کند؛ verify می‌گوید «not committed» | فایل `dvc.lock` یا `params.yaml` commit نشده است | `git add dvc.lock params.yaml && git commit`؛ `git status --short` را ببینید |
| `changed outs: deleted: models/model.joblib` در `dvc status` | فایل خروجی پاک شده | `uv run dvc checkout` (یا `dvc repro`) آن را از cache برمی‌گرداند |
| `Could not override 'train.CC'. ... Key 'CC' is not in struct` | کلید در `-S` اشتباه است | نام کلید را با `params.yaml` مقایسه کنید: `train.C` |
| آزمایش بعدی عدد عجیب می‌دهد؛ `params.yaml` پارامتر آزمایش قبلی را دارد | نتیجه‌ی آزمایش قبل در پوشه‌ی کار مانده | `git restore params.yaml dvc.lock metrics.json && uv run dvc checkout` |
| `missing data 'source': data/raw/churn.csv` | داده‌ی خام در این پوشه نیست (clone تازه یا حذف شده) | `uv run dvc pull` |
| `Stage 'x' didn't change` ولی فایلی را عوض کرده‌اید | آن فایل در `deps` یا `params` آن مرحله نیست | به `dvc.yaml` اضافه‌اش کنید |
| `Could not connect to the endpoint URL` یا `Forbidden (403)` هنگام `dvc push` | SeaweedFS خاموش است، یا کلیدها در `.dvc/config.local` نیست | همان راه‌حل‌های عیب‌یابی جلسه‌ی ۴ |
| `ruff format --check` فایل‌ها را رد می‌کند | قالب فایل کپی‌شده با تنظیمات شما فرق دارد | `uv run ruff format .` |

`dvc repro --force` همه‌ی مرحله‌ها را بی‌شرط اجرا می‌کند و فقط برای عیب‌یابی است؛ جای اصلاح `deps` را نمی‌گیرد.
