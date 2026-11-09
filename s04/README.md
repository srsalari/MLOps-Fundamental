<div dir="rtl">

# آزمایشگاه جلسه‌ی ۴ — نسخه‌بندی داده با DVC (remote روی SeaweedFS)

تا حالا کد را با Git نسخه‌بندی کردید، ولی فایل `churn.csv` را نه: اگر فردا داده‌ی تازه‌ای با همان نام بسازید، نسخه‌ی قبلی برای همیشه از بین می‌رود. در این آزمایشگاه با **DVC** داده را هم مثل کد «نسخه‌دار» می‌کنید: یک فایل کوچک متنی (pointer) در Git می‌ماند و خود فایل داده در انبار S3 شما (SeaweedFS) ذخیره می‌شود. بعد دو نسخه‌ی داده می‌سازید، به نسخه‌ی اول برمی‌گردید و می‌بینید دقیقاً همان متریک اول برمی‌گردد.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۳ سالم باشد: `~/work/churn-mlops` روی شاخه‌ی `main`، remote به نام `origin` روی Gitea، فایل `.env` با چهار متغیر (`S3_ENDPOINT_URL`، `AWS_ACCESS_KEY_ID`، `AWS_SECRET_ACCESS_KEY`، `AWS_DEFAULT_REGION`) و دستور `make train` که `0.802` می‌دهد.
2. مخزن دوره را به‌روز کنید:

```bash
git -C ~/mlops-lab pull
```

3. <bdi dir="rtl">SeaweedFS باید روشن باشد و ستون STATUS آن `healthy` بگوید:</bdi>

```bash
cd ~/mlops-lab/compose && docker compose ps
```

> اگر `seaweedfs` خاموش است، فقط همان را روشن کنید: `docker compose up -d seaweedfs`. اگر Docker خطا می‌دهد، روی مک `colima start` را بزنید.

4. یک حساب Gitea و مرورگر باز روی `http://localhost:3000` داشته باشید.

در این جلسه فایل آماده‌ای برای کپی کردن نیست: همه‌ی کد را از جلسه‌های قبل دارید (اسکریپت `make_dataset.py` از جلسه‌ی ۱ گزینه‌های `--rows` و `--drift` را دارد). همه‌ی دستورهای بعد در پوشه‌ی `~/work/churn-mlops` اجرا می‌شوند. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell.

> روی مک برای md5 فایل از `md5 -q data/raw/churn.csv` استفاده می‌کنید. روی لینوکس و WSL به‌جایش `md5sum data/raw/churn.csv` بزنید (اولین ستون همان md5 است).

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| DVC | ابزاری که کنار Git کار می‌کند و فایل‌های بزرگ (داده، مدل) را نسخه‌بندی می‌کند |
| pointer | فایل کوچک `churn.csv.dvc` که md5 و اندازه‌ی فایل داده را نگه می‌دارد؛ این فایل در Git می‌رود، نه خود داده |
| md5 | «اثر انگشت» محتوای فایل؛ با تغییر یک بایت، کاملاً عوض می‌شود |
| cache | پوشه‌ی `.dvc/cache` روی لپ‌تاپ شما؛ یک نسخه از هر فایل با نامی که از md5 ساخته شده |
| remote | «انبار مشترک» داده؛ اینجا همان SeaweedFS با پروتکل S3 |
| `dvc add` | md5 را حساب می‌کند، فایل را در cache می‌گذارد و pointer را می‌سازد |
| `dvc push` و `dvc pull` | فرستادن داده به remote و گرفتن آن از remote |
| `dvc checkout` | فایل داده‌ی داخل پوشه‌ی کار را مطابق pointer فعلی Git عوض می‌کند |
| tag | برچسب روی یک commit، مثل `data-v1`؛ بدون آن بعداً نمی‌دانید کدام commit نسخه‌ی ۱ بود |
| `--local` | رمز را در `.dvc/config.local` می‌نویسد که Git آن را نمی‌بیند |

دو داده‌ی این جلسه (عددهایی که باید دقیقاً ببینید):

|  | نسخه‌ی ۱ | نسخه‌ی ۲ |
| --- | --- | --- |
| ردیف | ۵۰۰۰ | ۸۰۰۰ |
| churn rate | 36.1% | 52.4% |
| اندازه | 201202 بایت | 320763 بایت |
| md5 | `79921313c42d311a4e6cbd6c828c4839` | `e0be77bd53ec0f8feda77f6e779c4a3d` |
| roc_auc | 0.802 | 0.7493 |
| f1 | 0.5969 | 0.6991 |

