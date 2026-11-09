<div dir="rtl" style="font-family: 'Vazirmatn', 'IRANSansX', Tahoma, sans-serif;">

# آزمایشگاه جلسه‌ی ۳ — مبانی Docker و ذخیره‌ساز شیء (SeaweedFS S3)

در این آزمایشگاه Docker را با دست امتحان می‌کنید (image، container، port، volume)، سرویس SeaweedFS را با Docker Compose روشن می‌کنید، با AWS CLI دو bucket به نام‌های `dvc` و `mlflow` می‌سازید و فایل `churn.csv` را بالا و پایین می‌برید. جلسه‌ی ۴ (DVC) و جلسه‌ی ۶ (MLflow) روی همین انبار کار می‌کنند.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

۱. پروژه‌ی جلسه‌ی ۲ سالم باشد: پوشه‌ی `~/work/churn-mlops`، چهار آزمون سبز، tag نسخه‌ی `v0.1.0` و مخزن روی Gitea.
۲. Docker Desktop (یا Colima) روشن باشد و حافظه‌ی آن دست‌کم ۸ گیگابایت باشد.
۳. مخزن دوره را به‌روز کنید:

```bash
git -C ~/mlops-lab pull
```

۴. فایل `.env` کنار `docker-compose.yml` باشد (در جلسه‌ی ۲ ساخته شد):

```bash
ls ~/mlops-lab/compose/.env
```

انتظار: خود نام فایل چاپ شود. اگر `No such file` دیدید:

```bash
cp ~/mlops-lab/compose/.env.example ~/mlops-lab/compose/.env
```

۵. آماده بودن لپ‌تاپ را بسنجید:

```bash
~/mlops-lab/scripts/preflight.sh s03
```

انتظار: آخرین خط `READY for session 3` باشد. اگر `WARN` درباره‌ی پورت دیدید، یعنی برنامه یا کانتینر دیگری آن پورت را گرفته؛ نام آن در همان خط آمده و باید آن را متوقف کنید. بخش `[Later sessions]` فقط ابزارهای جلسه‌های بعدی را نشان می‌دهد و در نتیجه اثری ندارد. اگر `FAIL` دیدید، راه حل در انتهای همان خط نوشته شده است.

۶. چهار image امروز روی لپ‌تاپ باشد (`seaweedfs`، `gitea`، `nginx` و `python`):

```bash
docker images | grep -E "nginx|python|seaweedfs|gitea"
```

باید `nginx 1.28-alpine` و `python 3.12-slim-bookworm` را هم ببینید. در کلاس اینترنت نیست؛ اگر نبودند از بسته‌ی دوره با `docker load` بارگذاری می‌شوند (مدرس کمک می‌کند).

۷. پورت‌های ۸۳۳۳، ۹۳۳۳، ۸۸۸۸، ۸۰۸۱ و ۸۰۸۲ روی لپ‌تاپ آزاد باشد. پورت ۸۰۸۰ را امروز نمی‌گیریم؛ برای ingress جلسه‌های Kubernetes رزرو است.

گام‌های ۱ تا ۳ به پروژه‌ی `churn-mlops` نیاز ندارند و فقط Docker لازم است. گام‌های ۴ و ۵ داخل `~/work/churn-mlops` اجرا می‌شوند. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell، و پوشه‌ها را داخل فایل‌سیستم WSL (مثل `~/work`) بسازند، نه در `/mnt/c`.

## مفهوم‌ها در یک نگاه

