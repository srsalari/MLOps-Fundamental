# راهنمای سرویس‌های آزمایشگاه

این پوشه سه سرویس اصلی دوره را با **Docker Compose** بالا می‌آورد: SeaweedFS (ذخیره‌ساز S3)، MLflow و Gitea. سرویس چهارم یعنی Gitea runner فقط در جلسه‌ی ۱۳ روشن می‌شود. همه‌ی تنظیمات در فایل `docker-compose.yml` است و توضیح انگلیسی هر بخش داخل خود فایل به‌صورت comment آمده است.

## فایل‌های این پوشه

| مسیر | کار آن | جلسه |
|---|---|---|
| `docker-compose.yml` | تعریف سرویس‌ها، پورت‌ها، volumeها و شبکه | ۲ تا ۱۳ |
| `.env.example` | الگوی کلیدهای آزمایشگاه؛ آن را به `.env` کپی می‌کنید | ۳ به بعد |
| `seaweedfs/s3.json` | کاربر و کلیدهای S3 | ۳ تا ۷ |
| `mlflow/Dockerfile` | ساخت image سرور MLflow | ۶ تا ۸ |
| `gitea-runner/config.yaml` | تنظیمات runner برای CI | ۱۳ |

## شروع، توقف و بررسی

فقط یک بار کلیدها را از الگو بسازید:

```bash
cp .env.example .env
```

همه‌ی سرویس‌های اصلی را روشن کنید:

```bash
docker compose up -d
```

وضعیت سرویس‌ها را ببینید (ستون STATUS باید `Up` و برای SeaweedFS `healthy` باشد):

```bash
docker compose ps
```

لاگ یک سرویس را ببینید (با `Ctrl+C` خارج می‌شوید):

```bash
docker compose logs -f mlflow
```

سرویس‌ها را بدون پاک شدن داده خاموش کنید:

```bash
docker compose down
```

> **هشدار مهم:** در کلاس هرگز `docker compose down -v` اجرا نکنید. گزینه‌ی `-v` همه‌ی volumeها را پاک می‌کند. یعنی تمام مخزن‌ها و کاربران Gitea و تمام runها و مدل‌های MLflow و همه‌ی فایل‌های SeaweedFS از بین می‌روند و برگشتی ندارد. دستور `docker compose down` بدون `-v` امن است.

## فایل `.env` و کلیدهایش

فایل `.env` در Git نیست (gitignore شده) و فقط روی لپ‌تاپ شما می‌ماند. کلیدهای آن مخصوص آزمایشگاه است و جای دیگری استفاده نمی‌شود.

```bash
S3_ACCESS_KEY=mlops-lab-key
S3_SECRET_KEY=mlops-lab-secret-change-me
RUNNER_TOKEN=
```

- مقدار `S3_ACCESS_KEY` و `S3_SECRET_KEY` باید دقیقاً با `seaweedfs/s3.json` یکی باشد. MLflow با همین دو کلید به SeaweedFS وصل می‌شود.
- مقدار `RUNNER_TOKEN` در جلسه‌ی ۱۳ از رابط Gitea ساخته می‌شود و تا آن موقع خالی می‌ماند.
- نسخه‌ی imageها را می‌شود با متغیرهایی مثل `SEAWEEDFS_IMAGE`، `MLFLOW_SERVER_IMAGE`، `GITEA_IMAGE` و `ACT_RUNNER_IMAGE` عوض کرد. اگر تعریف نشوند، نسخه‌ی پین‌شده‌ی داخل compose استفاده می‌شود.

## سرویس seaweedfs (جلسه‌های ۳ تا ۷)

ذخیره‌ساز SeaweedFS یک شیء سازگار با S3 است. داده‌ی DVC (bucket به نام `dvc`) و artifactهای MLflow (bucket به نام `mlflow`) اینجا نگهداری می‌شوند.

```yaml
image: ${SEAWEEDFS_IMAGE:-chrislusf/seaweedfs:4.45}
command: >
  server -dir=/data -ip=seaweedfs -ip.bind=0.0.0.0
  -master.volumeSizeLimitMB=1024 -volume.max=50
  -s3 -s3.port=8333 -s3.config=/etc/seaweedfs/s3.json
```

- دستور `server` همه‌ی بخش‌های SeaweedFS (master، volume، filer و S3) را در یک process اجرا می‌کند؛ برای لپ‌تاپ ساده‌ترین حالت است.
- گزینه‌های `-master.volumeSizeLimitMB=1024` و `-volume.max=50` حجم هر volume را کوچک نگه می‌دارند تا دیسک لپ‌تاپ از قبل اشغال نشود.
- گزینه‌ی `-s3.config` فایل کاربران را به SeaweedFS می‌دهد.