## نتیجه‌ی نهایی

- <bdi dir="rtl">DVC با نسخه‌ی `3.67.1` نصب شده و pointer داده (نه خود داده) در Git است</bdi>
- <bdi dir="rtl">remote به نام `storage` روی `s3://dvc/store` تنظیم شده و رمز فقط در `.dvc/config.local` است</bdi>
- دو نسخه‌ی داده با tagهای `data-v1` و `data-v2`، هر دو در bucket به نام `dvc`
- بازگشت به نسخه‌ی ۱ با همان md5 و همان متریک، و بازیابی داده بعد از حذف با `dvc pull`
- <bdi dir="rtl">Pull Request مرج‌شده در Gitea و tag نسخه‌ی `v0.2.0`</bdi>

---

## گام ۱ — بررسی SeaweedFS و نصب DVC (۱۰ دقیقه)

روی یک شاخه‌ی تازه کار می‌کنیم تا همه‌چیز با Pull Request وارد `main` شود:

```bash
cd ~/work/churn-mlops && git switch main && git switch -c feature/dvc-data
```

متغیرهای `.env` را در این ترمینال بارگذاری کنید و فهرست bucketها را ببینید:

```bash
set -a; source .env; set +a
```

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls
```

انتظار: دست‌کم این دو سطر (تاریخ‌ها فرق دارند):

```
2026-10-17 12:58:59 dvc
2026-10-17 12:59:01 mlflow
```

> اگر `dvc` نبود: `uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 mb s3://dvc`

<bdi dir="rtl">DVC را فقط به‌عنوان dev dependency نصب می‌کنیم (برای ساخت مدل لازم نیست، برای مدیریت داده لازم است) و نسخه را دقیق می‌نویسیم تا همه یک رفتار ببینند:</bdi>

```bash
uv add --dev "dvc[s3]==3.67.1"
```

```bash
uv run dvc --version
```

انتظار:

```
3.67.1
```

<bdi dir="rtl">DVC را در پروژه آماده کنید و ارسال آمار ناشناس را خاموش کنید:</bdi>

```bash
uv run dvc init
```

```bash
uv run dvc config core.analytics false
```

```bash
git status --short
```

انتظار (پنج سطر):

```
A  .dvc/.gitignore
AM .dvc/config
A  .dvcignore
 M pyproject.toml
 M uv.lock
```

> <bdi dir="rtl">`AM` خطا نیست: یعنی `dvc init` فایل config را stage کرد و تنظیم analytics دوباره آن را عوض کرد. با `git add` زیر دوباره stage می‌شود.</bdi>

```bash
git add .dvc .dvcignore pyproject.toml uv.lock
```

```bash
git commit -m "chore: init DVC"
```

<bdi dir="rtl">hookهای commit اجرا می‌شوند؛ هر کدام Passed یا Skipped است و هیچ‌کدام `Failed` نیست.</bdi>

## گام ۲ — ردیابی داده با `dvc add` (۱۲ دقیقه)

<bdi dir="rtl">`dvc add` سه کار می‌کند: md5 فایل را حساب می‌کند، یک نسخه از فایل را در `.dvc/cache` می‌گذارد و فایل کوچک `churn.csv.dvc` را می‌سازد. همین فایل کوچک در Git می‌رود.</bdi>

داده را بسازید و DVC را روی آن اجرا کنید:

```bash
make data
```

انتظار:

```
uv run python scripts/make_dataset.py
wrote 5000 rows to data/raw/churn.csv (churn rate 36.1%)
```

```bash
uv run dvc add data/raw/churn.csv
```

**یک خطا انتظار دارید و عادی است.** انتظار:

```
ERROR: bad DVC file name 'data/raw/churn.csv.dvc' is git-ignored.
```

این خطا از DVC نیست. در جلسه‌ی ۱ برای بیرون نگه داشتن داده یک قاعده در `.gitignore` گذاشتید که فایل pointer را هم ignore می‌کند. ببینید قاعده از کجاست:

```bash
git check-ignore -v data/raw/churn.csv.dvc
```

انتظار:

```
.gitignore:1:data/	data/raw/churn.csv.dvc
```