| معنی | واژه |
| --- | --- |
| دستورپخت و مواد یک برنامه؛ فقط‌خواندنی است و عوض نمی‌شود | image |
| جعبه‌ای که از روی یک image روشن شده و کار می‌کند؛ با `rm` از بین می‌رود | container |
| `-p 8081:80` یعنی پورت ۸۰۸۱ لپ‌تاپ به پورت ۸۰ داخل کانتینر وصل شود؛ چپ همیشه لپ‌تاپ است، راست کانتینر | port mapping |
| نشان دادن یک پوشه‌ی لپ‌تاپ داخل کانتینر؛ با `:ro` فقط خواندنی است | bind mount |
| قمقمه‌ی جدای Docker برای داده؛ با حذف کانتینر نمی‌رود | volume |
| فایل `docker-compose.yml` مثل برگه‌ی سفارش است: چه image، کدام پورت، کدام volume | Docker Compose |
| انبار شیء: هر فایل یک «شیء» با یک «کلید» است، داخل یک bucket | S3 |
| بالاترین سطح پوشه در S3؛ ما دو تا می‌سازیم: `dvc` و `mlflow` | bucket |
| نشانی انبار؛ برای ما `http://localhost:8333` (`--endpoint-url`) | endpoint |
| اثر انگشت فایل؛ دو فایل با اثر انگشت یکسان یک فایل‌اند | checksum |

سه پورت SeaweedFS: ۸۳۳۳ برای S3، ۹۳۳۳ صفحه‌ی مدیریتی Master، ۸۸۸۸ صفحه‌ی Filer.

## نتیجه‌ی نهایی

- SeaweedFS در وضعیت `healthy` و پورت ۸۳۳۳ پاسخ‌گو
- دو bucket به نام `dvc` و `mlflow`
- فایل `churn.csv` بالا رفته و برگشته، با checksum یکسان
- داده بعد از `docker compose down` و `up` هنوز هست
- فایل `.env.example` در Git، فایل `.env` بیرون از Git، و یک Pull Request ادغام‌شده

## فایل‌های این پوشه

این جلسه فایل آماده‌ای برای کپی ندارد؛ همه‌چیز را خودتان می‌سازید. تنها فایل تازه‌ی پروژه `.env.example` است که در گام ۴ می‌نویسید.

| کار | کجا | فایل |
| --- | --- | --- |
| سرویس SeaweedFS (از قبل هست؛ تغییرش ندهید) | `~/mlops-lab/compose/` | `docker-compose.yml` |
| نمونه‌ی تنظیمات S3 با `CHANGE_ME`؛ در Git می‌رود | ریشه‌ی `~/work/churn-mlops` | `.env.example` |
| تنظیمات واقعی با کلید؛ هرگز در Git نمی‌رود | ریشه‌ی `~/work/churn-mlops` | `.env` |

---

## گام ۱ — اولین کانتینرها (۱۲ دقیقه)

اول بسنجید Docker روشن است و نسخه‌ها را ببینید:

```bash
docker version -f '{{.Server.Version}}'
```

```bash
docker compose version
```

```bash
docker images
```

پایتونی که داخل کانتینر چاپ می‌شود با پایتون لپ‌تاپ شما جداست؛ یعنی محیط ایزوله:

```bash
docker run --rm python:3.12-slim-bookworm python -c "import sys; print(sys.version)"
```

انتظار (نسخه‌ی دقیق ممکن است کمی فرق کند):

```
3.12.15 (main, Oct  6 2026, 02:08:14) [GCC 12.2.0]
```

یک وب‌سرور nginx روشن کنید. `-d` یعنی در پس‌زمینه، `--name web` یعنی نام کانتینر `web` باشد:

```bash
docker run -d --name web -p 8081:80 nginx:1.28-alpine
```

انتظار: یک شناسه‌ی طولانی چاپ می‌شود.

```bash
docker ps
```

انتظار: خط `web` با `Up ... seconds` و ستون `PORTS` که `8081->80/tcp` دارد.

```bash
curl -sI localhost:8081 | head -1
```

انتظار:

```
HTTP/1.1 200 OK
```

(اگر `curl` ندارید، `http://localhost:8081` را در مرورگر باز کنید.)

لاگ و اجرای یک دستور داخل کانتینر:

```bash
docker logs web
```

```bash
docker exec web nginx -v
```

انتظار: `nginx version: nginx/1.28.3`

حالا کانتینر را متوقف و بعد حذف کنید و بعد از هر کدام فهرست را ببینید:

```bash
docker stop web
```

```bash
docker ps -a
```

انتظار: کانتینر `web` با وضعیت `Exited (0)` هنوز در فهرست است. `stop` یعنی خاموش کردن، نه پاک کردن.

