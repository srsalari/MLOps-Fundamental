<div dir="rtl">

# توضیح کد جلسه‌ی ۱۱

در جلسه‌ی ۱۰ سرویس را روی VM با Ansible مستقر کردیم. در این جلسه همان سرویس را روی **Kubernetes** اجرا می‌کنیم. کد پایتون برنامه و image جلسه‌ی ۹ تغییر نمی‌کنند؛ این جلسه فایل‌های «توصیف وضعیت دلخواه» دارد که به cluster می‌دهیم.

فایل‌های این جلسه:

- فایل `k8s/namespace.yaml`: یک «اتاق» جدا به نام `churn`.
- فایل `k8s/configmap.yaml`: تنظیم‌های برنامه (غیرمحرمانه).
- فایل `k8s/deployment.yaml`: دو pod از image، با probe‌ها و منابع. مهم‌ترین فایل این جلسه است.
- فایل `k8s/service.yaml`: آدرس ثابت جلوی pod‌ها.
- فایل `Makefile`: متغیرها و هدف‌های تازه برای cluster.
- فایل‌های مخزن دوره که فقط اجرا می‌کنید: `scripts/kind-up.sh` و `k8s/kind-config.yaml`.
- فایل `preflight.sh`: بررسی آمادگی پیش از کلاس (کد آموزشی نیست و اینجا توضیح داده نمی‌شود).

کامنت‌های داخل فایل‌ها عمداً انگلیسی هستند. شرح فارسی همه‌چیز در همین فایل است.

---

## مفهوم پایه: وضعیت دلخواه و حلقه‌ی کنترل

یک فایل YAML در Kubernetes نمی‌گوید «این دستورها را اجرا کن». می‌گوید «من **این** را می‌خواهم». مثلاً `replicas: 2` یعنی «دو pod». Kubernetes مدام وضعیت واقعی را با وضعیت دلخواه مقایسه می‌کند و هر جا فرق باشد، تصحیح می‌کند. به این حلقه «کنترلر» می‌گویند. به همین دلیل وقتی pod را حذف کردید، خودش دوباره ساخته شد: وضعیت واقعی (۱ pod) با دلخواه (۲ pod) فرق داشت.

هر فایل YAML چهار بخش بالایی مشترک دارد:

| فیلد | معنی |
|---|---|
| `apiVersion` | نسخه‌ی API این نوع منبع (`v1` برای چیزهای پایه، `apps/v1` برای Deployment) |
| `kind` | نوع منبع (`Namespace`، `ConfigMap`، `Deployment`، `Service`) |
| `metadata` | نام و ویژگی‌های شناسایی (نام، namespace، label) |
| `spec` یا `data` | خود محتوا: چه می‌خواهیم |

نوشتار YAML با فاصله (indent) کار می‌کند، با دو فاصله برای هر سطح، و **هرگز با TAB**. خط‌هایی که با `- ` شروع می‌شوند عضو یک فهرست‌اند.

---

## فایل `k8s/namespace.yaml`

**کار فایل:** یک namespace به نام `churn` می‌سازد. همه‌ی منابع سرویس ما داخل آن می‌روند، تا از منابع دیگر (مثلاً جلسه‌های بعد: ingress، monitoring) جدا باشند و بشود همه را با یک دستور پاک کرد.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: churn
```

- `apiVersion: v1` و `kind: Namespace`: نوع منبع.
- `metadata.name: churn`: نام namespace. هیچ `spec` لازم نیست.

نکته: Namespace خودش در هیچ namespace نیست (یک منبع «سراسری» cluster است)، برای همین `namespace:` ندارد.

---

## فایل `k8s/configmap.yaml`

**کار فایل:** تنظیم‌های برنامه را از image جدا نگه می‌دارد. image یک بار ساخته می‌شود، ولی در هر محیط تنظیم دیگری می‌خواهد.

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: churn-api-config
  namespace: churn
```