پورت‌ها (همه فقط روی `127.0.0.1` باز هستند، یعنی از شبکه‌ی کلاس قابل دسترسی نیستند):

| پورت | کاربرد |
|---|---|
| `8333` | S3 API؛ ابزارهای DVC و MLflow به این پورت وصل می‌شوند |
| `9333` | رابط وب master برای دیدن وضعیت خوشه |
| `8888` | رابط وب filer برای دیدن فایل‌ها و bucketها |

حجم‌ها (volumes): `seaweedfs-data` برای ماندگاری داده‌ها، و فایل `s3.json` که فقط‌خواندنی (`:ro`) mount می‌شود.

```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -q -O /dev/null http://localhost:9333/cluster/status || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 12
```

بررسی سلامت (healthcheck) هر ۱۰ ثانیه از master می‌پرسد زنده است یا نه. تا ۱۲ بار شکست را تحمل می‌کند (حدود دو دقیقه). سرویس MLflow تا `healthy` شدن SeaweedFS شروع نمی‌شود. گزینه‌ی `restart: unless-stopped` باعث می‌شود بعد از ریبوت لپ‌تاپ دوباره بالا بیاید، مگر خودتان آن را متوقف کرده باشید.

## فایل `seaweedfs/s3.json`

فایل JSON کامنت ندارد، پس توضیح آن اینجاست. این فایل می‌گوید چه کسی اجازه‌ی استفاده از S3 را دارد:

```json
{
  "identities": [
    {
      "name": "mlops-lab",
      "credentials": [
        { "accessKey": "mlops-lab-key", "secretKey": "mlops-lab-secret-change-me" }
      ],
      "actions": ["Admin", "Read", "Write", "List", "Tagging"]
    }
  ]
}
```

- بخش `identities` فهرست کاربران S3 است. در آزمایشگاه فقط یک کاربر داریم.
- مقدار `name` فقط یک نام توصیفی است.
- بخش `credentials` جفت کلید است: `accessKey` مثل نام کاربری و `secretKey` مثل رمز عبور. این دو باید با `S3_ACCESS_KEY` و `S3_SECRET_KEY` در `.env` برابر باشند، وگرنه خطای دسترسی (Access Denied) می‌گیرید.
- بخش `actions` اجازه‌ها را مشخص می‌کند: `Admin` (ساخت و حذف bucket)، `Read`، `Write`، `List` و `Tagging`.
- این کلیدها فقط برای کلاس هستند. در هر محیط واقعی حتماً عوضشان کنید (نام secret هم به همین دلیل `change-me` دارد).

## سرویس mlflow (جلسه‌های ۶ تا ۸)

سرور MLflow runها، پارامترها، متریک‌ها و Model Registry را نگه می‌دارد.

```yaml
build:
  context: ./mlflow
  args:
    MLFLOW_VERSION: "3.17.2"
    BOTO3_VERSION: "1.43.95"
depends_on:
  seaweedfs:
    condition: service_healthy
```

- ساخت image از روی `mlflow/Dockerfile` ساخته می‌شود و نسخه‌ها پین‌شده‌اند تا همه‌ی دانشجوها یک نسخه داشته باشند.
- بخش `depends_on` با شرط `service_healthy` یعنی MLflow بعد از آماده شدن SeaweedFS شروع می‌شود.

متغیرهای محیطی:

```yaml
environment:
  MLFLOW_S3_ENDPOINT_URL: http://seaweedfs:8333
  AWS_ACCESS_KEY_ID: ${S3_ACCESS_KEY}
  AWS_SECRET_ACCESS_KEY: ${S3_SECRET_KEY}
  AWS_DEFAULT_REGION: us-east-1
```

کتابخانه‌ی boto3 داخل MLflow این چهار متغیر را می‌خواند تا به‌جای AWS به SeaweedFS وصل شود. نشانی `seaweedfs:8333` فقط داخل شبکه‌ی Docker معنی دارد. مقدار region بی‌اثر است ولی boto3 وجودش را لازم دارد.

```yaml
command: >
  mlflow server --host 0.0.0.0 --port 5000
  --backend-store-uri sqlite:////mlflow/mlflow.db
  --artifacts-destination s3://mlflow/
  --serve-artifacts
  --allowed-hosts localhost,localhost:5050,127.0.0.1,127.0.0.1:5050,mlflow,mlflow:5000
```