```bash
docker rm web
```

```bash
docker ps -a
```

انتظار: فهرست خالی است (فقط سطر عنوان‌ها).

> برای `stop` و `rm` همیشه نام کامل کانتینر را بنویسید. Docker پیشوند شناسه را هم می‌پذیرد و یک حرف ممکن است کانتینر دیگری را پاک کند.

## گام ۲ — آزمایش پورت و volume (۱۳ دقیقه)

### الف) دو کانتینر روی یک پورت

پورت لپ‌تاپ مثل شماره‌ی تلفن است: دو نفر نمی‌توانند یک شماره را داشته باشند.

```bash
docker run -d --name web1 -p 8081:80 nginx:1.28-alpine
```

```bash
docker run -d --name web2 -p 8081:80 nginx:1.28-alpine
```

انتظار: خطای `Bind for 0.0.0.0:8081 failed: port is already allocated`. این خطا درست و مورد انتظار است.

```bash
docker run -d --name web3 -p 8082:80 nginx:1.28-alpine
```

```bash
docker ps -a
```

انتظار: `web1` و `web3` با `Up` و `web2` با وضعیت `Created`. کانتینر `web2` با وجود خطا باقی مانده و باید پاک شود:

```bash
docker rm -f web1 web2 web3
```

### ب) bind mount

یک صفحه‌ی ساده روی لپ‌تاپ بسازید:

```bash
mkdir -p ~/work/s03 && cd ~/work/s03 && mkdir site
```

```bash
echo '<h1>hello</h1>' > site/index.html
```

پوشه‌ی `site` را فقط‌خواندنی (`:ro`) داخل nginx بگذارید. مسیر باید مطلق باشد، به همین دلیل `$PWD` نوشته شده است:

```bash
docker run -d --name demo2 -p 8081:80 \
    -v "$PWD/site:/usr/share/nginx/html:ro" nginx:1.28-alpine
```

```bash
curl -s localhost:8081
```

انتظار: `<h1>hello</h1>` (همان فایل لپ‌تاپ شما). در مرورگر هم `http://localhost:8081` را باز کنید.

حالا بخواهید داخل کانتینر چیزی بنویسید:

```bash
docker exec demo2 sh -c 'echo x > /usr/share/nginx/html/new.txt'
```

انتظار:

```
sh: can't create /usr/share/nginx/html/new.txt: Read-only file system
```

```bash
docker rm -f demo2
```

### پ) داده با volume و بدون volume

کانتینر مثل لیوان یک‌بارمصرف است؛ هرچه داخلش بریزید با `rm` می‌رود. اول بدون volume (نام را دقیقاً `demo1` بگذارید):

```bash
docker run --name demo1 python:3.12-slim-bookworm \
    sh -c 'mkdir -p /data && echo run-1 > /data/note.txt'
```

```bash
docker rm demo1
```

```bash
docker run --rm python:3.12-slim-bookworm cat /data/note.txt
```

انتظار:

```
cat: /data/note.txt: No such file or directory
```

داده با کانتینر رفت. حالا با volume (قمقمه‌ی جدا):

```bash
docker volume create notes
```

```bash
docker run --rm -v notes:/data python:3.12-slim-bookworm \
    sh -c 'echo run-1 > /data/note.txt'
```

```bash
docker run --rm -v notes:/data python:3.12-slim-bookworm cat /data/note.txt
```

انتظار: `run-1`. کانتینرها هر دو پاک شده‌اند ولی داده مانده است.

```bash
docker volume ls
```

انتظار: یک volume به نام `notes` با `DRIVER` برابر `local` (اگر volumeهای `mlops-lab_...` هم هست، به آن‌ها دست نزنید).

```bash
docker volume rm notes
```

همین دلیل است که داده‌ی SeaweedFS و Gitea روی volume است، نه داخل کانتینر.

## گام ۳ — SeaweedFS با Compose (۱۲ دقیقه)

دیروز Gitea را با یک دستور بالا آوردیم؛ امروز همان دستور را برای انبار فایل می‌زنیم. همیشه نام سرویس را بنویسید؛ `docker compose up` بدون نام همه‌ی سرویس‌ها از جمله MLflow را بالا می‌آورد که هنوز لازم نیست و حافظه می‌خورد.

