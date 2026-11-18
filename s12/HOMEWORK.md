<div dir="rtl">

# تکلیف جلسه‌ی ۱۲

مهلت: پیش از شروع جلسه‌ی ۱۳. همه‌ی کارها روی یک شاخه‌ی تازه و با یک Pull Request وارد `main` شوند. بخش ۱ اختیاری است، ولی بخش‌های ۲ و ۳ لازم‌اند.

```bash
cd ~/work/churn-mlops && git switch main && git pull && git switch -c feature/homework-12
```

<bdi dir="rtl">cluster باید روشن باشد و Traefik و release با نام `churn-api` در namespace با نام `churn` کار کنند (`make helm-status`). در هر ترمینال تازه alias‌ها را دوباره بزنید و context را بررسی کنید (هرگز بدون `--context kind-mlops` یا `--kube-context kind-mlops` به cluster دستور نزنید):</bdi>

```bash
alias k='kubectl --context kind-mlops'
```

```bash
alias h='helm --kube-context kind-mlops'
```

```bash
kubectl config current-context
```

<bdi dir="rtl">MLflow هم باید روشن باشد. اگر release خراب شد، `h history churn-api -n churn` و `h rollback churn-api REV -n churn` راه برگشت‌اند.</bdi>

قاعده‌ی کلی تکلیف: هر تغییر را **در فایل‌های `chart/` بنویسید و با `helm upgrade` (یا `make helm-deploy`) اعمال کنید**، نه با `kubectl edit` یا `kubectl set`، تا Git و Helm هر دو منبع حقیقت بمانند. هر عددی که می‌گویید باید با خروجی یک دستور واقعی ثابت شود.

## ۱. اختیاری: Ingress دوم

یکی از این دو را انتخاب کنید:

- برای محیط prod یک host دوم به Ingress اضافه کنید (مثلاً `api.prod.churn.localhost` علاوه بر `prod.churn.localhost`) و هر دو را با `curl` امتحان کنید. این یعنی `ingress.host` باید به فهرستی از host‌ها تبدیل شود؛ چه چیزی در template تغییر می‌کند (راهنما: `range`)؟
- با دستور `h template` ثابت کنید که با `ingress.enabled=false` هیچ شیء `Ingress` ساخته نمی‌شود، و این را برای یک release آزمایشی در namespace دیگری اجرا کنید.

برای هر کدام بنویسید: چه فایلی را عوض کردید، دستورها، و چه دیدید.

## ۲. یک مقدار قابل‌تنظیم به chart اضافه کنید و مستندش کنید (لازم)

هدف: همان کاری که یک مهندس پلتفرم روزانه می‌کند: یک رفتار سخت‌کد‌شده را به **مقدار قابل‌تنظیم** تبدیل می‌کند، برای هر محیط تنظیمش می‌کند و برای هم‌تیمی‌ها می‌نویسد.

### الف) انتخاب مقدار

یک مقدار انتخاب کنید که **در chart فعلی ثابت است** و تغییرش معنی دارد. چند پیشنهاد (یکی را انتخاب کنید یا مورد دیگری با تأیید مدرس):

- زمان‌بندی probe‌ها (مثلاً `readinessProbe.initialDelaySeconds` یا `periodSeconds`)
- <bdi dir="rtl">`strategy.maxSurge` و `maxUnavailable`</bdi>
- <bdi dir="rtl">annotation‌های Ingress (`ingress.annotations`) یا label‌های اضافه روی همه‌ی شیء‌ها</bdi>
- <bdi dir="rtl">`nodeSelector` یا `terminationGracePeriodSeconds` pod</bdi>
- فعال یا غیرفعال بودن یک بخش (مثل `ingress.enabled`، که الان هست؛ یک شیء دیگر مثل یک `PodDisruptionBudget` ساده)

قاعده‌ها:

- مقدار باید نام روشن داشته باشد و در `values.yaml` یک **مقدار پیش‌فرض** و یک **کامنت** (انگلیسی، یک خط) بگیرد.
- پیش‌فرض باید همان رفتار قبلی را بدهد: با `values.yaml` تنها، خروجی `helm template` نسبت به قبل از تغییر **نباید فرق کند** (جز آنچه خودتان خواسته‌اید). این را با یک دستور ثابت کنید.
- مقدار باید در `values-dev.yaml` یا `values-prod.yaml` (یا هر دو) **متفاوت** تنظیم شود، با دلیل.

### ب) کار با chart

۱. مقدار را در `values.yaml` اضافه کنید و در template مناسب (`templates/...`) استفاده کنید. اگر `Chart.yaml` تغییر لازم دارد (مثلاً شماره‌ی `version` chart)، با دلیل تغییر دهید.

۲. <bdi dir="rtl">`make helm-lint` را برای dev و prod اجرا کنید (`make helm-lint STAGE=prod`).</bdi>

۳. فرق خروجی را با `helm template` ثابت کنید. دو خروجی بگیرید (پیش از تغییر با `git stash` یا از commit قبلی، و بعد از تغییر) و با `diff` مقایسه کنید. دستورها و فقط خطوطی که فرق دارند را بنویسید.