- `kind: ConfigMap`: مجموعه‌ای از جفت‌های کلید و مقدار.
- `name: churn-api-config`: نامی که Deployment به آن اشاره می‌کند (در `configMapRef`).
- `namespace: churn`: باید همان namespace Deployment باشد؛ ConfigMap فقط در namespace خودش دیده می‌شود.

```yaml
data:
  MLFLOW_TRACKING_URI: http://mlflow:5000
  MODEL_URI: models:/churn@champion
  PREDICT_THRESHOLD: "0.5"
```

سه جفت کلید و مقدار:

| کلید | معنی |
|---|---|
| `MLFLOW_TRACKING_URI` | آدرس MLflow داخل شبکه‌ی Docker به نام `mlops-lab`. نام `mlflow` فقط وقتی کار می‌کند که node به آن شبکه وصل شده باشد (کاری که `make k8s-up` می‌کند) |
| `MODEL_URI` | کدام مدل را سرویس بدهد. `models:/churn@champion` یعنی نسخه‌ای که alias آن `champion` است. برای ثابت کردن نسخه: `models:/churn/1` |
| `PREDICT_THRESHOLD` | آستانه‌ی تصمیم (احتمال بالاتر از آن یعنی `churn: true`) |

مقدار `"0.5"` عمداً داخل کوتیشن است. در ConfigMap همه‌ی مقدارها باید **رشته** باشند؛ بدون کوتیشن، YAML آن را عدد می‌خواند و خطا می‌دهد.

متغیر چهارمی هم هست که اینجا نیست: `MLFLOW_ENABLE_PROXY_MULTIPART_DOWNLOAD=false` از قبل داخل image جلسه‌ی ۹ تنظیم شده، پس لازم نبود دوباره بنویسیم.

**چرا Secret نداریم؟** هیچ‌کدام از این سه مقدار محرمانه نیست. و برنامه کلیدی ندارد که بخواهد در Secret بگذارد: سرور MLflow خودش مدل را از S3 می‌گیرد و برای برنامه می‌فرستد (artifacts پروکسی‌شده)، پس pod به SeaweedFS دسترسی مستقیم و کلید نمی‌خواهد.

یک ویژگی مهم: **تغییر ConfigMap، pod‌های در حال اجرا را عوض نمی‌کند.** متغیرهای محیطی فقط هنگام ساخت pod خوانده می‌شوند. بعد از تغییر ConfigMap باید `rollout restart` بزنید. و `rollout undo` تغییر ConfigMap را برنمی‌گرداند، چون ConfigMap بخشی از تاریخچه‌ی Deployment نیست.

---

## فایل `k8s/deployment.yaml`

**کار فایل:** می‌گوید «دو کپی از این image اجرا کن، با این آزمون‌های سلامت و این سقف منابع، و هر وقت چیزی تغییر کرد، قدم‌به‌قدم عوض کن».

### سربرگ

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: churn-api
  namespace: churn
  labels:
    app: churn-api
```

- `apiVersion: apps/v1`: Deployment در گروه `apps` است.
- `name: churn-api`: نام Deployment (در دستورها: `deployment/churn-api`).
- `labels: app: churn-api`: برچسب روی خود Deployment؛ برای ما فقط راحتی در جست‌وجو است (با `-l app=churn-api` می‌شود فیلتر کرد). برچسب مهم‌تر روی **pod‌ها** است که پایین‌تر می‌آید.

### replicas و selector

```yaml
spec:
  replicas: 2
  selector:
    matchLabels:
      app: churn-api