```bash
cd ~/mlops-lab/compose
```

```bash
docker compose up -d seaweedfs
```

انتظار: چهار خط `Creating`، `Created`، `Starting`، `Started` برای `seaweedfs`.

```bash
docker compose ps
```

بعد از حدود ۱۰ تا ۱۵ ثانیه ستون `STATUS` باید `Up ... (healthy)` شود. اگر هنوز `healthy` نیست ۳۰ ثانیه صبر کنید و دوباره بزنید.

```bash
docker compose logs --tail 60 seaweedfs | grep S3
```

انتظار: خطی که `Start Seaweed S3 API Server` و `at http port 8333` دارد. ممکن است یک خط خطا درباره‌ی `Failed to load IAM configuration` هم ببینید؛ برای این آزمایشگاه بی‌اثر است و S3 با کلیدهای ما کار می‌کند.

```bash
curl -s localhost:9333/cluster/status
```

انتظار:

```
{"IsLeader":true,"Leader":"seaweedfs:9333.19333"}
```

```bash
curl -s -o /dev/null -w '%{http_code}\n' localhost:8333
```

انتظار: `403`. این عدد خطا نیست؛ یعنی S3 بالاست و بدون کلید اجازه نمی‌دهد. خطا آن وقت است که اصلاً جواب نگیرید.

در مرورگر `http://localhost:9333` را باز کنید؛ صفحه‌ی Master باید `Leader` را پر نشان بدهد.

## گام ۴ — S3 با AWS CLI (۱۶ دقیقه)

همه‌ی دستورهای این گام داخل پروژه‌ی خودتان اجرا می‌شوند. اول شاخه‌ی تازه:

```bash
cd ~/work/churn-mlops && git switch -c feature/s3-storage
```

فایل `.env.example` را با ویرایشگر (`code .env.example` یا `nano`) بسازید. دقیقاً همین پنج خط، با `CHANGE_ME` (کلید واقعی اینجا ننویسید):

```text
# Copy to .env  - never commit .env
S3_ENDPOINT_URL=http://localhost:8333
AWS_ACCESS_KEY_ID=CHANGE_ME
AWS_SECRET_ACCESS_KEY=CHANGE_ME
AWS_DEFAULT_REGION=us-east-1
```

نام فایل دقیقاً `.env.example` است. فایل `.env.example` فقط یک نمونه است و در Git می‌رود. فایل `.env` واقعی با کلید است و هرگز commit نمی‌شود (از جلسه‌ی ۱ در `.gitignore` هست).

```bash
cp .env.example .env
```

حالا با ویرایشگر فایل `.env` را باز کنید و دو مقدار `CHANGE_ME` را با `S3_ACCESS_KEY` و `S3_SECRET_KEY` از فایل `~/mlops-lab/compose/.env` جایگزین کنید. این‌ها کلیدهای آزمایشگاهی‌اند. بعد از ذخیره، دقت کنید فاصله یا خط اضافه در انتهای مقدارها نیامده باشد.

ابزار AWS CLI را به‌عنوان وابستگی توسعه‌ی پروژه اضافه کنید (نسخه‌ی ثابت دوره):

```bash
uv add --dev awscli==1.46.1
```

```bash
uv run aws --version
```

انتظار: خطی که با `aws-cli/1.46.1` شروع می‌شود. در `uv run` ممکن است پیام‌های `Building churn` یا `Installed 1 package` ببینید؛ طبیعی است.

متغیرهای `.env` را در این ترمینال بارگذاری و یک میان‌بر به نام `s3` تعریف کنید. `--endpoint-url` همان نشانی انبار ماست؛ اگر ننویسید AWS CLI سراغ Amazon می‌رود، نه SeaweedFS ما:

```bash
set -a; source .env; set +a
```

```bash
s3() { uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 "$@"; }
```

> تابع `s3` با بستن ترمینال از بین می‌رود. در ترمینال تازه دو دستور بالا را دوباره بزنید.

