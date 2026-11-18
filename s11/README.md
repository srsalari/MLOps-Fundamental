<div dir="rtl">

# آزمایشگاه جلسه‌ی ۱۱ — استقرار روی Kubernetes با kind

در جلسه‌ی ۱۰ سرویس را روی یک VM گذاشتید و systemd آن را زنده نگه می‌داشت. در این جلسه همان سرویس churn را روی **Kubernetes** اجرا می‌کنید. Kubernetes به‌جای شما نگهبانی می‌کند: دو کپی از برنامه را همیشه روشن نگه می‌دارد، اگر یکی مُرد جایش یکی تازه می‌سازد، نسخه‌ی تازه را قدم‌به‌قدم جایگزین می‌کند، و ترافیک را فقط به کپی‌هایی می‌دهد که واقعاً آماده‌اند. آنچه اجرا می‌کنید یک **cluster** واقعی Kubernetes است، ولی کوچک و روی لپ‌تاپ خودتان، با ابزاری به نام **kind** («Kubernetes in Docker»: node این cluster یک container است).

کار این جلسه بیشتر خواندن و نوشتن فایل‌های YAML («manifest») و دیدن واکنش cluster است. چند اشتباه عمدی هم می‌کنید (image که وجود ندارد، مدل که خاموش است) تا ببینید Kubernetes از کاربران چطور محافظت می‌کند.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۱۰ سالم باشد: `main` شامل tag `v0.8.0` است.
2. <bdi dir="rtl">image جلسه‌ی ۹ (`churn-api:0.7.0`) روی لپ‌تاپ شما هست و در registry محلی (`localhost:5001`، container با نام `kind-registry`) هم گذاشته شده است. اگر مطمئن نیستید، در گام ۱ همین را بررسی و در صورت نیاز درست می‌کنیم (`make image` و `make push`).</bdi>
3. سرویس‌های جلسه‌های قبل پاک نشده‌اند (`docker compose down -v` نزده باشید).
4. **حافظه‌ی Docker حداقل ۸ گیگابایت** باشد. node ما با دو pod حدود ۱٫۱ گیگابایت می‌گیرد، ولی خود Docker و بقیه‌ی سرویس‌ها هم جا می‌خواهند. در Docker Desktop: Settings، بخش Resources.
5. <bdi dir="rtl">kind و kubectl روی لپ‌تاپ نصب باشند (در بسته‌ی آفلاین دوره هستند). بررسی آمادگی را اجرا کنید:</bdi>

```bash
~/mlops-lab/s11/preflight.sh
```

اگر خطایی داد، پیام آن راه‌حل را می‌گوید. بعد مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
K=~/mlops-lab/s11
```

در این جلسه **دو ترمینال** لازم دارید: ترمینال ۱ برای کار اصلی، و ترمینال ۲ فقط برای `port-forward` (از گام ۳). اگر ترمینال را بستید، خط `K=...` را دوباره بزنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell. دانشجوهای macOS: Docker Desktop (یا Colima) باید در حال اجرا باشد.

### هشدار مهم درباره‌ی چند cluster

ابزار `kubectl` هر دستور را به «context فعلی» می‌فرستد. وقتی kind یک cluster می‌سازد، **context فعلی را عوض می‌کند** و روی `kind-mlops` می‌گذارد. اگر در `~/.kube/config` شما cluster دیگری هم هست (مثلاً cluster کاری یا ابری)، یک دستور اشتباه می‌تواند به آن برسد. دو دفاع داریم:

- <bdi dir="rtl">Makefile این جلسه همیشه `--context kind-mlops` را به kubectl می‌دهد.</bdi>
- در دستورهای دستی هم از `alias k` استفاده می‌کنیم که همین گزینه را در خود دارد (در گام ۱ می‌سازید).

پس در این جلسه به‌جای `kubectl` همیشه `k` می‌نویسید. و قبل از هر کار مهم، context را ببینید:

```bash
kubectl config current-context
```

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| Kubernetes (K8s) | سیستمی که container‌ها را روی چند ماشین اجرا و مدیریت می‌کند: می‌سازد، زنده نگه می‌دارد، جایگزین می‌کند |
| kind | ابزاری که یک cluster کامل Kubernetes را با container‌های Docker روی لپ‌تاپ می‌سازد؛ مخصوص تمرین و تست |
| cluster و node | cluster مجموعه‌ی ماشین‌هاست؛ هر ماشین یک node. cluster ما یک node دارد: `mlops-control-plane` |
| context | اینکه kubectl الان به کدام cluster وصل است (`kind-mlops`) |
| namespace | «اتاق» جدا داخل cluster. همه‌ی چیزهای ما در namespace به نام `churn` هستند |
| Pod | کوچک‌ترین واحد اجرا: یک (یا چند) container که با هم اجرا می‌شوند. pod را می‌شود هر لحظه کشت و جایگزین کرد |
| ReplicaSet | نگهبانی که می‌گوید «همیشه N کپی از این pod زنده باشد». اگر pod مُرد، جدید می‌سازد |
| Deployment | مدیر بالاتر: ReplicaSet می‌سازد و به‌روزرسانی مرحله‌ای (rolling update) و برگشت (rollback) را انجام می‌دهد. ما فقط Deployment می‌نویسیم |
| Service | یک نام و آدرس ثابت جلوی pod‌ها. فقط به pod‌های آماده ترافیک می‌دهد |
| label و selector | برچسب‌های `app: churn-api` روی pod‌ها؛ Service و Deployment با selector همان pod‌ها را پیدا می‌کنند |
| ConfigMap | تنظیم‌های غیرمحرمانه (مثل آدرس MLflow) که از image جدا نگه می‌داریم |
| Secret | مثل ConfigMap ولی برای چیزهای محرمانه (رمز، کلید). در این آزمایشگاه استفاده نمی‌شود، توضیحش پایین‌تر است |
| readinessProbe | آزمونی که می‌پرسد «آماده‌ای ترافیک بگیری؟». ناموفق: pod از Service بیرون می‌ماند، ولی restart نمی‌شود |
| livenessProbe | آزمونی که می‌پرسد «زنده‌ای؟». چند بار پشت‌سرهم ناموفق: container restart می‌شود |
| requests و limits | requests: حداقلی که برای pod رزرو می‌شود. limits: سقفی که از آن نباید رد شود. رد شدن از سقف حافظه یعنی `OOMKilled` |
| rolling update | جایگزین کردن pod‌های قدیمی با جدید، یکی‌یکی، بدون خاموشی |
| rollout undo | برگشت Deployment به نسخه‌ی قبلی |
| port-forward | تونل موقت از لپ‌تاپ به یک Service داخل cluster (برای تست) |
| events | گزارش‌های کوتاه cluster («pod ساخته شد»، «image دانلود شد»، «probe شکست خورد»). اولین جای نگاه کردن در عیب‌یابی |

### <bdi dir="rtl">Secret در یک نگاه (فقط مفهوم)</bdi>

*<bdi dir="rtl">*Secret** شبیه ConfigMap است، ولی برای اطلاعات محرمانه مثل رمز پایگاه داده. Pod آن را مثل ConfigMap به‌صورت متغیر محیطی دریافت می‌کند. دو نکته‌ی مهم:</bdi>

- مقدار در Secret فقط به شکل base64 ذخیره می‌شود. base64 **رمزنگاری نیست** و هر کس بتواند Secret را بخواند، مقدار را می‌خواند. محافظت واقعی با کنترل دسترسی (RBAC) و ابزارهای مدیریت راز است.
- فایل YAML حاوی راز را هرگز وارد Git نکنید.

شکل ساخت یک Secret (فقط برای دیدن نوشتار دستور؛ **در این آزمایشگاه اجرا نمی‌شود**، و `db-pass` و `CHANGE_ME` نمونه‌اند):

```text
k -n churn create secret generic db-pass --from-literal=password=CHANGE_ME
```

**چرا API ما Secret لازم ندارد؟** چون pod اصلاً به SeaweedFS (S3) وصل نمی‌شود و کلید S3 نمی‌خواهد. سرور MLflow فایل‌های مدل را خودش از S3 می‌گیرد و برای pod می‌فرستد (به این حالت می‌گویند artifacts پروکسی‌شده). تنها چیزی که pod می‌داند آدرس MLflow است (`http://mlflow:5000`) و آدرس که محرمانه نیست؛ پس ConfigMap کافی است. اگر روزی برنامه‌ای مستقیم به S3 یا پایگاه داده وصل شد، کلیدهایش در Secret می‌رفت.