```

- `replicas: 2`: همیشه دو pod. این عدد وضعیت دلخواه است. با `k -n churn scale deployment/churn-api --replicas=3` موقتاً عوض می‌شود، ولی منبع حقیقت فایل است.
- `selector.matchLabels`: Deployment چطور می‌فهمد کدام pod‌ها مال اوست؟ pod‌هایی که برچسب `app: churn-api` دارند. **این باید دقیقاً با برچسب `template.metadata.labels` یکی باشد**، وگرنه Kubernetes فایل را رد می‌کند. (بعد از ساخته شدن Deployment، selector قابل تغییر نیست.)

### strategy

```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
```

- `type: RollingUpdate`: به‌روزرسانی مرحله‌ای (پیش‌فرض). گزینه‌ی دیگر `Recreate` است که همه را می‌کشد و بعد می‌سازد، یعنی خاموشی دارد.
- `maxUnavailable: 0`: هیچ‌وقت نگذار تعداد pod‌های **آماده** از `replicas` کمتر شود. یعنی قدیمی را فقط وقتی حذف کن که جایگزینش آماده باشد.
- `maxSurge: 1`: در حین کار یک pod **اضافه** هم مجاز است (یعنی تا ۳ pod).

نتیجه: به‌روزرسانی چنین پیش می‌رود: یک pod تازه ساخته می‌شود (۳ pod)، صبر می‌کنیم آماده شود، یک قدیمی حذف می‌شود (۲ pod)، دوباره تکرار. اگر pod تازه هیچ‌وقت آماده نشد (مثل image ناموجود)، قدیمی‌ها دست‌نخورده می‌مانند و کاربر چیزی نمی‌فهمد. همین چیزی بود که در آزمایش دیدید.

### template: قالب pod

```yaml
  template:
    metadata:
      labels:
        app: churn-api
    spec:
```

`template` شکل هر pod است. ReplicaSet از روی آن pod می‌سازد. `labels: app: churn-api` همان برچسبی است که `selector` (هم در Deployment و هم در Service) دنبالش می‌گردد. **تغییر هر چیز داخل `template` یک rollout تازه (و ReplicaSet تازه) می‌سازد**؛ تغییر `replicas` نمی‌سازد.

### securityContext

```yaml
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
```

- `runAsNonRoot: true`: اگر container بخواهد با root اجرا شود، Kubernetes آن را شروع نمی‌کند.
- `runAsUser: 10001`: با کاربر شماره‌ی ۱۰۰۰۱ اجرا شود.

چرا هر دو؟ در `Dockerfile` جلسه‌ی ۹ نوشتیم `USER app`، یعنی کاربر با **نام**. Kubernetes برای بررسی `runAsNonRoot` یک **عدد** می‌خواهد و نمی‌تواند نام را به عدد تبدیل کند. بدون `runAsUser` شروع pod با خطا رد می‌شد (Kubernetes نمی‌تواند ثابت کند کاربر `app` غیر root است). عدد ۱۰۰۰۱ همان uid کاربر `app` در image است.

### container

```yaml
      containers:
        - name: api
          image: localhost:5001/churn-api:0.7.0
          ports:
            - name: http
              containerPort: 8000
```

- `containers:` فهرست container‌های pod؛ ما یکی داریم. خط `- name: api` عضو اول فهرست است.
- `name: api`: نام container (در دستور `set image ... api=...` همین نام می‌آید).
- `image: localhost:5001/churn-api:0.7.0`: image از registry محلی. نکته‌ی مهم: tag را **ثابت** و مشخص می‌نویسیم، نه `latest`. با `latest` معلوم نیست دقیقاً کدام نسخه اجرا می‌شود و rollback معنی ندارد. نام `localhost:5001` را node به registry واقعی (`kind-registry`) نگاشت می‌کند (کاری که `kind-up.sh` انجام می‌دهد).
- `ports`: پورتی که برنامه در آن گوش می‌دهد. `name: http` یک **نام** برای پورت است و `containerPort: 8000` شماره‌اش. Service و probe‌ها با همین نام به آن اشاره می‌کنند، پس اگر روزی پورت برنامه عوض شود، فقط همین یک خط عوض می‌شود. (این فیلد فقط توضیح و نام‌گذاری است؛ پورت را باز نمی‌کند.)

### envFrom

```yaml
          envFrom:
            - configMapRef:
                name: churn-api-config