عدد `1` شماره‌ی خط قاعده در `.gitignore` است. حالا که pointer باید در Git باشد، خط `data/` باید برود. فایل `.gitignore` را با VS Code یا nano باز کنید و آن خط را پاک کنید، یا این دستور (روی مک، لینوکس و WSL کار می‌کند):

```bash
sed -i.bak '/^data\/$/d' .gitignore && rm .gitignore.bak
```

```bash
cat .gitignore
```

انتظار (خط `data/` نیست):

```
models/
metrics.json
.env
.venv/
__pycache__/
```

> اگر باز هم خطا گرفتید، خط دیگری مثل `data/raw` در `.gitignore` هست. دستور `git check-ignore -v` شماره‌ی خط را می‌گوید.

دوباره اجرا کنید:

```bash
uv run dvc add data/raw/churn.csv
```

<bdi dir="rtl">DVC در پایان دو پیشنهاد چاپ می‌کند (`git add ...` و `core.autostage`). فعلاً به آن‌ها دست نزنید.</bdi>

```bash
git status --short
```

انتظار:

```
 M .gitignore
?? data/
```

خود `churn.csv` در فهرست نیست: DVC آن را در یک `.gitignore` کوچک کنار فایل ignore کرده است. حالا سه فایل را ببینید:

```bash
cat data/raw/churn.csv.dvc
```

انتظار:

```
outs:
- md5: 79921313c42d311a4e6cbd6c828c4839
  size: 201202
  hash: md5
  path: churn.csv
```

```bash
cat data/raw/.gitignore
```

انتظار:

```
/churn.csv
```

```bash
find .dvc/cache -type f
```

انتظار: همان md5 با دو رقم اول به‌عنوان نام پوشه:

```
.dvc/cache/files/md5/79/921313c42d311a4e6cbd6c828c4839
```

این یعنی cache «محتوا‌محور» است: نام فایل همان اثر انگشت محتوا است. حالا pointer را در Git بگذارید (سه فایل):

```bash
git add .gitignore data/raw/.gitignore data/raw/churn.csv.dvc
```

```bash
git commit -m "feat: track churn dataset with DVC"
```

```bash
git ls-files data
```

انتظار: فقط pointer و gitignore کوچک، نه csv:

```
data/raw/.gitignore
data/raw/churn.csv.dvc
```

> اشتباهی `git add data/raw/churn.csv` نزنید. به فایل داده دست نزنید؛ pointer را add کنید.

## گام ۳ — remote با رمز محلی و push (۱۳ دقیقه)

تا الان بایت‌های داده فقط روی لپ‌تاپ شما هستند. remote یعنی انبار مشترک. آدرس `s3://dvc/store` یعنی در bucket به نام `dvc` و زیر پوشه‌ی `store`.

نام remote و نشانی سرور در `.dvc/config` می‌رود و در Git commit می‌شود، چون رازی نیست. اگر ترمینال را بسته‌اید، اول دوباره بزنید:

```bash
set -a; source .env; set +a
```

```bash
uv run dvc remote add -d storage s3://dvc/store
```

```bash
uv run dvc remote modify storage endpointurl "$S3_ENDPOINT_URL"
```

رمز و کلید هرگز نباید وارد Git شوند. گزینه‌ی `--local` آن‌ها را در `.dvc/config.local` می‌نویسد که از قبل ignore شده است. ما حتی رمز را تایپ نمی‌کنیم و از متغیرهای `.env` می‌خوانیم:

```bash
uv run dvc remote modify --local storage access_key_id "$AWS_ACCESS_KEY_ID"
```

```bash
uv run dvc remote modify --local storage secret_access_key "$AWS_SECRET_ACCESS_KEY"
```

```bash
git status --short
```

انتظار: فقط یک سطر؛ `config.local` نباید دیده شود:

```
 M .dvc/config
```

```bash
cat .dvc/config
```

انتظار (پورت در سیستم شما همان پورت `S3_ENDPOINT_URL` است؛ هیچ رمزی در فایل نیست):

```
[core]
    analytics = false
    remote = storage
['remote "storage"']
    url = s3://dvc/store
    endpointurl = http://localhost:8333
```

> سطر `['remote "storage"']` با کروشه و کوتیشن همین‌طور نوشته می‌شود؛ عادی است. فایل `.dvc/config.local` را با `cat` روی صفحه نیاورید (رمز آنجاست).

