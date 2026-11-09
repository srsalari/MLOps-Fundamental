<div dir="rtl">

# تکلیف جلسه‌ی ۴

مهلت: پیش از شروع جلسه‌ی ۵. این تکلیف چهار بخش دارد. بخش‌های ۱، ۳ و ۴ روی یک شاخه و با یک Pull Request وارد `main` می‌شوند. بخش ۲ (نسخه‌ی ۳ داده) روی شاخه‌ی جدا می‌ماند و **merge نمی‌شود**، چون جلسه‌ی ۵ دقیقاً از داده‌ی نسخه‌ی ۲ روی `main` شروع می‌کند (متریک `0.7493` و `0.6991`).

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-4
```

```bash
set -a; source .env; set +a
```

<bdi dir="rtl">SeaweedFS باید روشن باشد (`docker compose ps` در پوشه‌ی `~/mlops-lab/compose`). فایل‌ها را با VS Code یا `nano` ویرایش کنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند.</bdi>

## ۱. بخش «Data versioning» در README

در `README.md` پروژه بخشی با عنوان «Data versioning» بنویسید که به یک همکار تازه بگوید:

- چطور پروژه را clone کند
- دو مقدار رمز را کجا و با چه دستوری فقط به‌صورت محلی بدهد
- چطور داده را بگیرد و چطور بفهمد داده درست است (با کدام دستور md5 را ببیند و با کدام عدد مقایسه کند)

دستورها را در بلوک کد بنویسید و رمز واقعی را در متن نیاورید. برای اطمینان، همین مراحل را یک بار در یک clone تازه (مثلاً در `~/work/churn-clone`) اجرا کنید و ببینید کار می‌کند.

## ۲. نسخه‌ی ۳ داده (روی شاخه‌ی جدا)

```bash
git switch main && git switch -c feature/data-v3
```

نسخه‌ی ۳ را با seed دیگر بسازید (گزینه‌ی `--seed` در `make_dataset.py` هست؛ مثلاً مقدار ۷ و ۵۰۰۰ ردیف). بعد مثل گام ۴ آزمایشگاه: `dvc add`، `git add` روی pointer، commit، `dvc push`، `make train` و tag به نام `data-v3`. شاخه و tag را push کنید، ولی Pull Request نسازید:

```bash
git push -u origin feature/data-v3 && git push origin data-v3
```

یک جدول سه‌ردیفه در README بنویسید (نسخه‌ی ۱، ۲ و ۳) با ستون‌های: tag، تعداد ردیف، churn rate، md5 کوتاه‌شده (هشت حرف اول)، roc_auc و f1. عددهای نسخه‌ی ۳ را خودتان با اجرا به‌دست آورید. یک جمله بنویسید که چرا نباید این سه عدد را عادلانه با هم مقایسه کرد.

در پایان به نسخه‌ی ۲ روی `main` برگردید و مطمئن شوید `verify.sh s04` هنوز سبز است:

```bash
git switch feature/homework-4 && uv run dvc checkout
```

> جدول README را روی شاخه‌ی `feature/homework-4` (نه `feature/data-v3`) بنویسید.

## ۳. دو هدف تازه در Makefile

دو هدف به `Makefile` اضافه کنید و نامشان را به خط `.PHONY` هم بیفزایید (خط‌های دستور با **TAB** شروع می‌شوند، نه فاصله):

| هدف | کار |
| --- | --- |
| `data-pull` | داده را از remote می‌گیرد (دستور `dvc pull`) |
| `data-status` | وضعیت cache در برابر remote را نشان می‌دهد (دستور `dvc status` با گزینه‌ی cloud) |

```bash
make data-status
```

انتظار: خطی که می‌گوید `Cache and remote 'storage' are in sync.`

## ۴. شکست عمدی

دو خطا را عمداً بسازید و پیام دقیق هر کدام را در جدولی در README بنویسید (ستون‌ها: کاری که کردم، پیام خطا، یعنی چه، راه‌حل):

1. پورت `endpointurl` را خراب کنید (مثلاً یک عدد اشتباه) و `uv run dvc push` بزنید. بعد درستش کنید.
2. یکی از دو مقدار `--local` را از `.dvc/config.local` پاک کنید (با `dvc remote modify --local storage --unset ...`) و `uv run dvc pull` بزنید. بعد دوباره از `.env` بدهید.

اگر `dvc push` یا `dvc pull` چیزی برای انجام نداشت، یک بار `rm -r .dvc/cache` فقط در همین پروژه بزنید تا خطا دیده شود. مراقب مسیر باشید.

## ۵. commit، push و Pull Request

```bash
git add README.md Makefile && git commit -m "docs: data versioning section, make targets, failure table"
```

```bash
git push -u origin feature/homework-4
```

در Gitea Pull Request بسازید، Merge کنید و بعد:

```bash
git switch main && git pull
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s04
```

2. متن بخش «Data versioning» و دو جدول README
3. خروجی `git tag -n1`
4. لینک شاخه‌ی `feature/data-v3` در Gitea
5. یک جمله: اگر `churn.csv.dvc` در Git باشد ولی `dvc push` را هرگز نزده باشید، همکار شما بعد از clone و `dvc pull` چه می‌بیند و چرا؟

</div>