```

همه‌ی کلیدهای ConfigMap به نام `churn-api-config` را به متغیر محیطی همین container تبدیل کن: `MLFLOW_TRACKING_URI`، `MODEL_URI`، `PREDICT_THRESHOLD`. برنامه همان‌طور که در جلسه‌های ۸ و ۹ از محیط می‌خواند، می‌خواند. اگر ConfigMap با این نام وجود نداشته باشد، pod شروع نمی‌شود و در `describe` خطا می‌بینید (`Optional: false` در خروجی `describe` یعنی همین: وجود ConfigMap اجباری است).

### readinessProbe

```yaml
          readinessProbe:
            httpGet:
              path: /ready
              port: http
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3
```

سؤال این probe: «آیا این pod آماده‌ی دریافت ترافیک است؟»

- `httpGet` با `path: /ready`: Kubernetes یک `GET /ready` می‌فرستد. پاسخ ۲۰۰ تا ۳۹۹ یعنی موفق. در برنامه‌ی ما `/ready` تا وقتی مدل بار نشده ۵۰۳ می‌دهد.
- `port: http`: به پورتی با نام `http` (همان ۸۰۰۰). نام را بالاتر تعریف کردیم.
- `initialDelaySeconds: 5`: ۵ ثانیه بعد از شروع container اولین آزمون. (برای همین یک هشدار `connection refused` در events می‌بینید: uvicorn هنوز بالا نیامده.)
- `periodSeconds: 5`: هر ۵ ثانیه تکرار.
- `failureThreshold: 3`: سه شکست پشت‌سرهم لازم است تا pod «ناآماده» اعلام شود.

وقتی readiness شکست می‌خورد، **pod از Service بیرون می‌آید (ترافیک نمی‌گیرد)، ولی restart نمی‌شود.** و در rollout، pod ناآماده را «آماده» حساب نمی‌کنند، پس `maxUnavailable: 0` قدیمی را حذف نمی‌کند.

### livenessProbe

```yaml
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            failureThreshold: 3
```

سؤال این probe: «آیا برنامه زنده است یا گیر کرده؟»

- مسیر `/health` فقط می‌پرسد process جواب می‌دهد؛ به MLflow و مدل کاری ندارد.
- `initialDelaySeconds: 10`: بیشتر از readiness، تا برنامه فرصت شروع داشته باشد.
- `periodSeconds: 10` و `failureThreshold: 3`: بعد از ۳ شکست پشت‌سرهم (حدود ۳۰ ثانیه) container **restart** می‌شود.

چرا `/health` و `/ready` را جدا گرفتیم؟ اگر liveness از `/ready` استفاده می‌کرد، وقتی MLflow خاموش می‌شد و مدل بار نمی‌شد، Kubernetes pod را دائم restart می‌کرد، بی‌فایده (چون مشکل از MLflow است) و با هر restart خرابی بدتر می‌شد. قاعده: liveness فقط «آیا خودم گیر کرده‌ام» را بپرسد؛ وابستگی‌های بیرونی را readiness بپرسد.

### resources

```yaml
          resources:
            requests:
              cpu: 100m
              memory: 256Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

| فیلد | معنی |
|---|---|
| `requests.cpu: 100m` | حداقل یک‌دهم هسته‌ی پردازنده رزرو می‌شود (`m` = هزارم هسته). scheduler با همین عدد pod را روی node جا می‌دهد |
| `requests.memory: 256Mi` | حداقل ۲۵۶ مگابایت (دودویی) حافظه رزرو می‌شود |
| `limits.cpu: 500m` | سقف پردازنده. بیشتر از آن **کند** می‌شود (throttle)، نه کشته |
| `limits.memory: 512Mi` | سقف حافظه. بیشتر از آن container با **`OOMKilled`** (کد خروج ۱۳۷) کشته می‌شود |

