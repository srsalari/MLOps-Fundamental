<div dir="rtl">

# تکلیف جلسه‌ی ۲

مهلت: پیش از شروع جلسه‌ی ۳. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-2
```

## ۱. یک آزمون دیگر بنویسید

یک آزمون پنجم به `tests/test_data.py` اضافه کنید. یکی از این دو را انتخاب کنید:

- **نرخ ریزش در بازه‌ی مجاز:** میانگین ستون `churn` در داده‌ی ساخته‌شده عددی بین ۰ و ۱ است و هیچ‌کدام از دو مقدار ۰ و ۱ غایب نیست.
- **مقادیر مجاز یک ستون:** ستون `tenure_months` هیچ مقدار منفی ندارد.

```bash
uv run pytest -q
```

انتظار: `5 passed`.

یادآوری: آزمونی مثل «ROC-AUC بالاتر از ۰٫۸۵ باشد» ننویسید. آن ارزیابی مدل است، نه آزمون واحد.

## ۲. هدف‌های `lint` و `test` را به Makefile اضافه کنید

این دو هدف را به `Makefile` اضافه کنید و نامشان را به خط `.PHONY` هم بیفزایید. خط‌های دستور باید با **TAB** شروع شوند، نه فاصله:

```makefile
lint:
	uv run ruff check .
	uv run ruff format --check .

test:
	uv run pytest -q
```

```bash
make lint && make test
```

اگر خطای `missing separator` گرفتید، خط دستور با فاصله شروع شده است.

## ۳. بخش Contributing را به README اضافه کنید

در `README.md` پروژه بخشی به نام `Contributing` بنویسید که قراردادهای تیم را بگوید، در چهار تا شش خط:

- نام‌گذاری شاخه‌ها (`feature/...`، `fix/...`، `docs/...`)
- قالب پیام commit (Conventional Commits، با یک مثال)
- چک‌لیست Pull Request (آزمون‌ها سبز، متریک قبل و بعد در توضیح، بدون داده و مدل و رمز)
- دستورهایی که پیش از push باید اجرا شوند (`make lint` و `make test`)

## ۴. Pull Request و ارسال

```bash
git add . && git commit -m "test: add data test, lint/test targets and contributing guide"
```

```bash
git push -u origin feature/homework-2
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s02
```

2. خروجی `git log --oneline | head -8`
3. یک جمله: کدام hook بیشتر جلوی commit شما را گرفت و چرا؟

## برای جلسه‌ی ۳

<bdi dir="rtl">Docker و Gitea را روشن نگه دارید؛ جلسه‌ی ۳ با Docker شروع می‌شود و توضیح می‌دهد پشت دستور `docker compose up -d gitea` چه اتفاقی می‌افتاد.</bdi>

### سه image جلسه‌ی ۳ را از الان بگیرید

کلاس جلسه‌ی ۳ اینترنت ندارد، پس این سه image را **پیش از کلاس و با اینترنت** بگیرید (image مثل فایل نصب است: یک بار دانلود می‌شود و بعد بدون اینترنت اجرا می‌شود). نصب و راه‌اندازی SeaweedFS کار خود جلسه‌ی ۳ است؛ اینجا فقط دانلود می‌کنید.

| image | در جلسه‌ی ۳ برای چه |
| --- | --- |
| `chrislusf/seaweedfs:4.45` | ذخیره‌ساز شیء سازگار با S3 |
| `nginx:1.28-alpine` | تمرین container و پورت |
| `python:3.12-slim-bookworm` | تمرین volume و اجرای پایتون داخل container |

هر دستور را جدا بزنید (کاربران Windows داخل Ubuntu در WSL، نه PowerShell):

```bash
docker pull chrislusf/seaweedfs:4.45
```

```bash
docker pull nginx:1.28-alpine
```

```bash
docker pull python:3.12-slim-bookworm
```

انتظار: هر دستور با خطی که با `Status:` شروع می‌شود تمام شود؛ یا `Downloaded newer image for ...` (بار اول، روی هم حدود ۲۵۰ مگابایت) یا `Image is up to date for ...` (اگر از قبل داشتید). هر دو درست است.

اگر اینترنت کند است یا Docker Hub در دسترس نیست، از بسته‌ی آفلاین دوره استفاده کنید (لینک را مدرس می‌دهد):

```bash
~/mlops-lab/scripts/install-session-pack.sh s03
```

بررسی کنید که چهار image (همراه `gitea` از جلسه‌ی ۲) روی لپ‌تاپ هست:

```bash
docker images | grep -E "nginx|python|seaweedfs|gitea"
```

انتظار: چهار ردیف با `chrislusf/seaweedfs:4.45`، `gitea/gitea:1.27.3`، `nginx:1.28-alpine` و `python:3.12-slim-bookworm`.

```bash
~/mlops-lab/scripts/preflight.sh s03
```

انتظار: در بخش `[Lab images loaded]` چهار `PASS` و در خط آخر `READY for session 3` (همراه تعداد هشدارها؛ بخش `[Later sessions]` فقط اطلاع است). اگر خطی `FAIL` بود، راه‌حل زیر همان خط (بعد از `->`) نوشته شده است.

| نشانه | راه‌حل |
| --- | --- |
| `Cannot connect to the Docker daemon` | macOS: Docker Desktop را باز کنید یا `colima start`؛ Ubuntu و WSL: `sudo systemctl start docker` |
| `toomanyrequests` یا قطع شدن دانلود | چند دقیقه بعد دوباره امتحان کنید، یا بسته‌ی آفلاین |
| `no space left on device` | با `docker system df` ببینید چه چیزی جا گرفته و فقط image‌های قدیمی خودتان را پاک کنید |

برای DVC امروز کاری لازم نیست؛ در جلسه‌ی ۴ داخل خود پروژه نصب می‌شود.

</div>