۴. <bdi dir="rtl">release dev را با `helm upgrade` به‌روز کنید و در **cluster** ثابت کنید که مقدار اعمال شده است. با دستوری مثل `k ... get ... -o jsonpath=...` یا `k describe`، مقدار را از خود شیء بخوانید (نه از فایل).</bdi>

۵. مقدار را به شکل `--set` هم یک بار عوض کنید، `h history` و `h get values` را ببینید، و با `h rollback` به revision قبل برگردید. بنویسید `h get values churn-api -n churn` قبل و بعد از rollback چه نشان داد و چرا.

### ج) مستندسازی

فایلی به نام `chart/churn-api/README.md` بسازید (یا اگر خواستید، `chart/README.md`). باید این‌ها را داشته باشد:

- یک جدول از **همه‌ی** مقدارهای chart (نه فقط مقدار شما): نام، پیش‌فرض، معنی، مثال. مقدار تازه‌ی شما در آن باشد.
- دو دستور نمونه: نصب dev و نصب prod با `make` یا `helm`.
- یک بخش «چگونه تغییر امن بدهیم»: از `helm lint`، `helm template` و `helm upgrade --wait` چه ترتیبی را پیشنهاد می‌کنید و چرا.

این فایل را برای کسی بنویسید که chart را ندیده است و فقط با آن فایل باید بتواند یک release بسازد.

## ۳. دو پاراگراف (لازم)

متن باید از خودتان باشد.

**پاراگراف اول** (چهار تا شش جمله): فرق `kubectl apply -f k8s/` با `helm install` را با یک مثال از همین جلسه بنویسید. چه چیزی را Helm برای شما نگه می‌دارد که kubectl نگه نمی‌داشت؟ چرا `helm install` روی شیء‌هایی که kubectl ساخته بود خطا داد؟

**پاراگراف دوم** (چهار تا شش جمله): در release prod مدل را به یک نسخه‌ی ثابت (`models:/churn/2`) وصل کردیم، ولی در dev به `@champion`. دلیل این تصمیم را توضیح دهید و بنویسید در چه حالتی هر کدام برای تیم مناسب‌تر است. بعد بنویسید اگر فردا `@champion` به نسخه‌ی ۳ برود، در هر یک از دو محیط چه اتفاقی می‌افتد و چه کاری لازم است.

## ۴. commit و push

```bash
git add chart && git commit -m "feat: add a configurable chart value and document the chart (homework 12)"
```

اگر یادداشت‌هایتان را در فایلی مثل `NOTES-S12.md` نوشتید، نام آن را هم به `git add` اضافه کنید.

```bash
git push -u origin feature/homework-12
```

در Gitea Pull Request بسازید و Merge کنید، بعد:

```bash
git switch main && git pull
```

<bdi dir="rtl">release را با نسخه‌ی merge‌شده یک بار دیگر اعمال کنید تا cluster و Git یکی باشند:</bdi>

```bash
make helm-deploy
```

## برای مدرس بفرستید

1. خروجی این دستور:

```bash
~/mlops-lab/scripts/verify.sh s12
```

2. نام مقدار انتخابی، دلیل انتخاب، و diff فایل‌های `chart/` (خروجی `git diff main~1 -- chart` یا لینک PR)
3. خروجی `diff` بین دو `helm template` (پیش از تغییر و بعد از آن) و دستور و خروجی خواندن مقدار از cluster
4. خروجی `h history churn-api -n churn` و `h get values churn-api -n churn` پس از آزمایش `--set` و rollback، با توضیح
5. فایل `chart/churn-api/README.md`
6. دو پاراگراف بخش ۳
7. اگر بخش ۱ را انجام دادید: توضیح و خروجی‌ها

## راهنمای نمره‌دهی

| بخش | چه چیزی دیده می‌شود |
| --- | --- |
| ۲ الف (لازم) | مقدار با نام روشن، پیش‌فرض و کامنت در `values.yaml`؛ پیش‌فرض رفتار قبلی را عوض نمی‌کند (با diff ثابت شده)؛ در dev یا prod با دلیل متفاوت تنظیم شده |
| ۲ ب (لازم) | `helm lint` سبز برای dev و prod؛ diff پیش و پس از تغییر؛ مقدار از خود cluster خوانده شده؛ آزمایش `--set` و rollback با توضیح درست از `get values` |
| ۲ ج (لازم) | README در `chart/`: جدول کامل مقدارها (نه فقط مقدار تازه)، دو دستور نمونه، و بخش تغییر امن؛ برای کسی که chart را ندیده قابل استفاده است |
| ۳ (لازم) | هر دو پاراگراف پاسخ داده شده؛ فرق kubectl و Helm با مثال؛ تحلیل `@champion` در برابر نسخه‌ی ثابت درست است؛ متن شخصی و غیرکپی |
| ۱ (اختیاری) | تغییر در فایل (نه دستی)، دستور و نتیجه‌ی دیده‌شده |
| کلی | `verify.sh s12` سبز؛ PR وارد `main` شده؛ release در پایان `deployed` و سالم است؛ هیچ راز یا کلیدی در commit نیست؛ هیچ دستور kubectl یا helm بدون context کار نشده |

</div>