در اندازه‌گیری ما هر pod حدود ۱۸۰ مگابایت حافظه مصرف کرد، پس ۵۱۲ مگابایت جای کافی دارد. اگر سقف را خیلی کوچک بگذارید (مثلاً ۱۲۸ مگابایت)، pod دائم `OOMKilled` و `CrashLoopBackOff` می‌شود؛ این در تکلیف تمرین می‌شود. تفاوت پردازنده و حافظه مهم است: پردازنده «فشردنی» است (کندتر می‌شود)، ولی حافظه نه (کشته می‌شود).

---

## فایل `k8s/service.yaml`

**کار فایل:** pod‌ها می‌میرند و با IP دیگری زنده می‌شوند. Service یک نام و آدرس **ثابت** جلوی آنهاست و بین pod‌های آماده تقسیم می‌کند.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: churn-api
  namespace: churn
```

`name: churn-api`: داخل cluster و همان namespace می‌شود با آدرس `churn-api` (یا `churn-api.churn`) به آن رسید.

```yaml
spec:
  selector:
    app: churn-api
```

`selector`: Service pod‌هایی را هدف می‌گیرد که برچسب `app: churn-api` دارند، یعنی همان pod‌هایی که Deployment ساخت. این **تنها** رابطه‌ی Service با Deployment است؛ هیچ اشاره‌ی مستقیمی به نام Deployment نیست. از بین این pod‌ها فقط آنهایی که readiness آنها موفق است ترافیک می‌گیرند.

```yaml
  ports:
    - name: http
      port: 80
      targetPort: http
```

- `port: 80`: پورتی که Service در آن گوش می‌دهد.
- `targetPort: http`: ترافیک را به پورت **با نام** `http` در pod می‌فرستد، یعنی همان `containerPort: 8000` که در Deployment نام `http` گرفت. به همین دلیل Service شماره‌ی ۸۰۰۰ را نمی‌داند.
- نوع Service ننوشته شده، یعنی پیش‌فرض `ClusterIP`: آدرس فقط داخل cluster. برای دیدن از لپ‌تاپ `port-forward` می‌زنیم (در جلسه‌ی ۱۲ با Ingress بدون port-forward).

### زنجیره‌ی ارتباط همه‌ی فایل‌ها

```text
ConfigMap churn-api-config  <-- envFrom (نام) -- Deployment churn-api
                                                     |
                                    template.labels: app=churn-api
                                                     |   (ReplicaSet دو Pod می‌سازد)
Service churn-api -- selector: app=churn-api --> Pod ها (فقط آماده‌ها)
   port 80 --> targetPort "http" --> containerPort 8000 (نام http)
```

سه اتصال را حفظ کنید: **نام ConfigMap** (در `envFrom`)، **برچسب `app: churn-api`** (در selector Deployment، قالب pod و selector Service)، و **نام پورت `http`** (در Deployment، probe‌ها و Service). غلط تایپی در هر کدام معمولاً یک خطای ساکت است: مثلاً Service بدون endpoint و اتصال بی‌جواب.

---

## فایل `Makefile`

**کار فایل:** همان Makefile جلسه‌ی ۱۰ است (هدف‌های `data` تا `rollback`) به‌علاوه‌ی متغیرها و چهار هدف تازه. فقط بخش جدید توضیح داده می‌شود.

```makefile
.PHONY: ... k8s-up k8s-deploy k8s-status k8s-forward
```

چهار نام تازه به فهرست هدف‌هایی که نام فایل نیستند اضافه شده است.

```makefile
CLUSTER ?= mlops
KCTX ?= kind-$(CLUSTER)
KUBECTL = kubectl --context $(KCTX)
LAB_DIR ?= $(HOME)/mlops-lab
FORWARD_PORT ?= 8002
```

| متغیر | معنی |
|---|---|
| `CLUSTER` | نام cluster kind (`mlops`) |
| `KCTX` | نام context که kind می‌سازد: همیشه `kind-` و نام cluster. با `$(CLUSTER)` ساخته می‌شود، پس اگر cluster را عوض کنید خودش دنبال می‌آید |
| `KUBECTL` | دستور کامل `kubectl --context kind-mlops`. با `=` (بدون `?`) نوشته شده چون قرار نیست از بیرون عوض شود، ولی چون از `KCTX` ساخته می‌شود تغییر `KCTX` را می‌گیرد |
| `LAB_DIR` | مخزن دوره، که `kind-up.sh` در آن است |
| `FORWARD_PORT` | پورت لپ‌تاپ برای port-forward (`8002`؛ ۸۰۰۱ مال جلسه‌ی ۹ و ۸۰۹۰ مال جلسه‌ی ۱۰ است) |

علامت `?=` یعنی فقط اگر از بیرون مقدار داده نشده باشد (مثلاً `make k8s-forward FORWARD_PORT=8003`). دلیل اصلی `KUBECTL`: هر دستور kubectl در Makefile صریحاً context را می‌گوید، پس اگر context فعلی شما cluster دیگری باشد، Makefile هیچ‌وقت به آن نمی‌رسد.

```makefile
k8s-up:
	$(LAB_DIR)/scripts/kind-up.sh
	docker network connect $(NETWORK) $(CLUSTER)-control-plane 2>/dev/null || true
