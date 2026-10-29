# MLOps Fundamentals On-Prem — مخزن دانشجو

فایل‌های آزمایشگاه و منابع دوره‌ی **MLOps Fundamentals On-Prem** (۱۴ جلسه‌ی ۳ ساعته) — Anisa / Iran Linux House

مدرس: سعیدرضا سالاری

## دریافت و به‌روزرسانی

بار اول:

```bash
git clone https://github.com/srsalari/MLOps-Fundamental.git ~/mlops-lab
```

قبل از هر جلسه:

```bash
git -C ~/mlops-lab pull
```

کاربران Windows همه‌ی دستورها را داخل Ubuntu (WSL2) اجرا کنند، نه در PowerShell. راهنمای نصب در `s01/README.md` است.

## ساختار مخزن

| مسیر | محتوا |
|---|---|
| `s01/`، `s02/`، … | فایل‌های آماده و راهنمای آزمایشگاه هر جلسه؛ در هر پوشه `preflight.sh` آمادگی پیش از کلاس را می‌سنجد (لپ‌تاپ و وضعیت پروژه در پایان جلسه‌ی قبل)، مثلاً `~/mlops-lab/s05/preflight.sh` |
| `compose/` | سرویس‌های آزمایشگاه با Docker Compose: Gitea (و runner آن)، SeaweedFS، MLflow |
| `scripts/` | `verify.sh` (بررسی پایان کار هر جلسه)، `preflight.sh` (بررسی آمادگی لپ‌تاپ؛ مثلاً `preflight.sh s03` فقط نیازهای جلسه‌ی ۳ و جلسه‌های قبل از آن را می‌سنجد)، `kind-up.sh`، `install-from-bundle.sh` |
| `k8s/` | تنظیمات Kubernetes (kind، Traefik، monitoring) برای جلسه‌های ۱۱ تا ۱۳ |
| `compose/README.md`، `k8s/README.md` | راهنمای فارسی فایل‌های تنظیمات: [سرویس‌های آزمایشگاه](compose/README.md) و [تنظیمات Kubernetes](k8s/README.md) |
| `versions.env`، `requirements.txt` | نسخه‌ی دقیق ابزارها و کتابخانه‌های دوره |

## پروژه‌ی شما کجاست؟

این مخزن فقط **منبع فایل‌ها**ست. پروژه‌ی خودتان را جدا، در `~/work/churn-mlops` می‌سازید و فایل‌های هر جلسه را طبق راهنمای همان جلسه به آن کپی می‌کنید. داخل `~/mlops-lab` چیزی را ویرایش نکنید تا `git pull` بدون مشکل کار کند.

## جلسه‌ها

| جلسه | موضوع | پوشه |
|---|---|---|
| ۱ | شروع دوره و مبانی MLOps؛ اولین مدل Churn | [`s01/`](s01/README.md) |
| ۲ | Git برای ML و کیفیت کد | [`s02/`](s02/README.md) · [آماده‌سازی](s02/SETUP.md) |
| ۳ | مبانی Docker و ذخیره‌ساز شیء (SeaweedFS) | [`s03/`](s03/README.md) · [تکلیف](s03/HOMEWORK.md) |
| ۴ | نسخه‌بندی داده با DVC | [`s04/`](s04/README.md) · [تکلیف](s04/HOMEWORK.md) |
| ۵ | پایپ‌لاین DVC (preprocess/train/evaluate) و بازتولیدپذیری | [`s05/`](s05/README.md) · [تکلیف](s05/HOMEWORK.md) |
| ۶ | MLflow Tracking و اتصال آن به پروژه | [`s06/`](s06/README.md) · [تکلیف](s06/HOMEWORK.md) |
| ۷ | Model Registry و Promotion با دروازه‌ی ارزیابی | [`s07/`](s07/README.md) · [تکلیف](s07/HOMEWORK.md) |
| ۸ | سرویس استنتاج (Inference) با FastAPI | [`s08/`](s08/README.md) · [تکلیف](s08/HOMEWORK.md) |
| ۹ | Containerization و امنیت image (Docker، Trivy، registry محلی) | [`s09/`](s09/README.md) · [تکلیف](s09/HOMEWORK.md) |
| ۱۰ | استقرار روی VM با Ansible (systemd، Nginx، Runbook، rollback) | [`s10/`](s10/README.md) · [تکلیف](s10/HOMEWORK.md) |
| ۱۱ | استقرار روی Kubernetes با kind (Deployment، Service، probeها، rollout) | [`s11/`](s11/README.md) · [تکلیف](s11/HOMEWORK.md) |
| ۱۲ | Ingress با Traefik و بسته‌بندی با Helm (host-based routing، chart، values، upgrade و rollback) | [`s12/`](s12/README.md) · [تکلیف](s12/HOMEWORK.md) |
| ۱۳ | CI هوشمند روی Gitea Actions، مانیتورینگ با Prometheus و Grafana، گزارش drift با Evidently | [`s13/`](s13/README.md) · [تکلیف](s13/HOMEWORK.md) |
| ۱۴ | اجرای سرتاسری از clone تمیز، چک‌لیست امتیازدار آمادگی، Runbook، Demo و نسخه‌ی v1.0.0 | [`s14/`](s14/README.md) · [تکلیف](s14/HOMEWORK.md) |

## درباره‌ی کلیدهای داخل `compose/`

کلیدهای `compose/.env.example` و `compose/seaweedfs/s3.json` فقط برای سرویس‌های محلی آزمایشگاه روی لپ‌تاپ خودتان هستند. هرگز آن‌ها را بیرون از کلاس استفاده نکنید.