پیش از push وضعیت cache و remote را ببینید، بعد push کنید:

```bash
uv run dvc status -c
```

انتظار:

```
	new:                data/raw/churn.csv
```

```bash
uv run dvc push
```

انتظار:

```
1 file pushed
```

```bash
uv run dvc status -c
```

انتظار:

```
Cache and remote 'storage' are in sync.
```

حالا شیء را در خود bucket ببینید (`--recursive` را فراموش نکنید، وگرنه فقط سطح اول دیده می‌شود):

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls s3://dvc/ --recursive
```

انتظار (تاریخ فرق دارد؛ اندازه و کلید همان است):

```
2026-10-17 13:00:01     201202 store/files/md5/79/921313c42d311a4e6cbd6c828c4839
```

```bash
git add .dvc/config
```

```bash
git commit -m "chore: add DVC remote on SeaweedFS"
```

<bdi dir="rtl">hook با نام `block hard-coded secrets` باید `Passed` بدهد.</bdi>

**اگر رمز را بدون `--local` نوشتید:** این hook commit را رد می‌کند و شماره‌ی خط را می‌گوید (مثلاً `.dvc/config:7`). رمز را از فایل config پاک کنید و دوباره آن را فقط با `--local` بدهید:

```bash
uv run dvc remote modify storage --unset secret_access_key
```

## گام ۴ — نسخه‌ی ۲ داده و مقایسه‌ی متریک (۱۶ دقیقه)

اول مدل را روی نسخه‌ی ۱ می‌سازیم و عدد را یادداشت می‌کنیم:

```bash
make train
```

انتظار:

```
{'roc_auc': 0.802, 'f1': 0.5969}
```

حالا پیش از ساخت نسخه‌ی ۲ همین commit را علامت بزنید. این مهم‌ترین قدم گام است: بدون tag بعداً نمی‌دانید کدام commit نسخه‌ی ۱ بود.

```bash
git tag -a data-v1 -m "dataset v1 (5000 rows)"
```

```bash
git tag -n1
```

انتظار: tag تازه و `v0.1.0` از جلسه‌ی ۲ (اگر tagهای دیگری ساخته‌اید آن‌ها هم هستند):

```
data-v1         dataset v1 (5000 rows)
v0.1.0          ...
```

نسخه‌ی ۲ را با همان اسکریپت می‌سازید، ولی با ۸۰۰۰ ردیف و گزینه‌ی `--drift` (مشتری‌های جدیدتر، گران‌تر و کم‌وفاتر). فایل با همان نام و مسیر بازنویسی می‌شود:

```bash
uv run python scripts/make_dataset.py --rows 8000 --drift
```

انتظار:

```
wrote 8000 rows to data/raw/churn.csv (churn rate 52.4%)
```

```bash
uv run dvc status
```

انتظار: DVC می‌گوید فایل با pointer نمی‌خواند:

```
data/raw/churn.csv.dvc:
	changed outs:
		modified:           data/raw/churn.csv
```

```bash
uv run dvc add data/raw/churn.csv
```

```bash
git diff data/raw/churn.csv.dvc
```

انتظار: فقط دو خط md5 و size عوض شده است:

```
-- md5: 79921313c42d311a4e6cbd6c828c4839
-  size: 201202
+- md5: e0be77bd53ec0f8feda77f6e779c4a3d
+  size: 320763
```

(در خروجی واقعی پیش از هر خط `-` یا `+` یک خط با `@@` و چند خط بدون تغییر هم هست.) داده‌ی تازه را push کنید و تفاوت را ببینید:

```bash
uv run dvc push
```

انتظار: فقط شیء جدید فرستاده می‌شود:

```
1 file pushed
```

```bash
uv run dvc diff --show-hash
```

انتظار:

```
Modified:
    79921313..e0be77bd  data/raw/churn.csv