```

هدف `k8s-up` دو دستور دارد:

1. `kind-up.sh`: اسکریپت دوره، که در بخش بعد توضیح داده شده (registry و cluster).
2. `docker network connect`: container node (نامش همیشه `<cluster>-control-plane` است، یعنی `mlops-control-plane`) را به شبکه‌ی `mlops-lab` وصل می‌کند. `$(NETWORK)` از Makefile قدیمی است (`mlops-lab`). دلیل: kind به‌طور پیش‌فرض node را فقط به شبکه‌ی Docker به نام `kind` می‌گذارد، و از آنجا نام `mlflow` شناخته نمی‌شود. بعد از اتصال، pod‌ها می‌توانند `http://mlflow:5000` را پیدا کنند. بخش `2>/dev/null || true`: اگر قبلاً وصل بود، Docker خطا می‌دهد؛ خطا را پنهان می‌کنیم و ادامه می‌دهیم، تا اجرای دوباره مشکلی نسازد.

```makefile
k8s-deploy:
	$(KUBECTL) apply -f k8s/namespace.yaml
	$(KUBECTL) apply -f k8s/
	$(KUBECTL) -n churn rollout status deployment/churn-api --timeout=180s
```

هدف `k8s-deploy` سه دستور دارد:

1. namespace را اول می‌سازد (چون فایل‌ها به ترتیب الفبا اعمال می‌شوند و `configmap.yaml` قبل از `namespace.yaml` می‌آید).
2. همه‌ی پوشه‌ی `k8s/` را اعمال می‌کند. `apply` یعنی «وضعیت دلخواه را از این فایل بگیر». اگر منبع وجود نداشت می‌سازد (`created`)، اگر تفاوت داشت عوض می‌کند (`configured`)، و اگر یکی بود کاری نمی‌کند (`unchanged`). پس بی‌خطر قابل تکرار است.
3. `rollout status` منتظر می‌ماند تا Deployment کامل آماده شود (حداکثر ۱۸۰ ثانیه). اگر نشد، با خطا تمام می‌شود و `make` هم شکست می‌خورد.

```makefile
k8s-status:
	$(KUBECTL) -n churn get deploy,rs,pods,svc
	$(KUBECTL) -n churn rollout history deployment/churn-api
```

هدف `k8s-status`: چهار نوع منبع را با یک `get` نشان می‌دهد (فهرست با ویرگول، بدون فاصله) و بعد تاریخچه‌ی revision‌ها. `-n churn` یعنی «در namespace churn»؛ بدون آن kubectl به namespace `default` نگاه می‌کند و چیزی نمی‌بیند.