## نتیجه‌ی نهایی

- یک cluster به نام `mlops` (context به نام `kind-mlops`) با یک node، و registry محلی `localhost:5001`
- <bdi dir="rtl">namespace به نام `churn` با Deployment به نام `churn-api` و **دو pod آماده** (`2/2`)</bdi>
- <bdi dir="rtl">Service ثابت `churn-api` و دسترسی از لپ‌تاپ با port-forward روی `http://localhost:8002`</bdi>
- دیدن و فهمیدن: rolling update، rollout undo، خود-ترمیمی، readiness در عمل، و فرق ConfigMap با rollout
- پوشه‌ی `k8s/` و Makefile تازه در پروژه، با tag نسخه‌ی `v0.9.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `k8s/namespace.yaml` | پوشه‌ی `k8s/` در پروژه | ساخت namespace به نام `churn` |
| `k8s/configmap.yaml` | پوشه‌ی `k8s/` در پروژه | تنظیم‌های API: آدرس MLflow، مدل، آستانه |
| `k8s/deployment.yaml` | پوشه‌ی `k8s/` در پروژه | دو pod از image، با probe‌ها و requests و limits |
| `k8s/service.yaml` | پوشه‌ی `k8s/` در پروژه | آدرس ثابت جلوی pod‌ها |
| `Makefile` | ریشه‌ی پروژه (جای Makefile جلسه‌ی ۱۰) | هدف‌های تازه‌ی `k8s-up`، `k8s-deploy`، `k8s-status`، `k8s-forward` |
| `preflight.sh` | اجرا از همین پوشه | بررسی آمادگی پیش از کلاس |

دو فایل از مخزن دوره را فقط اجرا می‌کنید و کپی نمی‌کنید: `~/mlops-lab/scripts/kind-up.sh` (ساخت registry و cluster) و `~/mlops-lab/k8s/kind-config.yaml` (تنظیم cluster). توضیح خط‌به‌خط همه‌ی فایل‌ها به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — cluster و registry (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git describe --tags
```

انتظار: `v0.8.0` (اگر تکلیف جلسه‌ی ۱۰ را merge کرده‌اید چیزی مثل `v0.8.0-2-g1a2b3c4` می‌بینید؛ مشکلی نیست)

```bash
git switch -c feature/k8s
```

سرویس‌های جلسه‌های قبل را روشن کنید. Pod‌ها باید MLflow را از طریق شبکه‌ی Docker به نام `mlops-lab` ببینند، پس این شبکه باید وجود داشته باشد:

```bash
cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow
```

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK`

```bash
cd ~/work/churn-mlops
```

<bdi dir="rtl">Makefile جلسه‌ی ۱۰ را با Makefile این جلسه عوض کنید (هدف‌های قبلی همه در آن هستند):</bdi>

```bash
cp $K/Makefile .
```

حالا cluster را بسازید. این هدف دو کار می‌کند: اسکریپت دوره (`kind-up.sh`) را اجرا می‌کند که registry و cluster را می‌سازد، و بعد node را به شبکه‌ی `mlops-lab` وصل می‌کند تا pod‌ها بتوانند به `http://mlflow:5000` برسند:

```bash
make k8s-up
```

انتظار: **حدود ۱ دقیقه** (بار اول image مربوط به node هم دانلود می‌شود؛ در کلاس معمولاً آماده است). پیام‌های ساخت cluster می‌آیند و در انتها چیزی مثل این:

```
 ✓ Waiting ≤ 2m0s for control-plane = Ready ⏳
 • Ready after 16s 💚
Set kubectl context to "kind-mlops"

You can now use your cluster with:

kubectl cluster-info --context kind-mlops

Have a nice day! 👋
configmap/local-registry-hosting created
NAME                  STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE                       KERNEL-VERSION            CONTAINER-RUNTIME
mlops-control-plane   Ready    control-plane   20s   v1.36.4   172.25.0.2    <none>        Debian GNU/Linux 13 (trixie)   7.0.14-linuxkit (arm64)   containerd://2.3.4
Cluster 'mlops' ready. Registry: localhost:5001  Ingress: http://localhost:8080
```