files summary: 1 modified
```

<bdi dir="rtl">`dvc diff` نمی‌گوید کدام ردیف‌ها عوض شدند؛ فقط می‌گوید کدام فایل عوض شده و md5 قبل و بعد چه بود. تحلیل ردیف‌ها کار pandas است. حالا مدل را روی داده‌ی تازه بسازید:</bdi>

```bash
make train
```

انتظار:

```
{'roc_auc': 0.7493, 'f1': 0.6991}
```

<bdi dir="rtl">AUC پایین آمد ولی f1 بالا رفت. دلیلش این است که نرخ ریزش از ۳۶٫۱٪ به ۵۲٫۴٪ رسیده و f1 به فراوانی کلاس مثبت حساس است. دو مدل روی دو توزیع مختلف را با یک عدد مقایسه نکنید.</bdi>

<bdi dir="rtl">pointer جدید را commit و tag کنید:</bdi>

```bash
git add data/raw/churn.csv.dvc
```

```bash
git commit -m "feat: dataset v2 (8000 rows, drifted)"
```

```bash
git tag -a data-v2 -m "dataset v2 (8000 rows, drift)"
```

```bash
git tag -n1
```

انتظار: tag `data-v2` هم اضافه شده است. در bucket باید دو شیء با دو اندازه‌ی متفاوت باشد:

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls s3://dvc/ --recursive
```

انتظار (تاریخ‌ها فرق دارند):

```
2026-10-17 13:00:01     201202 store/files/md5/79/921313c42d311a4e6cbd6c828c4839
2026-10-17 13:00:29     320763 store/files/md5/e0/be77bd53ec0f8feda77f6e779c4a3d
```

> اگر نسخه‌ی ۲ را ساختید ولی tag نسخه‌ی ۱ را فراموش کرده بودید: با `git log --oneline` hash commit مربوط به `chore: add DVC remote on SeaweedFS` را پیدا کنید و روی همان tag بزنید: `git tag -a data-v1 -m "dataset v1 (5000 rows)" <hash>`.

## گام ۵ — زمان‌سفر، بازیابی و Pull Request (۱۷ دقیقه)

### الف) بازگشت به نسخه‌ی ۱

زمان‌سفر دو قدم است: Git اشاره‌گر را به commit قدیمی می‌برد، بعد DVC فایل داده را مطابق pointer آن commit عوض می‌کند. اگر قدم دوم را نزنید، فایل داده هنوز نسخه‌ی ۲ است.

```bash
git checkout data-v1
```

(Git پیام طولانی `detached HEAD` چاپ می‌کند؛ عادی است.)

```bash
uv run dvc checkout
```

انتظار:

```
M       data/raw/churn.csv
```

```bash
md5 -q data/raw/churn.csv
```

انتظار: md5 نسخه‌ی ۱ برگشته است (روی لینوکس و WSL `md5sum data/raw/churn.csv`):

```
79921313c42d311a4e6cbd6c828c4839
```

```bash
make train
```

انتظار: همان متریک گام ۴ برای نسخه‌ی ۱. این یعنی بازتولیدپذیری: همان کد، همان داده، همان عدد.

```
{'roc_auc': 0.802, 'f1': 0.5969}
```

به آخرین نسخه برگردید:

```bash
git checkout feature/dvc-data
```

```bash
uv run dvc checkout
```

```bash
md5 -q data/raw/churn.csv
```

انتظار:

```
e0be77bd53ec0f8feda77f6e779c4a3d
```

### ب) بازیابی بعد از «فاجعه»

حالا فایل داده و cache را پاک می‌کنیم. چون پیش‌تر push کرده‌اید، با `dvc pull` همه‌چیز برمی‌گردد. **هشدار:** `rm` خطرناک است. فقط این دو مسیر را پاک کنید، هرگز با ستاره، و پیش از Enter مسیر را دوباره بخوانید.

```bash
rm data/raw/churn.csv
```

```bash
rm -r .dvc/cache
```

```bash
make train
```

انتظار: خطا، چون داده نیست:

```
FileNotFoundError: [Errno 2] No such file or directory: 'data/raw/churn.csv'
make: *** [train] Error 1
```

```bash
uv run dvc status
```

انتظار:

```
data/raw/churn.csv.dvc:
	changed outs:
		not in cache:       data/raw/churn.csv
```

```bash
uv run dvc pull
```

انتظار:

```
A       data/raw/churn.csv
1 file fetched and 1 file added
```

```bash
make train
```

انتظار:

```
{'roc_auc': 0.7493, 'f1': 0.6991}
```

> <bdi dir="rtl">cache پاک‌شده فقط نسخه‌ی ۲ را دوباره گرفت. اگر بعداً دوباره به `data-v1` رفتید و `dvc checkout` خطا داد، بزنید `uv run dvc pull`.</bdi>

### ج) Pull Request و tag