```makefile
k8s-forward:
	$(KUBECTL) -n churn port-forward svc/churn-api $(FORWARD_PORT):80
```

هدف `k8s-forward`: تونل از پورت `8002` لپ‌تاپ به پورت ۸۰ سرویس. تا زمانی که اجرا شود ترمینال را پر می‌کند (با Ctrl+C قطع می‌شود). یک نکته: port-forward وقتی به یک Service می‌زنید، یک pod مشخص را انتخاب می‌کند و به همان وصل می‌ماند، پس اگر آن pod عوض شود تونل قطع می‌شود و باید دوباره اجرایش کنید. این ابزار **تست** است، نه راه ورود کاربران.

جلوی خط‌های دستور باید TAB باشد، نه فاصله.

---

## اسکریپت `scripts/kind-up.sh` (از مخزن دوره)

این اسکریپت را کپی نمی‌کنید؛ `make k8s-up` آن را از `~/mlops-lab/scripts` اجرا می‌کند. هدفش ساخت registry و cluster است. چند ویژگی که ارزش دانستن دارد: با `set -euo pipefail` شروع می‌شود (در اولین خطا بایستد)، و هر مرحله اول بررسی می‌کند که انجام نشده باشد، پس اجرای دوباره بی‌خطر است.

**مرحله ۱: registry محلی.** اگر container به نام `kind-registry` در حال اجرا نباشد، آن را با image رجیستری از `versions.env` می‌سازد: پورت `5001` لپ‌تاپ (فقط روی `127.0.0.1`) به ۵۰۰۰ داخل container، با `--restart=always` تا بعد از ری‌استارت Docker دوباره بالا بیاید. تمام image‌هایی که با `make push` می‌فرستید اینجا ذخیره می‌شوند.

**مرحله ۲: cluster.** اگر `kind get clusters` نامی برابر `mlops` نداشته باشد، `kind create cluster` اجرا می‌شود با image node مشخص (نسخه‌ی Kubernetes پین‌شده در `versions.env`) و فایل `k8s/kind-config.yaml`، و `--wait 120s` تا node آماده شود. در این مرحله است که kubeconfig شما تغییر می‌کند و context فعلی `kind-mlops` می‌شود.

**مرحله ۳: اتصال registry به node.** برای هر node، دو کار:

- داخل node فایل `hosts.toml` ساخته می‌شود که به containerd می‌گوید آدرس `localhost:5001` را در واقع از `http://kind-registry:5000` بگیرد. (داخل node، `localhost` خود node است، نه لپ‌تاپ، پس بدون این نگاشت pull نمی‌شد.)
- container رجیستری به شبکه‌ی `kind` وصل می‌شود (اگر نبود) تا node بتواند نام `kind-registry` را پیدا کند.

بعد یک ConfigMap به نام `local-registry-hosting` در namespace `kube-public` ساخته می‌شود. این یک قرارداد استاندارد است که ابزارها از آن می‌فهمند registry محلی کجاست؛ همان خطی که در خروجی `configmap/local-registry-hosting created` دیدید.

**مرحله ۴: image‌های آفلاین.** اگر فایل `images/kind-preload.tar.gz` وجود داشته باشد (در بسته‌ی آفلاین کلاس)، image‌های لازم افزونه‌ها بدون اینترنت داخل node بارگذاری می‌شود.

**مرحله ۵: افزونه‌های اختیاری.** برای جلسه‌ی ۱۱ هیچ آرگومانی نمی‌دهیم و این مرحله اجرا نمی‌شود. گزینه‌ی `--ingress` (جلسه‌ی ۱۲) Traefik و `--monitoring` (جلسه‌ی ۱۳) Prometheus و Grafana را با Helm نصب می‌کنند.

در پایان `kubectl get nodes -o wide` و یک پیام نهایی چاپ می‌شود.

### فایل `k8s/kind-config.yaml` (از مخزن دوره)