```bash
s3 ls
```

انتظار: چیزی چاپ نمی‌شود (فهرست اول خالی است).

دو bucket بسازید. نام را کپی کنید، تایپ نکنید؛ غلط تایپی در SeaweedFS بی‌صدا یک bucket تازه می‌سازد:

```bash
s3 mb s3://dvc && s3 mb s3://mlflow
```

انتظار:

```
make_bucket: dvc
make_bucket: mlflow
```

```bash
s3 ls
```

انتظار (زمان‌ها فرق می‌کند):

```
2026-10-15 20:34:54 dvc
2026-10-15 20:34:55 mlflow
```

اگر فایل `data/raw/churn.csv` ندارید اول آن را بسازید (اگر دارید، این دستور لازم نیست):

```bash
make data
```

انتظار: خطی که با `wrote 5000 rows` شروع می‌شود.

فایل را بالا ببرید و فهرست کنید:

```bash
s3 cp data/raw/churn.csv s3://dvc/raw/churn.csv
```

```bash
s3 ls s3://dvc/ --recursive
```

انتظار (اندازه و زمان در سیستم شما ممکن است فرق کند؛ در آزمایش مدرس ۲۰۱۲۰۲ بایت بود):

```
2026-10-15 20:35:00     201202 raw/churn.csv
```

فایل را پایین بیاورید و با checksum ثابت کنید سالم برگشته. فایل پایین‌آمده را بیرون از پروژه (در `~/work`) می‌گذاریم تا وارد Git نشود:

```bash
s3 cp s3://dvc/raw/churn.csv ../churn-copy.csv
```

```bash
shasum -a 256 data/raw/churn.csv ../churn-copy.csv
```

(در لینوکس و WSL اگر `shasum` نبود، `sha256sum` را بزنید.) انتظار: دو سطر که رشته‌ی hash در هر دو دقیقاً یکی است. مقدار hash به داده‌ی شما بستگی دارد؛ مهم یکسان بودن است.

در مرورگر `http://localhost:8888/buckets/` (صفحه‌ی Filer) را باز کنید؛ همان دو bucket را می‌بینید. یعنی همان شیء را از دو راه دیدیم.

## گام ۵ — ماندگاری، نظافت و Pull Request (۲۰ دقیقه)

۵ دقیقه‌ی آخر همین گام «بررسی پایان کار» است.

### الف) داده بعد از down و up می‌ماند

```bash
cd ~/mlops-lab/compose
```

```bash
docker compose down
```

```bash
docker volume ls
```

انتظار: کانتینرها و شبکه‌ی `mlops-lab` پاک می‌شوند ولی دو volume مانده‌اند:

```
mlops-lab_gitea-data
mlops-lab_seaweedfs-data
```

> هرگز `docker compose down -v` نزنید. گزینه‌ی `-v` volumeها را هم پاک می‌کند، یعنی هم داده‌ی SeaweedFS و هم مخزن‌های Gitea جلسه‌ی ۲.

```bash
docker compose up -d seaweedfs gitea
```

```bash
docker compose ps
```

انتظار: هر دو سرویس `Up` و `seaweedfs` بعد از چند ثانیه `(healthy)`. صبر کنید `healthy` شود؛ در غیر این صورت دستور بعد خطای اتصال می‌دهد.

```bash
cd ~/work/churn-mlops
```

```bash
set -a; source .env; set +a
```

```bash
s3() { uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 "$@"; }
```

```bash
s3 ls s3://dvc/ --recursive
```

انتظار: همان `raw/churn.csv` با همان اندازه برگشته است. داده ماند، چون volume هرگز پاک نشد.

### ب) نظافت Git

```bash
git status --short
```

انتظار: فایل `.env` در فهرست نیست؛ فقط `pyproject.toml`، `uv.lock` و `.env.example` (با علامت `??`) را می‌بینید.

اختیاری (۲ دقیقه) برای دیدن نگهبان: یک نسخه‌ی سالم از `.env.example` کنار بگذارید، کلید واقعی را در آن بریزید و commit کنید.

```bash
cp .env.example ~/work/env.example.good
```

