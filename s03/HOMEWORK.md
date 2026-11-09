<div dir="rtl">

# تکلیف جلسه‌ی ۳

مهلت: پیش از شروع جلسه‌ی ۴. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-3
```

<bdi dir="rtl">SeaweedFS باید روشن باشد (در `~/mlops-lab/compose` دستور `docker compose ps` وضعیت `healthy` بدهد).</bdi>

## ۱. بخش «Local storage» در README

در `README.md` پروژه یک بخش با عنوان `Local storage` اضافه کنید که یک هم‌تیمی تازه بتواند با آن:

- <bdi dir="rtl">SeaweedFS را بالا بیاورد،</bdi>
- فایل `.env` را از روی نمونه بسازد،
- دو bucket `dvc` و `mlflow` را بسازد.

دستورها را با همان ترتیب آزمایشگاه بنویسید و کنار هر دستور یک جمله بگویید چه می‌کند. یک جمله هم بنویسید که چرا `.env` در Git نیست.

## ۲. هدف `s3-ls` در Makefile

به `Makefile` پروژه هدفی به نام `s3-ls` اضافه کنید که فهرست bucketها را چاپ کند. راهنما:

- پیش‌نیاز: کلیدها را از `.env` بخواند (مثل `source` در آزمایشگاه) و از `uv run aws` با `--endpoint-url` استفاده کند.
- در Makefile هر دستور با کاراکتر Tab شروع می‌شود، نه فاصله.
- متغیر شل داخل Makefile با دو علامت دلار نوشته می‌شود.
- نام هدف را در خط `.PHONY` هم بگذارید.

بعد بررسی کنید:

```bash
make s3-ls
```

انتظار: همان دو bucket چاپ شوند.

## ۳. شکست عمدی

هدف: خواندن پیام خطا. فایل `.env` اصلی را خراب نکنید؛ متغیر را فقط برای همان یک دستور بدهید. اول `.env` را بارگذاری کنید:

```bash
set -a; source .env; set +a
```

یک بار secret اشتباه:

```bash
AWS_SECRET_ACCESS_KEY=wrong uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls
```

یک بار پورت اشتباه:

```bash
uv run aws --endpoint-url http://localhost:8334 s3 ls
```

در `README.md` یک جدول کوچک بگذارید با سه ستون: دستور، پیام خطا، علت و راه‌حل. دست‌کم این دو پیام را بنویسید: `SignatureDoesNotMatch` و `Could not connect to the endpoint URL`. اگر خواستید، خطای پورت اشغال Docker (`Bind for ... failed`) را هم اضافه کنید.

## ۴. سالم نگه داشتن محیط

<bdi dir="rtl">Docker و SeaweedFS را تا جلسه‌ی ۴ سالم نگه دارید. جلسه‌ی ۴ از bucket `dvc` استفاده می‌کند. فقط `dvc` و `mlflow` باید bucket باشند؛ اگر bucket اضافه (مثل نام اشتباه) ساخته‌اید، پاکش کنید.</bdi>

```bash
set -a; source .env; set +a
```

```bash
uv run aws --endpoint-url "$S3_ENDPOINT_URL" s3 ls
```

## ۵. commit و push

```bash
git add README.md Makefile && git commit -m "docs: local storage section, s3-ls target, error table"
```

```bash
git push -u origin feature/homework-3
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s03
```

2. خروجی `make s3-ls`
3. متن بخش `Local storage` و جدول خطاها از `README.md`
4. یک جمله: بعد از `docker compose down` چرا `churn.csv` هنوز هست، و با `-v` چه می‌شد؟
5. یک جمله: امروز کدام بخش مبهم‌تر بود، Docker یا S3؟

</div>