```bash
git push -u origin feature/dvc-data
```

پیش از push، hook مرحله‌ی pre-push تست‌ها را اجرا می‌کند (`pytest ... Passed`). در Gitea Pull Request از `feature/dvc-data` به `main` بسازید. در توضیح بنویسید چه کردید و چرا (DVC، دو نسخه‌ی داده، remote روی SeaweedFS، متریک هر نسخه). چهار commit این جلسه را در صفحه می‌بینید. بعد **Create merge commit** را بزنید.

```bash
git switch main && git pull
```

```bash
git tag -a v0.2.0 -m "Session 4: DVC"
```

<bdi dir="rtl">tagهای داده فقط با `--tags` به Gitea می‌روند:</bdi>

```bash
git push origin --tags
```

انتظار: سه `[new tag]` برای `data-v1`، `data-v2` و `v0.2.0`.

در Gitea بخش Releases/Tags را باز کنید و داخل `data/raw` ببینید: فقط `.gitignore` و `churn.csv.dvc` هست و فایل csv نیست. داده فقط در SeaweedFS است.

---

## بررسی پایان کار

```bash
~/mlops-lab/scripts/verify.sh s04
```

انتظار:

```
[PASS] data/raw/churn.csv.dvc and data/raw/.gitignore are committed; churn.csv itself is NOT in Git
[PASS] dvc[s3]==3.67.1 pinned in pyproject.toml; .dvc/config and uv.lock committed
[PASS] .dvc/config (committed): default remote 'storage' -> s3://dvc/..., with endpointurl
[PASS] keys only in .dvc/config.local (ignored); no secret in tracked files or in Git history
[PASS] tags data-v1 and data-v2 exist, point to different data, and are on Gitea
       data-v1 md5 79921313c42d311a4e6cbd6c828c4839
       data-v2 md5 e0be77bd53ec0f8feda77f6e779c4a3d
[PASS] both data versions (data-v1 and data-v2) exist in the remote 'storage'
[PASS] dvc status: data matches the pointer; dvc status -c: cache and remote are in sync
[PASS] Gitea 'main' contains the pointer of data-v2 and the remote config (PR merged)
[PASS] tag v0.2.0 exists locally and on Gitea
s04: 9/9 checks passed
```

بررسی دستی (اگر خواستید خودتان ببینید):

```bash
git ls-files data
```

```bash
git check-ignore -v data/raw/churn.csv
```

```bash
git grep -n "mlops-lab-secret" || echo "no secret in tracked files"
```

```bash
git tag -n1
```

خروجی `verify.sh` را همراه با تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

### اگر عقب ماندید

- پس از گام ۲ عقب هستید: دو دستور `dvc remote modify --local` و `dvc push` گام ۳ را بزنید و از گام ۴ ادامه دهید.
- پس از گام ۴ عقب هستید: گام ۵ را از `git checkout data-v1` شروع کنید.

### همکار تازه‌وارد (clone تازه)

در یک clone تازه فقط pointer هست. برای گرفتن داده باید رمز محلی بدهید (فایل `.env` در Git نیست و باید خودتان بسازید):

```bash
git clone http://localhost:3000/<نام-کاربری>/churn-mlops.git ~/work/churn-clone && cd ~/work/churn-clone
```

```bash
uv sync
```

```bash
set -a; source .env; set +a
```

```bash
uv run dvc remote modify --local storage access_key_id "$AWS_ACCESS_KEY_ID"
```

```bash
uv run dvc remote modify --local storage secret_access_key "$AWS_SECRET_ACCESS_KEY"
```

```bash
uv run dvc pull
```

بدون دو دستور `--local` خطای `403 Forbidden` می‌گیرید.