```bash
cp .env .env.example
```

```bash
git add .env.example && git commit -m 'chore: add env example'
```

انتظار: hook جلوی commit را می‌گیرد؛ در خروجی `block hard-coded secrets` با `Failed` و بعد نام فایل و شماره‌ی خط می‌آید. (هشدار `Unstaged files detected` عادی است.) حالا فایل را برگردانید و stage را پاک کنید:

```bash
cp ~/work/env.example.good .env.example
```

```bash
git reset
```

```bash
rm ~/work/env.example.good
```

مطمئن شوید `.env.example` دوباره `CHANGE_ME` دارد:

```bash
grep -c CHANGE_ME .env.example
```

انتظار: `2`

### پ) commit و push

```bash
git add .env.example pyproject.toml uv.lock
```

```bash
git commit -m "chore: add S3 env example and awscli"
```

انتظار: در خروجی hook با نام `block hard-coded secrets` برابر `Passed` است.

```bash
git push -u origin feature/s3-storage
```

انتظار: قبل از push آزمون‌ها اجرا می‌شوند (بار اول تا ۳۰ ثانیه) و در پایان خطی مثل `Create a new pull request for 'feature/s3-storage'` با نشانی Gitea می‌آید.

### ت) Pull Request در Gitea

در `http://localhost:3000` از شاخه‌ی `feature/s3-storage` به `main` یک Pull Request بسازید. باید سه فایل تغییر کرده باشد و در `.env.example` فقط مقدارهای `CHANGE_ME` دیده شود. عنوان و توضیح بنویسید (چه چیزی و چرا). با جفت‌کار خود همدیگر را بازبینی کنید، بعد با گزینه‌ی Create merge commit و تیک Delete Branch ادغام کنید. سپس روی لپ‌تاپ:

```bash
git switch main && git pull
```

```bash
git branch -d feature/s3-storage
```

---

## بررسی پایان کار

دستور زیر داخل `~/work/churn-mlops` اجرا شود. SeaweedFS باید روشن باشد (`docker compose ps` در پوشه‌ی `compose`).

```bash
~/mlops-lab/scripts/verify.sh s03
```

انتظار (اندازه‌ی `churn.csv` در سیستم شما فرق دارد):

```
[PASS] Docker engine and Compose v2 answer
[PASS] SeaweedFS S3 answers at http://localhost:8333
[PASS] .env exists and holds real lab keys (not CHANGE_ME)
[PASS] awscli pinned in pyproject.toml; pyproject.toml and uv.lock tracked
[PASS] buckets dvc and mlflow exist
[PASS] s3://dvc/raw/churn.csv exists and its size equals data/raw/churn.csv
       churn.csv in S3: 201202 bytes
[PASS] .env.example is tracked (CHANGE_ME), .env is NOT tracked and is ignored
[PASS] the lab secret is in no tracked file and in no commit
[PASS] Pull Request merged: local main == origin main (Gitea) and has .env.example
s03: 9/9 checks passed   (commit ..., branch main)
```

خروجی را به‌همراه خروجی `git rev-parse --short HEAD` و تکلیف برای مدرس بفرستید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

## عیب‌یابی