(عددهایی مثل IP، زمان‌ها و معماری `arm64` یا `amd64` روی سیستم شما فرق دارند.) خط `Set kubectl context to "kind-mlops"` همان چیزی است که در هشدار بالا گفتیم. اتصال به شبکه‌ی `mlops-lab` ساکت انجام می‌شود و خروجی ندارد.

اگر دوباره `make k8s-up` بزنید بدون خطا تمام می‌شود، چون هر مرحله اول بررسی می‌کند که قبلاً انجام نشده باشد.

<bdi dir="rtl">context را بررسی کنید:</bdi>

```bash
kubectl config current-context
```

انتظار: `kind-mlops`

اگر چیز دیگری دیدید، جدول عیب‌یابی را ببینید. حالا `alias` را بسازید که از این به بعد به‌جای `kubectl` بنویسید `k`:

```bash
alias k='kubectl --context kind-mlops'
```

این alias فقط در همین ترمینال زنده است. هر وقت ترمینال تازه باز کردید (از جمله ترمینال ۲)، این خط را دوباره بزنید. در Windows فقط داخل WSL.

```bash
k get nodes
```

انتظار: یک node به نام `mlops-control-plane` با وضعیت `Ready` (ستون‌های `ROLES` برابر `control-plane`).

حالا ببینید container‌های Docker که kind ساخته:

```bash
docker ps --filter name=mlops-control-plane --filter name=kind-registry --format '{{.Names}}\t{{.Status}}'
```

انتظار: دو ردیف، `mlops-control-plane` و `kind-registry`، هر دو `Up`. **node ما خودش یک container است**؛ همین است که به آن «Kubernetes in Docker» می‌گویند.

<bdi dir="rtl">image برنامه باید در registry باشد. از جلسه‌ی ۹ باید `churn-api:0.7.0` را داشته باشید:</bdi>

```bash
docker images churn-api:0.7.0
```

اگر ردیفی نبود، ابتدا `make image` را بزنید (حدود ۱ دقیقه). بعد در هر دو حالت image را به registry بفرستید (اگر قبلاً فرستاده‌اید، سریع تمام می‌شود و ایرادی ندارد):

```bash
make push
```

انتظار: بدون خطا تمام می‌شود و در حدود دو ثانیه (لایه‌ها اگر از جلسه‌ی ۹ در registry هستند دوباره فرستاده نمی‌شوند).

## گام ۲ — manifestها و اولین استقرار (۲۰ دقیقه)

پوشه‌ی `k8s/` را به پروژه کپی کنید:

```bash
cp -r $K/k8s .
```

```bash
ls k8s
```

انتظار: چهار فایل `configmap.yaml`، `deployment.yaml`، `namespace.yaml`، `service.yaml`

هر فایل را باز کنید و بخوانید. توضیح کامل خط‌به‌خط در [CODE.md](CODE.md) است؛ اینجا فقط ایده‌ی هر کدام را می‌گوییم.

**۱. namespace** — اتاق جدا برای همه‌ی چیزهای ما:

```bash
cat k8s/namespace.yaml
```

انتظار: `kind: Namespace` با نام `churn`. هر فایل دیگر هم `namespace: churn` دارد.

**۲. ConfigMap** — تنظیم‌های برنامه (فقط سه خط داده):

```bash
cat k8s/configmap.yaml
```

انتظار: سه کلید `MLFLOW_TRACKING_URI` (آدرس `http://mlflow:5000`)، `MODEL_URI` (برابر `models:/churn@champion`) و `PREDICT_THRESHOLD`. اینها همان متغیرهای محیطی هستند که در جلسه‌های ۸ تا ۱۰ هم به برنامه می‌دادیم.

**۳. Deployment** — مهم‌ترین فایل:

```bash
cat k8s/deployment.yaml
```

این بخش‌ها را پیدا کنید:

| بخش | معنی |
| --- | --- |
| `replicas: 2` | همیشه دو pod |
| `strategy` با `maxUnavailable: 0` و `maxSurge: 1` | در به‌روزرسانی، اول یک pod تازه اضافه شود (۳ تا)، و فقط وقتی آماده شد یک قدیمی حذف شود. هیچ‌وقت کمتر از دو pod آماده نداریم |
| `securityContext` با `runAsUser: 10001` | برنامه با کاربر معمولی اجرا شود، نه root |
| `image: localhost:5001/churn-api:0.7.0` | image از registry محلی |
| `envFrom` | همه‌ی کلیدهای ConfigMap به متغیر محیطی تبدیل شوند |
| `readinessProbe` روی `/ready` | وقتی مدل بار شده باشد پاسخ ۲۰۰ است، وگرنه ۵۰۳؛ تا آن موقع به pod ترافیک نمی‌رسد |
| `livenessProbe` روی `/health` | فقط می‌پرسد برنامه جواب می‌دهد یا نه؛ سه شکست پشت‌سرهم یعنی restart |
| `resources` | requests: `100m` پردازنده و `256Mi` حافظه. limits: `500m` و `512Mi` |

(`100m` یعنی یک‌دهم هسته‌ی پردازنده؛ `Mi` یعنی مگابایت دودویی.)

**۴. Service**:

```bash
cat k8s/service.yaml
```

انتظار: `type` نوشته نشده (پیش‌فرض ClusterIP: آدرس فقط داخل cluster)، پورت ۸۰ که به `targetPort: http` می‌رسد، یعنی پورتی که در Deployment اسمش `http` است (۸۰۰۰). Service pod‌ها را با `selector: app: churn-api` پیدا می‌کند.

حالا استقرار. هدف `k8s-deploy` اول namespace را می‌سازد، بعد همه‌ی پوشه را اعمال می‌کند، و منتظر می‌ماند همه‌ی pod‌ها آماده شوند:

```bash
make k8s-deploy
```

انتظار: **حدود ۱۱ ثانیه** (بار اول، اگر image را قبلاً در node نداشته باشد، چند ثانیه بیشتر برای دانلود). خروجی چیزی مثل این است:

```
kubectl --context kind-mlops apply -f k8s/namespace.yaml
namespace/churn created
kubectl --context kind-mlops apply -f k8s/
configmap/churn-api-config created
deployment.apps/churn-api created
namespace/churn unchanged
service/churn-api created
kubectl --context kind-mlops -n churn rollout status deployment/churn-api --timeout=180s
Waiting for deployment "churn-api" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "churn-api" rollout to finish: 1 of 2 updated replicas are available...
deployment "churn-api" successfully rolled out
```

چرا namespace را جدا اول اعمال می‌کنیم؟ چون در `apply -f k8s/` فایل‌ها به ترتیب الفبا خوانده می‌شوند و `configmap.yaml` قبل از `namespace.yaml` می‌آید؛ بدون namespace آماده، ConfigMap خطای `namespace "churn" not found` می‌داد.

وضعیت را ببینید:

```bash
make k8s-status
```

انتظار: چهار جدول پشت‌سرهم و در انتها تاریخچه‌ی rollout:

- <bdi dir="rtl">`deployment.apps/churn-api` با `READY 2/2`</bdi>
- یک `replicaset.apps/churn-api-<عدد-و-حرف>` با `DESIRED 2` و `READY 2`
- دو `pod/churn-api-<...>` هر دو `1/1` و `Running`
- <bdi dir="rtl">`service/churn-api` از نوع `ClusterIP` با پورت `80/TCP`</bdi>
- جدول `REVISION` / `CHANGE-CAUSE` با یک ردیف (revision شماره‌ی `1`)

**زنجیره را ببینید:** Deployment یک ReplicaSet ساخت، ReplicaSet دو Pod ساخت. نام pod از نام ReplicaSet شروع می‌شود (`churn-api-79dd5596d8-...`)؛ برای همین از نام pod می‌شود فهمید به کدام نسخه‌ی Deployment تعلق دارد. (حرف‌های وسط نام در سیستم شما فرق دارند.)

<bdi dir="rtl">pod‌ها را با جزئیات ببینید:</bdi>

```bash
k -n churn get pods -o wide
```

انتظار: دو pod با `READY 1/1`، `STATUS Running`، `RESTARTS 0`، هر کدام یک IP داخلی مثل `10.244.0.7` و `NODE` برابر `mlops-control-plane`. هر دو روی یک node هستند چون cluster ما یک node دارد.

بقیه‌ی منابع namespace را هم ببینید:

```bash
k -n churn get deploy,rs,svc,cm
```

انتظار: Deployment با `2/2`، یک ReplicaSet، Service از نوع `ClusterIP`، و دو ConfigMap: `churn-api-config` (با `DATA 3`، مال ما) و `kube-root-ca.crt` (خودکار ساخته شده، کاری به آن نداشته باشید).

## گام ۳ — دسترسی، لاگ و رویدادها (۱۵ دقیقه)

<bdi dir="rtl">Service از نوع ClusterIP فقط داخل cluster دیده می‌شود. برای تست از لپ‌تاپ یک تونل موقت می‌سازیم.</bdi>

**ترمینال ۲ را باز کنید** (یا یک tab تازه) و در آن:

```bash
cd ~/work/churn-mlops
```

```bash
make k8s-forward
```

انتظار: دو خط، و ترمینال پر می‌ماند (**نبندید و Ctrl+C نزنید**):

```
Forwarding from 127.0.0.1:8002 -> 8000
Forwarding from [::1]:8002 -> 8000
```

(`8002` پورت لپ‌تاپ است؛ پورت ۸۰۰۱ مال container جلسه‌ی ۹ بود و ۸۰۹۰ مال VM جلسه‌ی ۱۰.) `make k8s-forward` از Makefile اسم context را خودش می‌دهد، پس به alias نیازی ندارد.

**به ترمینال ۱ برگردید** (و اگر alias را زده‌اید ادامه دهید):

```bash
curl -s localhost:8002/ready
```

انتظار (شماره‌ی نسخه همان نسخه‌ی `@champion` شماست): `{"status":"ready","model_version":"2"}`

```bash
curl -s -X POST localhost:8002/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار:

```
{"churn_probability":0.9032,"churn":true,"threshold":0.5,"model_version":"2"}
```

همان عدد ۰٫۹۰۳۲ جلسه‌های ۸ تا ۱۰: برنامه همان است، فقط اجراکننده عوض شده.

### لاگ

```bash
k -n churn logs deploy/churn-api --tail=5
```

انتظار: اول یک خط `Found 2 pods, using pod/churn-api-...` (چون Deployment دو pod دارد، kubectl یکی را انتخاب کرد)، و بعد پنج خط JSON: درخواست‌های `/ready` و `/health` که خود Kubernetes برای probe می‌فرستد، و آخر `prediction` و `request POST /predict` با `"status": 200`. لاگ برنامه (JSON ساخت‌یافته جلسه‌ی ۸) همین‌جا است و به فایل نمی‌رود: برنامه روی stdout می‌نویسد و Kubernetes جمعش می‌کند.

### events

```bash
k -n churn get events --sort-by=.lastTimestamp
```

انتظار: به ترتیب زمان، رویدادهای ساخت: `Scheduled` (pod به node رسید)، `SuccessfulCreate` (ReplicaSet دو pod ساخت)، `Pulled` (image آماده شد؛ مثلاً `... in 19ms` چون قبلاً در node بود)، `Created`، `Started`. **یک خط `Warning` هم برای هر pod می‌بینید که نباید بترسید:**

```
Warning  Unhealthy  ...  Readiness probe failed: Get "http://10.244.0.6:8000/ready": dial tcp 10.244.0.6:8000: connect: connection refused
```

یعنی اولین آزمون readiness، پنج ثانیه بعد از شروع، رسید و uvicorn هنوز بالا نیامده بود (`connection refused`). این **عادی** است: pod فقط تا آن موقع `0/1` ماند و بعد آماده شد. فقط اگر این هشدار تکرار شد و pod آماده نشد باید نگران شد.

### describe

```bash
k -n churn describe pod -l app=churn-api | grep -E "^Name:|Limits|Requests|cpu|memory|Liveness|Readiness|Environment Variables from|churn-api-config"
```

انتظار: برای هر pod چند خط از جمله:

```
    Limits:
      cpu:     500m
      memory:  512Mi
    Requests:
      cpu:      100m
      memory:   256Mi
    Liveness:   http-get http://:http/health delay=10s timeout=1s period=10s successThreshold=1 failureThreshold=3
    Readiness:  http-get http://:http/ready delay=5s timeout=1s period=5s ...
    Environment Variables from:
      churn-api-config  ConfigMap  Optional: false