## عیب‌یابی

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `ERROR: bad DVC file name ... is git-ignored` | قاعده‌ی `data/` در `.gitignore` جلسه‌ی ۱ | `git check-ignore -v data/raw/churn.csv.dvc`، سپس خط را پاک کنید (گام ۲) |
| `ERROR: failed to initiate DVC ... is not tracked by any supported SCM tool` | داخل مخزن Git نیستید | `cd ~/work/churn-mlops` |
| `ERROR: failed to initiate DVC - '.dvc' exists. Use -f to force` | `dvc init` را دوباره زده‌اید | مشکلی نیست؛ ادامه دهید |
| `docker compose ps` خطا می‌دهد | Docker خاموش است | روی مک `colima start`، بعد `docker compose up -d seaweedfs` |
| `uv add` خطا می‌دهد | اینترنت یا بسته‌ی آفلاین نیست | نسخه را دقیق همین بنویسید: `dvc[s3]==3.67.1` |
| `Forbidden: An error occurred (403) when calling the HeadObject operation` | کلید یا رمز در `.dvc/config.local` نیست یا اشتباه است | `set -a; source .env; set +a` و دو دستور `dvc remote modify --local` را دوباره بزنید |
| `Could not connect to the endpoint URL` | پورت یا نشانی `endpointurl` اشتباه است یا SeaweedFS خاموش است | نشانی در پیام هست؛ `uv run dvc remote modify storage endpointurl "$S3_ENDPOINT_URL"` (بدون `--local`) |
| `no remote specified ... Create a default remote with dvc remote add -d` | remote ساخته نشده یا `-d` را فراموش کرده‌اید | `uv run dvc remote add -d storage s3://dvc/store` |
| hook `block hard-coded secrets` با `Failed` و `.dvc/config:7` | رمز را بدون `--local` نوشته‌اید | `uv run dvc remote modify storage --unset secret_access_key`، دوباره `git add .dvc/config`، رمز را با `--local` بدهید |
| بعد از push چیزی در bucket نیست | `s3 ls` بدون `--recursive` فقط سطح اول را نشان می‌دهد | `s3 ls s3://dvc/ --recursive` |
| `churn.csv` در `git status` دیده می‌شود | فراموش کرده‌اید `data/raw/.gitignore` را add کنید | `git add data/raw/.gitignore` و commit |
| `The following paths are ignored` موقع `git add` | `git add data/raw/churn.csv` زده‌اید | فایل داده را add نکنید؛ pointer را add کنید |
| `dvc status` بعد از `make data` تغییری نشان نمی‌دهد | به‌جای دستور نسخه‌ی ۲ دوباره `make data` زده‌اید (نسخه‌ی ۱ با همان md5 ساخته می‌شود) | `uv run python scripts/make_dataset.py --rows 8000 --drift` |
| commit خالی بعد از ساخت نسخه‌ی ۲ | `dvc add` را فراموش کرده‌اید | `uv run dvc add data/raw/churn.csv`، سپس `git diff` |
| بعداً `dvc pull` برای نسخه‌ی ۲ خطای فایل گمشده می‌دهد | `dvc push` را نزده‌اید | `uv run dvc push` (در bucket باید دو شیء باشد) |
| عددتان با جدول فرق دارد | رشته‌ی فرمان (`rows`، `seed`) را عوض کرده‌اید | md5 خودتان را در دو جا مقایسه کنید، نه عدد جدول |
| `git checkout` به‌خاطر تغییرات commit‌نشده شکایت می‌کند | فایل‌هایتان commit نیست | اول commit یا `git stash` |
| بعد از `git checkout data-v1` متریک هنوز `0.7493` است | `dvc checkout` را نزده‌اید | `uv run dvc checkout` |
| `dvc checkout` خطای `Can't remove the following unsaved files` | فایل داده را دستی عوض کرده و add نکرده‌اید | اگر ارزشی ندارد: `uv run dvc checkout --force` |
| پس از حذف cache، `dvc checkout` برای `data-v1` خطا می‌دهد | cache فقط نسخه‌ی ۲ را دوباره گرفته است | `uv run dvc pull` |
| push رد می‌شود چون pytest در hook شکست خورد | آزمون‌ها سبز نیستند | خروجی را بخوانید و درست کنید؛ `--no-verify` راه‌حل نیست |
| `v0.2.0` روی commit اشتباه خورده | بعد از merge، `git pull` نزده بودید | tag را پاک کنید (`git tag -d v0.2.0`)، `git pull`، دوباره tag بزنید |
| `verify.sh s04`: tag در Gitea نیست | tagها push نشده‌اند | `git push origin --tags` |
| روی detached HEAD تغییری commit کرده‌اید | بعد از `git checkout data-v1` کار کرده‌اید | برای نگه‌داشتن: `git switch -c نام-شاخه`؛ وگرنه رها کنید |

جلسه‌ی بعد روی همین داده و همین remote ساخته می‌شود: SeaweedFS را خاموش نکنید و `docker compose down -v` نزنید.

</div>