| راه‌حل | علت | نشانه |
| --- | --- | --- |
| Docker Desktop را باز کنید (یا `colima start`) و `docker ps` را دوباره بزنید | Docker روشن نیست | `failed to connect to the docker API ... is the daemon running` |
| `docker ps`؛ کانتینر قبلی را با نام کامل حذف کنید یا پورت ۸۰۸۲ بدهید | پورت ۸۰۸۱ را کانتینر یا برنامه‌ی دیگری گرفته | `Bind for 0.0.0.0:8081 failed: port is already allocated` |
| `docker rm web` (نام کامل) | کانتینری با همین نام هست | `Conflict. The container name "/web" is already in use` |
| با `docker images` مقایسه کنید؛ از بسته‌ی دوره `docker load` کنید | نام یا tag اشتباه است یا image بارگذاری نشده | `Unable to find image ... locally` |
| `http://localhost:8081` را در مرورگر باز کنید | WSL بدون curl | `curl` در Windows نیست |
| `"$PWD/site:..."` را بنویسید | Docker مسیر مطلق می‌خواهد | مسیر `site` نسبی داده شد و کار نکرد |
| `cd ~/mlops-lab/compose` | داخل پوشه‌ی `compose` نیستید | `no configuration file provided: not found` |
| `lsof -i :8333` (در لینوکس `ss -ltnp`) | برنامه‌ی دیگری (مثل MinIO یا SeaweedFS قدیمی) پورت را گرفته | `port is already allocated` برای ۸۳۳۳، ۹۳۳۳ یا ۸۸۸۸ |
| ۳۰ ثانیه صبر کنید، بعد `docker compose logs seaweedfs` | SeaweedFS هنوز بالا نیامده | وضعیت مدتی `Up` است ولی `healthy` نمی‌شود |
| `docker compose stop gitea` موقتاً؛ حافظه‌ی Docker را ۸ گیگابایت کنید | SeaweedFS حدود ۱۵۰ مگابایت می‌گیرد | حافظه کم است |
| `set -a; source .env; set +a` و تعریف دوباره‌ی تابع `s3` | `.env` را source نکرده‌اید یا ترمینال تازه است | `Unable to locate credentials` |
| با `~/mlops-lab/compose/.env` مقایسه کنید | secret اشتباه است (غلط املایی، فاصله یا خط اضافه) | `SignatureDoesNotMatch` |
| همان مقایسه | key اشتباه است | `InvalidAccessKeyId` |
| `docker compose ps`؛ نشانی باید `http` (نه `https`) و پورت ۸۳۳۳ باشد | SeaweedFS بالا نیست یا نشانی غلط است | `Could not connect to the endpoint URL` |
| `s3 mb s3://dvc` | `mb` را نزده‌اید | `NoSuchBucket` |
| مشکلی نیست | bucket از قبل هست | `BucketAlreadyOwnedByYou` |
| نام bucket اضافه را به مدرس نشان دهید تا با هم پاکش کنید؛ دفعه‌ی بعد نام را کپی کنید | نام را اشتباه تایپ کرده‌اید و `cp` موفق شده (SeaweedFS خطا نمی‌دهد) | `s3 ls` یک bucket اضافه نشان می‌دهد |
| `uv sync` را بزنید و به مدرس خبر بدهید | اینترنت یا بسته‌ی آفلاین نیست | `uv add` خطا می‌دهد |
| `sha256sum` به‌جای آن | لینوکس | `shasum: command not found` |
| `git check-ignore -v .env` باید خط `.gitignore` را نشان دهد | نام فایل اشتباه است یا در `.gitignore` نیست | فایل `.env` در `git status` دیده می‌شود |
| `git restore --staged .env` | `git add .` | فایل `.env` تصادفاً stage شده |
| مقدارها را به `CHANGE_ME` برگردانید و دوباره `git add` | کلید واقعی در `.env.example` است | commit رد می‌شود (`block hard-coded secrets` برابر `Failed`) |
| `uv run pytest -q` و خطا را رفع کنید | پیام را بخوانید؛ معمولاً `pytest` | push رد می‌شود (`non-fast-forward` یا شکست آزمون) |
| نام کاربری `student` است، نه ایمیل | نام کاربری Gitea | `Authentication failed` در push |
| PR را ادغام کنید، بعد `git switch main && git pull` | PR هنوز ادغام نشده یا `git pull` نزده‌اید | `verify.sh s03` می‌گوید `local main == origin main` شکست خورده |
| پوشه‌ی `~/work/churn-mlops` سالم است؛ به مدرس بگویید تا مخزن Gitea را دوباره بسازید و گام ۴ را برای پر کردن SeaweedFS تکرار کنید | گزینه‌ی `-v` volumeها را پاک کرد | بعد از `down -v` همه‌چیز رفت |

برای جلسه‌ی بعد SeaweedFS و bucketها را نگه دارید (`docker compose down -v` نزنید). جلسه‌ی ۴ با DVC روی همین bucket `dvc` کار می‌کند.

</div>