```

همان چیزی که در YAML نوشتید، همین‌جا از زبان cluster تأیید می‌شود. (اگر `describe` کامل را می‌خواهید بخوانید بدون `grep` اجرا کنید؛ بخش `Events:` آخر آن هم مفید است.)

### خود-ترمیمی (self-healing)

اول نام pod‌ها را ببینید:

```bash
k -n churn get pods
```

نام یکی از آنها را کپی کنید و جای `NAME` بگذارید (خودتان باید نام واقعی را بنویسید؛ چیزی مثل `churn-api-79dd5596d8-t9k5m`):

```bash
k -n churn delete pod NAME
```

انتظار: `pod "churn-api-..." deleted from churn namespace`. بلافاصله دوباره فهرست را ببینید:

```bash
k -n churn get pods
```

انتظار: باز **دو pod** هست، ولی یکی تازه است (`AGE` چند ثانیه)، و در ثانیه‌های اول `0/1 Running`. حدود ۱۲ ثانیه بعد دوباره بزنید و هر دو `1/1` می‌شوند. ReplicaSet دید که ۲ تا لازم است و فقط ۱ تا هست، پس خودش یکی ساخت. شما هیچ کاری نکردید. همین فرق Kubernetes با «یک container که با دست اجرا کردید» است. (برخلاف systemd جلسه‌ی ۱۰ این بار حتی لازم نبود ماشین سالم باشد؛ pod جدید ممکن است روی node دیگر بیاید.)

اگر ترمینال ۲ یک‌باره پیام `lost connection to pod` یا خطای مشابه داد: port-forward به یک pod مشخص وصل می‌شود، و آن pod را کشتید. در ترمینال ۲ دوباره `make k8s-forward` بزنید. در ادامه‌ی گام‌ها هم هر وقت pod‌ها عوض شدند همین کار را بکنید.

## گام ۴ — rollout و rollout undo (۱۵ دقیقه)

### به‌روزرسانی خراب

سناریو: کسی tag تازه‌ای را در Deployment گذاشته که وجود ندارد. image `0.7.1` را ما هرگز نساختیم:

```bash
k -n churn set image deployment/churn-api api=localhost:5001/churn-api:0.7.1
```

انتظار: `deployment.apps/churn-api image updated`

```bash
k -n churn rollout status deployment/churn-api --timeout=45s
```

انتظار: بعد از ۴۵ ثانیه:

```
Waiting for deployment "churn-api" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition
```

این پیام یعنی «چیزی درست پیش نرفت؛ **events را بخوان**». pod‌ها را ببینید:

```bash
k -n churn get pods
```

انتظار: سه pod. دو pod قدیمی `1/1 Running` و یک pod تازه با `0/1` و وضعیت `ErrImagePull` یا `ImagePullBackOff`:

```
churn-api-79dd5596d8-t9k5m   1/1   Running            0   76s
churn-api-79dd5596d8-xzg47   1/1   Running            0   76s
churn-api-b4f9664df-hdrhp    0/1   ImagePullBackOff   0   45s
```

(`BackOff` یعنی «دانلود شکست خورد و دوباره بعد از مدتی امتحان می‌کنم، هر بار با فاصله‌ی بیشتر».) علتش را از events بخوانید:

```bash
k -n churn get events --sort-by=.lastTimestamp
```

انتظار: خطی مثل زیر (کوتاه شده):

```
Failed to pull image "localhost:5001/churn-api:0.7.1": rpc error: code = NotFound desc = failed to pull and unpack image ... localhost:5001/churn-api:0.7.1: not found
```

در `Events` بعد از آن `Error: ErrImagePull` و `Error: ImagePullBackOff` هم می‌آید. علت روشن است: `not found` یعنی آن tag در registry نیست.

**نکته‌ی اصلی:** با اینکه rollout گیر کرد، کاربران هیچ مشکلی ندیدند. دو pod قدیمی هنوز `1/1` هستند و Service فقط به آنها ترافیک می‌دهد. این نتیجه‌ی `maxUnavailable: 0` است: تا pod تازه آماده نشود، قدیمی حذف نمی‌شود. اگر port-forward زنده است امتحان کنید:

```bash
curl -s localhost:8002/ready
```

انتظار: همچنان `{"status":"ready","model_version":"2"}`

تاریخچه‌ی Deployment:

```bash
k -n churn rollout history deployment/churn-api
```

انتظار:

```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

<bdi dir="rtl">revision شماره‌ی ۲ همین نسخه‌ی خراب است. ستون `CHANGE-CAUSE` خالی است و بعداً پرش می‌کنیم. حالا برگردید به نسخه‌ی قبل:</bdi>

```bash
k -n churn rollout undo deployment/churn-api
```

انتظار: دو خط. اول یک `Warning` و بعد خود نتیجه:

```
Warning: resource deployments/churn-api was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/churn-api rolled back
```

**هشدار را بفهمید:** `kubectl apply` یک یادداشت (annotation) روی Deployment می‌گذارد که می‌گوید «آخرین فایلی که اعمال شد این بود». `rollout undo` آن یادداشت را عوض نمی‌کند. یعنی فایل `deployment.yaml` شما و واقعیت cluster موقتاً کمی فرق دارند. اینجا ایرادی ندارد چون فایل ما هنوز image درست (`0.7.0`) را دارد. در تیم‌های واقعی، منبع حقیقت فایل‌ها در Git است و برگشت دائمی یعنی فایل را در Git درست کنید و دوباره `apply` کنید.

```bash
k -n churn rollout status deployment/churn-api
```

انتظار: `deployment "churn-api" successfully rolled out`

```bash
k -n churn rollout history deployment/churn-api
```