یک cluster با یک node که هم control-plane است و هم کار اجرا را انجام می‌دهد (برای لپ‌تاپ‌های ۱۶ گیگابایتی کافی است). `name: mlops` نام cluster را تعیین می‌کند، و نام context (`kind-mlops`) و نام container node (`mlops-control-plane`) از آن می‌آید. برچسب `ingress-ready: "true"` و `extraPortMappings` (پورت‌های ۸۰۸۰ و ۸۴۴۳ لپ‌تاپ) برای جلسه‌ی ۱۲ آماده شده‌اند؛ در این جلسه استفاده نمی‌شوند. گزینه‌ی `listenAddress: "127.0.0.1"` یعنی فقط خود لپ‌تاپ می‌تواند به آنها وصل شود.

---

## دستورهای kubectl که در این جلسه می‌زنید

| دستور | کار |
|---|---|
| `apply -f فایل` | وضعیت دلخواه را از فایل اعمال کن (بساز یا عوض کن) |
| `get TYPE` | فهرست منابع. گزینه‌ها: `-o wide` ستون بیشتر، `-w` تماشای زنده، `-l app=churn-api` فیلتر با برچسب |
| `describe TYPE NAME` | جزئیات یک منبع و در انتها `Events` آن |
| `logs NAME` | لاگ (stdout) یک pod. `deploy/churn-api` یعنی یکی از pod‌های آن Deployment |
| `get events --sort-by=.lastTimestamp` | رویدادهای namespace به ترتیب زمان |
| `delete pod NAME` | pod را حذف کن (ReplicaSet دوباره می‌سازد) |
| `set image deployment/X api=IMAGE` | image یک container را عوض کن (یک rollout می‌سازد) |
| `rollout status` / `history` / `undo` / `restart` | دیدن پیشرفت، تاریخچه، برگشت، و ساخت دوباره‌ی همه‌ی pod‌ها |
| `annotate ... kubernetes.io/change-cause=...` | ثبت دلیل تغییر در تاریخچه |
| `patch configmap NAME -p JSON` | یک بخش از منبع را مستقیم عوض کن |
| `exec deploy/X -- دستور` | یک دستور را داخل container اجرا کن |
| `port-forward svc/X لپ‌تاپ:سرویس` | تونل موقت از لپ‌تاپ |

فرق دو سبک کار: **declarative** (`apply -f` از فایل؛ فایل منبع حقیقت است) و **imperative** (`set image`، `patch`؛ سریع برای آزمایش ولی در Git ثبت نمی‌شود). تیم‌ها تغییرات ماندگار را همیشه با فایل می‌دهند.

---

## پرسش‌هایی برای فکر کردن

1. اگر برچسب `app: churn-api` را فقط در قالب pod به `app: churn` تغییر دهیم (و selector را دست نزنیم) چه می‌شود؟ Deployment و Service هر کدام چه واکنشی دارند؟
2. با `maxUnavailable: 0` و `maxSurge: 1` و دو replica، اگر node فقط جای ۲ pod داشته باشد، rollout گیر می‌کند؟ چه فرقی با `maxUnavailable: 1` و `maxSurge: 0` دارد؟
3. چرا `livenessProbe` را روی `/ready` نگذاشتیم؟ اگر گذاشته بودیم و MLflow برای ده دقیقه خاموش می‌شد، چه اتفاقی می‌افتاد؟
4. چرا `rollout undo` تغییر ConfigMap را برنمی‌گرداند؟ چه راهی می‌شناسید که تغییر ConfigMap هم خودکار یک rollout بسازد؟ (اشاره: به جای ConfigMap بودن، به بخشی از قالب pod فکر کنید که با تغییر محتوا تغییر کند.)
5. تفاوت `requests` و `limits` برای scheduler چیست؟ اگر مجموع `requests` همه‌ی pod‌ها از ظرفیت node بیشتر باشد، pod جدید چه وضعیتی می‌گیرد؟
6. چرا نوشتن `image: churn-api:latest` برای rollback بد است؟

</div>