- گزینه‌ی `--backend-store-uri` اطلاعات runها را در یک فایل SQLite می‌گذارد (برای کلاس کافی و ساده است).
- گزینه‌ی `--artifacts-destination` فایل‌های مدل و نمودارها را به bucket به نام `mlflow` در SeaweedFS می‌فرستد.
- گزینه‌ی `--serve-artifacts` یعنی خود سرور MLflow آپلود و دانلود artifact را واسطه‌گری می‌کند (proxied artifacts). به همین دلیل کد دانشجو فقط آدرس `http://localhost:5050` را می‌شناسد و به کلید S3 نیاز ندارد.
- گزینه‌ی `--allowed-hosts` در MLflow 3 لازم است: درخواستی که هدر Host آن در این فهرست نباشد رد می‌شود. شما با `localhost:5050` وصل می‌شوید و containerهای دیگر با `mlflow:5000`.

پورت: `127.0.0.1:5050:5000` یعنی پورت `5050` لپ‌تاپ به پورت `5000` داخل container وصل است. پورت `5000` روی macOS اغلب توسط AirPlay اشغال است، برای همین `5050` را انتخاب کرده‌ایم.

حجم (volume): `mlflow-db` پوشه‌ی `/mlflow` را نگه می‌دارد که فایل `mlflow.db` داخل آن است.

## فایل `mlflow/Dockerfile`

```dockerfile
FROM ${PYTHON_BASE_IMAGE}
ARG MLFLOW_VERSION=3.17.2
ARG BOTO3_VERSION=1.43.95
RUN pip install --no-cache-dir "mlflow==${MLFLOW_VERSION}" "boto3==${BOTO3_VERSION}" \
 && useradd --uid 1000 --create-home mlflow && mkdir /mlflow && chown mlflow /mlflow
USER mlflow
WORKDIR /mlflow
EXPOSE 5000
```

- پایه‌ی image همان `python:3.12-slim-bookworm` است (کوچک و سبک).
- ساخت image فقط `mlflow` و `boto3` را با نسخه‌ی دقیق نصب می‌کند. boto3 همان کتابخانه‌ای است که با S3 حرف می‌زند.
- سپس کاربر معمولی `mlflow` با شناسه‌ی ۱۰۰۰ ساخته می‌شود تا سرور با دسترسی root اجرا نشود.
- دستور `EXPOSE 5000` فقط مستندات است؛ باز شدن پورت واقعی در compose انجام می‌شود.
- اگر اینترنت ندارید، متغیرهای `PIP_INDEX_URL` یا `PIP_FIND_LINKS` می‌توانند pip را به mirror کلاس یا یک wheelhouse محلی ببرند.

## سرویس gitea (از جلسه‌ی ۲)

سرویس Gitea سرور Git محلی دوره است و CI (Gitea Actions) هم روی آن اجرا می‌شود.

```yaml
environment:
  GITEA__database__DB_TYPE: sqlite3
  GITEA__server__ROOT_URL: http://localhost:3000/
  GITEA__server__SSH_PORT: "2222"
  GITEA__security__INSTALL_LOCK: "true"
  GITEA__service__DISABLE_REGISTRATION: "true"
  GITEA__actions__ENABLED: "true"
  GITEA__actions__DEFAULT_ACTIONS_URL: self
```

نام هر متغیر به شکل `GITEA__بخش__کلید` است و معادل یک خط در فایل `app.ini` است.

- مقدار `sqlite3` یعنی به یک container دیتابیس جدا نیازی نیست.
- مقدار `ROOT_URL` در لینک‌های clone و صفحه‌های وب استفاده می‌شود.
- مقدار `INSTALL_LOCK` ویزارد نصب اولیه را رد می‌کند.
- مقدار `DISABLE_REGISTRATION` ثبت‌نام آزاد را می‌بندد؛ کاربران را مدرس می‌سازد.
- مقدار `DEFAULT_ACTIONS_URL: self` یعنی actionها از خود Gitea گرفته شوند و به github.com درخواستی نرود (محیط offline).

پورت‌ها: `3000` برای وب و Git روی HTTP، و `2222` برای Git روی SSH (به پورت ۲۲ داخل container وصل است؛ پورت ۲۲ خود لپ‌تاپ آزاد می‌ماند). volume با نام `gitea-data` مخزن‌ها، کاربران و دیتابیس را نگه می‌دارد.

## سرویس gitea-runner (جلسه‌ی ۱۳)

```yaml
profiles: ["ci"]
depends_on: [gitea]
environment:
  CONFIG_FILE: /config.yaml
  GITEA_INSTANCE_URL: http://gitea:3000
  GITEA_RUNNER_REGISTRATION_TOKEN: ${RUNNER_TOKEN}
  GITEA_RUNNER_NAME: laptop-runner
```