انتظار: دو ردیف، `2` و `3` (نه `1` و `2`). undo یک revision تازه (۳) با همان محتوای revision ۱ ساخت و ۱ را حذف کرد. شماره همیشه بالا می‌رود.

برای اینکه تاریخچه برای آدم‌ها خوانا باشد، دلیل تغییر را روی Deployment ثبت کنید:

```bash
k -n churn annotate deployment/churn-api kubernetes.io/change-cause="serve @champion again" --overwrite
```

```bash
k -n churn rollout history deployment/churn-api
```

انتظار: ردیف آخر (revision فعلی) حالا در ستون `CHANGE-CAUSE` متن `serve @champion again` را دارد.

### تغییر مدل با ConfigMap

حالا یک تغییر دیگر: به‌جای تغییر image، **نسخه‌ی مدل** را عوض می‌کنیم. ConfigMap را با دستور `patch` تغییر دهید تا مدل نسخه‌ی ۱ شود (به‌جای `@champion`):

```bash
k -n churn patch configmap churn-api-config -p '{"data":{"MODEL_URI":"models:/churn/1"}}'
```

انتظار: `configmap/churn-api-config patched`

<bdi dir="rtl">pod‌ها را بررسی کنید. برای اینکه مطمئن باشیم مستقیم از داخل یک pod می‌پرسیم (با port-forward ممکن است به pod دیگری برسید):</bdi>

```bash
k -n churn exec deploy/churn-api -- python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/ready').read().decode())"
```

انتظار: هنوز `{"status":"ready","model_version":"2"}`. **ConfigMap عوض شد ولی pod‌ها نه.** دلیل: متغیرهای محیطی فقط هنگام شروع pod خوانده می‌شوند. باید pod‌ها دوباره ساخته شوند، و ساده‌ترین راه، یک rolling restart است:

```bash
k -n churn rollout restart deployment/churn-api
```

```bash
k -n churn rollout status deployment/churn-api
```

انتظار: چند خط `Waiting for deployment...` و در انتها `successfully rolled out`.

```bash
k -n churn exec deploy/churn-api -- python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/ready').read().decode())"
```

انتظار: `{"status":"ready","model_version":"1"}`. حالا مدل نسخه‌ی ۱ است.

مشکل پیش آمد؛ آن را با `rollout undo` برمی‌گردانیم؟

```bash
k -n churn rollout undo deployment/churn-api
```

```bash
k -n churn rollout status deployment/churn-api
```

انتظار: `successfully rolled out`. حالا نسخه را بپرسید:

```bash
k -n churn exec deploy/churn-api -- python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/ready').read().decode())"
```

انتظار: **هنوز** `{"status":"ready","model_version":"1"}`!

چرا؟ `rollout undo` فقط **قالب pod** (image، probe، resources...) را برمی‌گرداند. ConfigMap بخشی از تاریخچه‌ی Deployment نیست و جدا زندگی می‌کند. pod‌های تازه همان ConfigMap فعلی را (که `models:/churn/1` دارد) می‌خوانند. این یک دام واقعی است: **undo همه‌چیز را برنمی‌گرداند.**

راه درست: فایل را به حالت درست خودش (که در Git و پوشه‌ی `k8s/` است) برگردانید، دوباره اعمال کنید، و pod‌ها را restart کنید:

```bash
k apply -f k8s/configmap.yaml
```

انتظار: `configmap/churn-api-config configured`

```bash
k -n churn rollout restart deployment/churn-api
```

```bash
k -n churn rollout status deployment/churn-api
```

```bash
k -n churn exec deploy/churn-api -- python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/ready').read().decode())"
```

انتظار: `{"status":"ready","model_version":"2"}`، یعنی دوباره `@champion`. درس: **فایل‌های `k8s/` در Git منبع حقیقت‌اند.** هر تغییر دستی (`patch`، `set image`) را بعد از تست یا به فایل منتقل کنید، یا با `apply` از فایل پاک کنید.

اگر پورت‌فوروارد در ترمینال ۲ قطع شده، همان‌جا دوباره `make k8s-forward` بزنید (pod‌هایی که به آنها وصل بود عوض شدند).

## گام ۵ — readiness در عمل و پایان (۱۵ دقیقه)

آخرین آزمایش: ببینیم readiness probe در یک خرابی واقعی چه می‌کند. سناریو: MLflow خاموش می‌شود، و درست در همان لحظه یک rollout شروع می‌شود (مثلاً یک deploy عادی).

ابتدا در ترمینال ۲ بررسی کنید port-forward زنده است. اگر قطع شده، دوباره `make k8s-forward` بزنید. بعد در ترمینال ۱ MLflow را خاموش کنید:

```bash
cd ~/mlops-lab/compose && docker compose stop mlflow
```

```bash
cd ~/work/churn-mlops
```

حالا یک rollout شروع کنید:

```bash
k -n churn rollout restart deployment/churn-api
```

```bash
k -n churn rollout status deployment/churn-api --timeout=40s
```

انتظار: بعد از ۴۰ ثانیه `error: timed out waiting for the condition`. pod‌ها را ببینید:

```bash
k -n churn get pods
```

انتظار: یک pod تازه با `0/1 Running` (و `RESTARTS 0`) و دو pod قدیمی `1/1`. تازه‌ای **نه مرده و نه restart شده؛ فقط آماده نیست.** علت را در لاگ همان pod ببینید (نام pod با `0/1` را بگذارید):

```bash
k -n churn logs NAME | grep model_load_failed
```

(فقط `--tail` کافی نیست: این خط یک بار هنگام روشن شدن pod چاپ می‌شود و probeها هر چند ثانیه خط تازه می‌نویسند.) انتظار: یک خط با `"event": "model_load_failed"` و `"uri": "models:/churn@champion"` و پیامی مثل `MLflow server not reachable at http://mlflow:5000 (ConnectionError)`. و در events:

```bash
k -n churn get events --sort-by=.lastTimestamp
```

انتظار: خطی مثل `Readiness probe failed: HTTP probe failed with statuscode: 503`. برنامه خودش ۵۰۳ می‌دهد چون مدل را نتوانسته بار کند.

حالا مهم‌ترین نکته: **کاربران چه می‌بینند؟** چند بار پشت‌سرهم درخواست بزنید:

```bash
for i in 1 2 3 4; do curl -s localhost:8002/ready; echo; done
```

انتظار: چهار بار `{"status":"ready","model_version":"2"}`. هیچ خطایی نیست، چون Service فقط به دو pod قدیمی (آماده) ترافیک می‌دهد و pod ناآماده را کنار گذاشته. این کار readiness است.

و **liveness چه کرد؟** هیچ. `RESTARTS` صفر ماند، چون `/health` همچنان ۲۰۰ می‌داد (برنامه زنده بود، فقط مدل نداشت). Restart هم کمکی نمی‌کرد؛ مشکل MLflow بود، نه برنامه. فرق این دو را حفظ کنید:

| probe | سؤال | شکست یعنی |
| --- | --- | --- |
| readiness | آماده‌ی ترافیک هستی؟ | از Service بیرون بمان (restart نه) |
| liveness | زنده‌ای؟ | container را restart کن |

<bdi dir="rtl">MLflow را دوباره روشن کنید:</bdi>

```bash
cd ~/mlops-lab/compose && docker compose start mlflow
```

```bash
curl -s http://localhost:5050/health
```

انتظار: `OK` (اگر چند ثانیه‌ی اول خطا داد، کمی صبر کنید و دوباره بزنید)

```bash
cd ~/work/churn-mlops
```

```bash
k -n churn get pods
```

انتظار: **pod ناآماده هنوز `0/1` است** و خودش درست نمی‌شود. چرا؟ برنامه مدل را فقط هنگام شروع بار می‌کند؛ بعد از آن دیگر تلاش نمی‌کند. راه‌حل: همان pod را بکشید تا جانشین تازه‌اش مدل را بار کند (نام pod با `0/1` را بگذارید):

```bash
k -n churn delete pod NAME
```

```bash
k -n churn rollout status deployment/churn-api --timeout=120s
```

انتظار: `successfully rolled out`. rollout که گیر کرده بود تمام شد. بررسی نهایی:

```bash
k -n churn get pods
```

انتظار: دو pod، هر دو `1/1 Running`.

این رفتار («ناآماده ماندن تا کسی دخالت کند») نقطه‌ی ضعف است و در تکلیف روی آن فکر می‌کنید.

### <bdi dir="rtl">commit و tag</bdi>

وضعیت Git:

```bash
git status --short
```

انتظار: `Makefile` با `M` و `k8s/` با `??`.

```bash
git add k8s Makefile && git commit -m "feat: deploy the API to Kubernetes (kind)"
```

انتظار: پنج فایل تغییر کرده است (`Makefile` به‌روز شد و چهار فایل داخل `k8s/` تازه‌اند).

```bash
git status --short
```

انتظار: خالی.

```bash
git push -u origin feature/k8s
```

در Gitea (`http://localhost:3000`) برای شاخه‌ی `feature/k8s` یک Pull Request بسازید و در توضیح بنویسید:

```
Deploy the inference API to Kubernetes (kind cluster "mlops").
k8s/: namespace churn, ConfigMap, Deployment (2 replicas, rolling update with maxUnavailable 0,
readiness /ready + liveness /health, requests/limits), ClusterIP Service.
Makefile: k8s-up, k8s-deploy, k8s-status, k8s-forward (every kubectl call uses --context kind-mlops).
No Secret needed: MLflow proxies the artifacts.
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.9.0 -m "Session 11: Kubernetes deploy on kind"
```

```bash
git push origin v0.9.0
```

---

## بررسی پایان کار

<bdi dir="rtl">cluster و pod‌ها باید روشن باشند (`k -n churn get pods` دو pod `1/1` را نشان بدهد)، و MLflow هم باید روشن باشد. بعد:</bdi>

```bash
~/mlops-lab/scripts/verify.sh s11
```

انتظار: همه‌ی خط‌ها `[PASS]` باشند. اگر خطی `[FAIL]` شد، متن آن می‌گوید چه چیزی کم است؛ جدول عیب‌یابی را ببینید. خروجی را همراه با تکلیف برای مدرس بفرستید.

## معیار پایان کار

- [ ] شاخه‌ی `feature/k8s` ساخته شد و با Pull Request وارد `main` شد
- [ ] `make k8s-up` اجرا شد و `kubectl config current-context` برابر `kind-mlops` است
- [ ] `alias k` را ساختید و می‌دانید چرا نباید بدون `--context` کار کرد
- [ ] `make k8s-deploy` تمام شد و `k -n churn get pods` دو pod با `1/1` نشان می‌دهد
- [ ] از لپ‌تاپ با port-forward روی ۸۰۰۲ جواب `/ready` و `/predict` را گرفتید (`churn_probability` برابر ۰٫۹۰۳۲)
- [ ] یک pod را حذف کردید و دیدید خودش دوباره ساخته شد
- [ ] image با tag ناموجود را گذاشتید، دو pod قدیمی همچنان سرویس دادند، و با `rollout undo` برگشتید
- [ ] می‌توانید توضیح دهید چرا `rollout undo` تغییر ConfigMap را برنگرداند و راه درست چه بود
- [ ] دیدید که با MLflow خاموش، pod جدید `0/1` ماند و کاربران همچنان جواب گرفتند
- [ ] فرق readinessProbe و livenessProbe را می‌توانید با یک مثال بگویید
- [ ] می‌توانید بگویید چرا این API به Secret نیاز ندارد
- [ ] tag `v0.9.0` روی `main` است و push شده
- [ ] `~/mlops-lab/scripts/verify.sh s11` همه‌ی بررسی‌ها را `PASS` داد

## عیب‌یابی

اصل کلی: وقتی چیزی درست نشد، **اول events را بخوانید**: `k -n churn get events --sort-by=.lastTimestamp`، بعد `k -n churn describe pod NAME`، بعد `k -n churn logs NAME`.

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| pod با وضعیت `ErrImagePull` یا `ImagePullBackOff` | tag در registry نیست (غلط تایپی یا هنوز `make push` نزده‌اید)، یا registry خاموش است | `k -n churn describe pod NAME` و بخش `Events`. بررسی کنید `docker ps --filter name=kind-registry` در حالت `Up` باشد، و `make push` را بزنید. در `deployment.yaml` نام و tag را با دقت مقایسه کنید (`localhost:5001/churn-api:0.7.0`) |
| pod‌ها `0/1 Running` می‌مانند و events می‌گوید `Readiness probe failed: HTTP probe failed with statuscode: 503` | برنامه مدل را بار نکرده: MLflow خاموش است، یا node به شبکه‌ی `mlops-lab` وصل نیست | `curl -s http://localhost:5050/health` باید `OK` باشد. بعد `docker network connect mlops-lab mlops-control-plane` (اگر گفت قبلاً وصل است ایرادی ندارد). علت را در `k -n churn logs NAME` ببینید (`model_load_failed`). بعد pod‌های ناآماده را حذف کنید تا دوباره بسازند |
| `CrashLoopBackOff` و در `describe` عبارت `OOMKilled` با `Exit Code: 137` | حافظه‌ی مصرفی از `limits.memory` بیشتر شد و kernel برنامه را کشت. سقف خیلی کوچک است | در `k -n churn describe pod NAME` بخش `Last State` را ببینید. در `deployment.yaml` مقدار limits را بالا ببرید (در کار عادی ما هر pod حدود 180Mi مصرف دارد، پس سقف باید مقداری بالاتر از آن باشد) و `apply` کنید. اگر با `set resources` خراب کردید: `k -n churn rollout undo deployment/churn-api` |
| `curl: (7) Failed to connect to localhost port 8002` یا `connection refused` | port-forward اجرا نیست، یا قطع شده (pod که به آن وصل بود عوض شد) | در ترمینال ۲ `make k8s-forward` را دوباره بزنید. باید `Forwarding from 127.0.0.1:8002` ببینید |
| `make k8s-forward`: `unable to listen on port 8002` / `address already in use` | برنامه‌ی دیگری (یا یک port-forward قدیمی) پورت ۸۰۰۲ را گرفته | آن را ببندید، یا پورت دیگر بدهید: `make k8s-forward FORWARD_PORT=8003` و در `curl` هم همان عدد را بنویسید |
| `kubectl config current-context` چیزی غیر از `kind-mlops` نشان می‌دهد | context فعلی به cluster دیگری اشاره می‌کند (مثلاً کاری) | با `k` (که `--context kind-mlops` دارد) و با `make` ادامه دهید و **بدون context** به cluster دیگر دستور نزنید. برای تنظیم: `kubectl config use-context kind-mlops`. با `kubectl config get-contexts` همه‌ی context‌ها را ببینید |
| `k: command not found` | alias در این ترمینال تعریف نشده | `alias k='kubectl --context kind-mlops'` را دوباره بزنید (برای هر ترمینال تازه) |
| `kind: command not found` یا `kubectl: command not found` | ابزار نصب نیست | از بسته‌ی آفلاین دوره نصب کنید (`~/mlops-lab/scripts/install-from-bundle.sh`) یا از مدرس بپرسید؛ بعد `~/mlops-lab/s11/preflight.sh` را دوباره بزنید |
| ساخت cluster شکست می‌خورد، یا `Waiting ≤ 2m0s for control-plane` تمام نمی‌شود | حافظه‌ی Docker کم است، یا Docker روشن نیست، یا یک cluster نیمه‌کاره مانده | حافظه‌ی Docker را به ۸ گیگابایت یا بیشتر برسانید. اگر نیمه‌کاره ساخته شده: `kind delete cluster --name mlops` و دوباره `make k8s-up` (فقط cluster خودتان با همین نام پاک می‌شود) |
| `Error from server (NotFound): namespaces "churn" not found` | فایل‌ها را قبل از ساخت namespace اعمال کردید (`apply -f k8s/` تنها) | اول `k apply -f k8s/namespace.yaml` بعد `k apply -f k8s/`. یا ساده‌تر: `make k8s-deploy` که ترتیب را رعایت می‌کند |
| `error: timed out waiting for the condition` در `rollout status` | rollout تا مهلت تمام نشد؛ خود این پیام علت نیست | همیشه events را بخوانید: `k -n churn get events --sort-by=.lastTimestamp` و `k -n churn get pods` |
| `The connection to the server ... was refused` / `Unable to connect to the server` | cluster خاموش است (Docker ری‌استارت شده) یا context اشتباه است | `docker ps --filter name=mlops-control-plane` را ببینید. اگر نیست یا `Exited` است، `docker start mlops-control-plane` یا دوباره `make k8s-up` (از نام کامل container استفاده کنید) |
| `make: *** No rule to make target 'k8s-up'` | Makefile جلسه‌ی ۱۰ هنوز جایگزین نشده | در گام ۱ `cp $K/Makefile .` را بزنید |
| `make k8s-up`: `kind-up.sh: No such file or directory` | مخزن دوره به‌روز نیست | `git -C ~/mlops-lab pull` |
| `Cannot connect to the Docker daemon` | Docker روشن نیست | macOS: Docker Desktop (یا `colima start`) را روشن کنید. Ubuntu و WSL: `sudo systemctl start docker` |
| Windows: دستورها خطای عجیب می‌دهند | از PowerShell استفاده می‌کنید | همه‌ی دستورها را داخل WSL Ubuntu بزنید |
| `verify.sh s11` در یکی از بررسی‌ها `FAIL` می‌دهد | cluster یا pod‌ها خاموش‌اند، یا commit یا tag کم است | متن همان خط را بخوانید؛ `k -n churn get pods` و `git describe --tags` را بررسی کنید و گام مربوط را کامل کنید |
| tag `v0.9.0` روی commit قدیمی است (پیش از merge زده شده) | tag را پیش از `git switch main && git pull` ساخته‌اید | `git tag -d v0.9.0 && git push origin :refs/tags/v0.9.0`، بعد روی `main` به‌روز دوباره tag و push |

*<bdi dir="rtl">*cluster را نگه دارید.** در جلسه‌های ۱۲ و ۱۳ (ingress، Helm، مانیتورینگ) روی همین cluster کار می‌کنیم. فقط وقتی مدرس گفت (آخر دوره) cluster را پاک کنید:</bdi>

```text
kind delete cluster --name mlops
```

سرویس‌های آزمایشگاه (SeaweedFS، MLflow، registry محلی) را هم نگه دارید و `docker compose down -v` نزنید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

</div>