- بخش `profiles: ["ci"]` یعنی این سرویس با `docker compose up -d` معمولی روشن نمی‌شود. در جلسه‌ی ۱۳ با این دستور روشن می‌شود:

```bash
docker compose --profile ci up -d
```

- مقدار `RUNNER_TOKEN` را باید قبلاً در Gitea بسازید و در `.env` بگذارید.
- مسیر `/var/run/docker.sock` به runner اجازه می‌دهد jobها را در containerهای جدید روی Docker لپ‌تاپ اجرا کند.
- حجم (volume) به نام `gitea-runner-data` ثبت‌نام runner را نگه می‌دارد تا هر بار تکرار نشود.

فایل `gitea-runner/config.yaml`:

```yaml
runner:
  capacity: 1
  timeout: 30m
  labels:
    - "ubuntu-latest:docker://mlops/ci-job:1.0"
container:
  network: mlops-lab
  force_pull: false
  privileged: false
  valid_volumes:
    - /var/run/docker.sock
    - mlops-uv-cache
  options: "-v mlops-uv-cache:/root/.cache/uv"
```

- مقدار `capacity: 1` یعنی هر بار فقط یک job اجرا می‌شود تا لپ‌تاپ ۱۶ گیگ تحت فشار نباشد.
- مقدار `timeout: 30m` jobهای طولانی‌تر از ۳۰ دقیقه را متوقف می‌کند.
- برچسب `ubuntu-latest` به image آماده‌ی دوره (`mlops/ci-job:1.0`) وصل شده است، یعنی jobهایی که `runs-on: ubuntu-latest` دارند داخل آن اجرا می‌شوند.
- مقدار `network: mlops-lab` باعث می‌شود containerهای job با نام‌های `gitea`، `mlflow` و `seaweedfs` سرویس‌ها را ببینند.
- گزینه‌ی `options` یک volume به نام `mlops-uv-cache` به هر job وصل می‌کند و `valid_volumes` اجازه‌ی این کار را می‌دهد. کتابخانه‌های Python که `uv` دانلود می‌کند آنجا می‌مانند، پس اجرای دوم CI به‌جای ۲۰ تا ۵۰ ثانیه دانلود، حدود یک ثانیه صرف نصب می‌کند (اندازه‌گیری ما: volume حدود ۸۰۰ مگابایت). سوکت Docker را خود runner به job می‌دهد؛ آن را دوباره در `options` ننویسید، وگرنه job با خطای `Duplicate mount point` شروع نمی‌شود.
- مقدار `force_pull: false` یعنی image محلی استفاده شود و اینترنت لازم نباشد. مقدار `privileged: false` هم دسترسی اضافه به jobها نمی‌دهد.

## volumeها و شبکه

```yaml
volumes:
  seaweedfs-data:
  mlflow-db:
  gitea-data:
  gitea-runner-data:

networks:
  default:
    name: mlops-lab
```

حجم‌های (volume) نام‌دار خارج از containerها ذخیره می‌شوند و با `docker compose down` پاک نمی‌شوند، ولی `docker compose down -v` همه را پاک می‌کند. شبکه‌ی `mlops-lab` اسم ثابت دارد تا containerها یکدیگر را با نام سرویس پیدا کنند و runner هم بتواند به آن وصل شود. نام پروژه (`name: mlops-lab`) هم ثابت است.

## عیب‌یابی سریع

| نشانه | علت و راه‌حل |
|---|---|
| خطای `port is already allocated` | برنامه‌ی دیگری پورت را گرفته؛ آن را ببندید و دوباره `docker compose up -d` بزنید |
| MLflow بالا نمی‌آید | با `docker compose logs mlflow` ببینید؛ معمولاً SeaweedFS هنوز `healthy` نشده یا `.env` ساخته نشده |
| خطای Access Denied هنگام آپلود | کلیدهای `.env` با `s3.json` یکی نیستند |
| خطای Invalid Host header در MLflow | نشانی که استفاده می‌کنید در `--allowed-hosts` نیست |
| runner ثبت نمی‌شود | مقدار `RUNNER_TOKEN` خالی یا اشتباه است |

## پرسش‌هایی برای فکر کردن

۱. اگر `docker compose down -v` بزنیم، کدام داده‌ها از دست می‌روند و کدام باقی می‌مانند؟
۲. چرا همه‌ی پورت‌ها را روی `127.0.0.1` بسته‌ایم و روی `0.0.0.0` باز نکرده‌ایم؟
۳. اگر `--serve-artifacts` را برداریم، کد دانشجو برای آپلود مدل چه چیزی بیشتر لازم دارد؟
