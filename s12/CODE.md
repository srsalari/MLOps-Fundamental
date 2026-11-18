<div dir="rtl">

# توضیح کد جلسه‌ی ۱۲

در جلسه‌ی ۱۱ سرویس را با چهار فایل YAML روی Kubernetes بردیم. در این جلسه دو کار می‌کنیم: یک فایل YAML تازه برای **Ingress** (راه ورود از بیرون)، و **بسته‌بندی** همه‌ی فایل‌ها به شکل یک chart برای Helm. کد پایتون برنامه و image جلسه‌ی ۹ تغییر نمی‌کنند.

فایل‌های این جلسه:

- فایل `k8s/ingress.yaml`: قانون مسیریابی `churn.localhost` به Service (گام ۲).
- پوشه‌ی `chart/churn-api/`: خود chart.
  - فایل `Chart.yaml`: نام و نسخه‌ی بسته.
  - فایل `values.yaml`، `values-dev.yaml`، `values-prod.yaml`: مقدارها.
  - فایل‌های داخل `templates/`: `_helpers.tpl`، `configmap.yaml`، `deployment.yaml`، `service.yaml`، `ingress.yaml`، `NOTES.txt`.
  - فایل `.helmignore`: فایل‌هایی که وارد بسته نمی‌شوند.
- فایل `Makefile`: متغیرها و هدف‌های تازه برای Traefik و Helm.
- فایل‌های مخزن دوره که فقط استفاده می‌کنید: `charts/traefik-41.5.0.tgz` و `k8s/traefik-values.yaml`.
- فایل `preflight.sh`: بررسی آمادگی پیش از کلاس (کد آموزشی نیست و اینجا توضیح داده نمی‌شود).

کامنت‌های داخل فایل‌ها عمداً انگلیسی هستند. شرح فارسی همه‌چیز در همین فایل است.

---

## مفهوم پایه: Ingress و controller

Ingress یک **قانون** است، نه برنامه. مثل یک برگه‌ی راهنما که می‌گوید «هر کس برای فلان نام آمد، او را به فلان اتاق ببر». کسی که برگه را می‌خواند و واقعاً آدم‌ها را هدایت می‌کند **Ingress controller** است (اینجا Traefik). اگر controller نباشد، برگه هیچ اثری ندارد؛ اگر برگه نباشد، controller نمی‌داند کجا ببرد (همان `404` گام ۱).

مسیر یک درخواست در این جلسه:

```text
curl http://churn.localhost:8080/ready
   |  (churn.localhost = 127.0.0.1، پورت 8080 لپ‌تاپ)
   v
پورت 8080 لپ‌تاپ  ->  پورت 30080 داخل node (kind extraPortMappings)
   v
Service به نام traefik (NodePort 30080)  ->  pod به نام traefik
   |  Traefik سرآیند Host را می‌خواند و Ingress‌ها را نگاه می‌کند
   v
Service به نام churn-api (پورت 80)  ->  یکی از pod‌های churn-api (پورت 8000)
```

---

## فایل `k8s/ingress.yaml`

**کار فایل:** به Traefik می‌گوید درخواست‌های host برابر `churn.localhost` را به Service با نام `churn-api` بده.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: churn-api
  namespace: churn
```

- `apiVersion: networking.k8s.io/v1` و `kind: Ingress`: نوع منبع.
- `namespace: churn`: Ingress باید در همان namespace Service باشد؛ قانون فقط به Service هم‌namespace اشاره می‌کند.

```yaml
spec:
  ingressClassName: traefik
```

`ingressClassName` می‌گوید کدام controller این قانون را بردارد. ما فقط Traefik را داریم و در `traefik-values.yaml` پیش‌فرض است، ولی صریح نوشتن بهتر است: اگر روزی دو controller داشتید، اشتباه نمی‌شود.

```yaml
  rules:
    - host: churn.localhost
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: churn-api
                port:
                  number: 80
```

- `host: churn.localhost`: شرط اول. فقط درخواست‌هایی که سرآیند `Host` آن‌ها این نام است. همین است که host-based routing را می‌سازد. برای دو سرویس، دو `rules` با دو `host` می‌نویسید.
- `path: /` و `pathType: Prefix`: شرط دوم. هر مسیری که با `/` شروع شود (یعنی همه‌چیز). با `path: /api` فقط آدرس‌های زیر `/api` می‌آمدند.
- `backend.service`: مقصد. نام Service (`churn-api`، از جلسه‌ی ۱۱) و پورت **Service** (۸۰، نه ۸۰۰۰ پورت container).

---

## مفهوم پایه: Helm و template

Helm یک **موتور قالب** است. فایل‌های YAML را با جاهای خالی می‌نویسید و Helm با مقدار‌ها پرشان می‌کند:

```text
templates/*.yaml  +  values (values.yaml + -f فایل + --set)   ->   YAML نهایی   ->   cluster
```

جاهای خالی داخل `{{ ... }}` هستند. چند تکه‌ی مهم این زبان (زبان قالب Go):

| تکه | معنی |
|---|---|
| `{{ .Values.replicaCount }}` | مقدار `replicaCount` از فایل‌های values |
| `{{ .Release.Name }}` | نام release (آنچه بعد از `helm install` می‌نویسید) |
| `{{ .Chart.Name }}`، `{{ .Chart.AppVersion }}` | مقدار‌هایی از `Chart.yaml` |
| `{{ ... \| quote }}` | مقدار را داخل کوتیشن بگذار (برای رشته‌ها در YAML ضروری است) |
| `{{ .Values.image.tag \| default .Chart.AppVersion }}` | اگر مقدار خالی بود، پیش‌فرض را بگذار |
| `{{ include "نام" . }}` | یک تکه‌ی نام‌دار (از `_helpers.tpl`) را همین‌جا بگذار |
| `\| nindent 4` | خروجی را با خط جدید و ۴ فاصله بنویس (برای تورفتگی درست YAML) |
| `{{ toYaml .Values.resources }}` | یک ساختار را به YAML تبدیل کن |
| `{{- if ... }} ... {{- end }}` | فقط اگر شرط برقرار بود بنویس |
| `{{- ` و ` -}}` | خط خالی اطراف را نخور (علامت `-` فاصله‌ها را پاک می‌کند) |

تمرین فکری: اگر نمی‌دانید یک الگو چه می‌سازد، `make helm-template` بزنید و خروجی را ببینید. این امن‌ترین راه یادگرفتن است، چون به cluster دست نمی‌زند.

---

## فایل `chart/churn-api/Chart.yaml`

```yaml
apiVersion: v2
name: churn-api
description: Churn prediction API (FastAPI) - Deployment, Service, ConfigMap and Ingress
type: application
version: 0.1.0
appVersion: "0.7.0"
```

- `apiVersion: v2`: نسخه‌ی قالب chart (برای Helm نسخه‌ی ۳ و ۴).
- `name`: نام chart؛ باید با نام پوشه یکی باشد.
- `type: application`: یعنی chart چیزی نصب می‌کند (نوع دیگر `library` است).
- `version`: نسخه‌ی **بسته**. هر وقت یک template عوض کردید بالا ببرید (`0.1.1`، `0.2.0`).
- `appVersion`: نسخه‌ی **برنامه‌ی داخل** chart. ما از آن به‌عنوان tag پیش‌فرض image استفاده می‌کنیم. دقت کنید این فقط یک عدد اطلاعاتی است: وقتی با `--set image.tag=0.7.1` tag را عوض کردید، ستون `APP VERSION` در `helm list` همان `0.7.0` می‌ماند.

---

## فایل `chart/churn-api/values.yaml`

**کار فایل:** همه‌ی چیزهایی که قابل تنظیم‌اند، با مقدار پیش‌فرض. هر محیط فقط تفاوت‌هایش را می‌نویسد.

```yaml
replicaCount: 2

image:
  repository: localhost:5001/churn-api
  tag: ""
  pullPolicy: IfNotPresent
```

- `replicaCount`: تعداد pod. همان `replicas` جلسه‌ی ۱۱.
- `image.repository`: نشانی کامل image بدون tag. جدا نوشتن repository و tag اجازه می‌دهد فقط tag را عوض کنید.
- `image.tag: ""`: خالی یعنی «از `appVersion` استفاده کن» (`0.7.0`).
- `pullPolicy: IfNotPresent`: اگر image روی node هست دوباره دانلود نکن.

```yaml
config:
  mlflowTrackingUri: http://mlflow:5000
  modelUri: models:/churn@champion
  predictThreshold: "0.5"
```

سه مقدار ConfigMap جلسه‌ی ۱۱ با نام camelCase (رسم Helm). `predictThreshold` عمداً رشته (داخل کوتیشن) است، چون در ConfigMap همه‌چیز رشته است.

```yaml
service:
  port: 80

ingress:
  enabled: true
  className: traefik
  host: churn.localhost
  path: /
```

- `service.port`: پورت Service (و پورتی که Ingress به آن اشاره می‌کند). یک بار اینجا می‌نویسیم و در دو template استفاده می‌شود؛ این یعنی دو جا هیچ‌وقت ناهماهنگ نمی‌شوند.
- `ingress.enabled`: کلید روشن/خاموش کردن Ingress؛ در `templates/ingress.yaml` با `if` خوانده می‌شود.
- `ingress.host`: همان `churn.localhost`.

```yaml
resources:
  requests:
    cpu: 100m
    memory: 256Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

همان عددهای جلسه‌ی ۱۱. تمام ساختار با `toYaml` در Deployment گذاشته می‌شود، پس هر کلید داخلش (مثلاً `ephemeral-storage`) بدون تغییر template کار می‌کند.

---

## فایل‌های `values-dev.yaml` و `values-prod.yaml`

```yaml
# values-dev.yaml
replicaCount: 1
config:
  modelUri: models:/churn@champion
ingress:
  host: churn.localhost
resources:
  requests: {cpu: 50m, memory: 192Mi}
  limits: {cpu: 500m, memory: 512Mi}
```

```yaml
# values-prod.yaml
replicaCount: 3
config:
  modelUri: models:/churn/2
ingress:
  host: prod.churn.localhost
```

فقط **تفاوت‌ها** را می‌نویسند؛ چیزهایی که ننوشته‌اند از `values.yaml` می‌آید. Helm فایل‌ها را روی هم می‌ریزد (merge): اول `values.yaml`، بعد `-f`، بعد `--set` (هر چه دیرتر باشد قوی‌تر است). دو تصمیم مهم:

- dev مدل را با alias دنبال می‌کند (`@champion`)، تا تیم همیشه تازه‌ترین مدل را ببیند.
- prod نسخه‌ی عددی (`models:/churn/2`) را می‌گیرد، تا تغییر alias در MLflow، production را ناگهان عوض نکند؛ برای عوض کردن مدل prod باید یک `helm upgrade` آگاهانه (و بازبینی‌شده) بزنید.

نکته: merge روی **map‌ها** کلید به کلید است (مثلاً `config.modelUri` فقط همان یک کلید را عوض می‌کند و `mlflowTrackingUri` از پیش‌فرض می‌ماند)، ولی **فهرست‌ها** کامل جایگزین می‌شوند.

---

## فایل `chart/churn-api/templates/_helpers.tpl`

فایلی که با `_` شروع شود هیچ شیء Kubernetes نمی‌سازد؛ فقط تکه‌های نام‌دار تعریف می‌کند که فایل‌های دیگر با `include` صدایشان می‌زنند.

```text
{{- define "churn-api.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

`churn-api.name`: نام chart (حداکثر ۶۳ نویسه، محدودیت Kubernetes برای نام‌ها).

```text
{{- define "churn-api.fullname" -}}
{{- if contains .Chart.Name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
```

`churn-api.fullname`: نام هر شیء. اگر نام release شامل نام chart باشد (مثل `churn-api`) همان را می‌گذارد؛ وگرنه `RELEASE-CHART`. نتیجه: با release به نام `churn-api` همه‌ی نام‌ها همان‌هایی هستند که در جلسه‌ی ۱۱ داشتیم (`churn-api`، `churn-api-config`). اگر release را `prod` بنامید، نام‌ها `prod-churn-api` می‌شوند. از همین رو دو release با نام یکسان (`churn-api`) را در دو namespace جدا ساختیم.

```text
{{- define "churn-api.selectorLabels" -}}
app.kubernetes.io/name: {{ include "churn-api.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
```

`selectorLabels`: دو label که Deployment و Service با آن‌ها pod‌ها را پیدا می‌کنند (به‌جای `app: churn-api` جلسه‌ی ۱۱؛ این نام‌ها استاندارد Kubernetes هستند). `instance` باعث می‌شود دو release هم‌نام chart در یک namespace قاطی نشوند. **این label‌ها را بعد از اولین نصب عوض نکنید**: `selector` یک Deployment غیرقابل تغییر است.

```text
{{- define "churn-api.labels" -}}
{{ include "churn-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}
```

`labels`: label‌های روی همه‌ی شیء‌ها. `managed-by: Helm` همان چیزی است که جلوی `helm install` روی شیء‌های kubectl را می‌گرفت (گام ۳): Helm فقط شیء‌هایی را مدیریت می‌کند که این label را دارند.

---

## فایل `chart/churn-api/templates/configmap.yaml`

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "churn-api.fullname" . }}-config
  labels:
    {{- include "churn-api.labels" . | nindent 4 }}
data:
  MLFLOW_TRACKING_URI: {{ .Values.config.mlflowTrackingUri | quote }}
  MODEL_URI: {{ .Values.config.modelUri | quote }}
  PREDICT_THRESHOLD: {{ .Values.config.predictThreshold | quote }}
```

- نام: `churn-api-config` (همان جلسه‌ی ۱۱).
- `namespace` نوشته نشده: Helm شیء را در namespace دستور (`-n`) می‌سازد. به همین دلیل یک chart را می‌شود در `churn` و `churn-prod` نصب کرد.
- `| quote`: مقدار را داخل کوتیشن می‌گذارد، تا `0.5` عدد خوانده نشود.

---

## فایل `chart/churn-api/templates/deployment.yaml`

ساختار همان Deployment جلسه‌ی ۱۱ است؛ فقط این بخش‌ها `{{ }}` شده‌اند:

```yaml
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "churn-api.selectorLabels" . | nindent 6 }}
```

تعداد pod از values، و selector از label‌های مشترک.

```yaml
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

**مهم‌ترین خط chart.** `include (print $.Template.BasePath "/configmap.yaml") .` متن نهایی فایل ConfigMap را می‌سازد و `sha256sum` از آن یک اثر انگشت می‌گیرد. اگر ConfigMap تغییر کند (مثلاً مدل را عوض کنید)، اثر انگشت عوض می‌شود، پس **قالب pod عوض می‌شود** و Kubernetes خودش یک rolling update می‌کند. در جلسه‌ی ۱۱ این کار را باید با دست (`rollout restart`) می‌کردید. `$` یعنی «ریشه‌ی همه‌چیز» (در درون بلوک‌های تو در تو، `.` ممکن است عوض شده باشد).

```yaml
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
```

نشانی image از دو مقدار ساخته می‌شود. وقتی `tag` خالی است، `default` از `appVersion` (`0.7.0`) استفاده می‌کند.

```yaml
          envFrom:
            - configMapRef:
                name: {{ include "churn-api.fullname" . }}-config
```

نام ConfigMap با همان تابع نام ساخته می‌شود، پس هیچ‌وقت با فایل `configmap.yaml` ناهماهنگ نمی‌شود.

```yaml
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
```

کل بخش `resources` از values می‌آید. عدد `12` تورفتگی است: باید برابر تورفتگی خط `resources:` به‌علاوه‌ی ۲ باشد. این جای معمول خطای `YAML parse error` است.

بقیه‌ی فایل (probe‌ها، `securityContext`، `strategy`) **همان جلسه‌ی ۱۱** است و ثابت مانده؛ این‌ها هنوز مقدار قابل‌تنظیم نیستند (تکلیف بخش ۲ از شما می‌خواهد یکی از آن‌ها را قابل‌تنظیم کنید). توضیح هر کدام در [CODE.md جلسه‌ی ۱۱](../s11/CODE.md) است.

---

## فایل `chart/churn-api/templates/service.yaml`

```yaml
spec:
  selector:
    {{- include "churn-api.selectorLabels" . | nindent 4 }}
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
```

همان Service جلسه‌ی ۱۱. `selector` از label‌های مشترک می‌آید و `port` از values. `targetPort: http` به **نام** پورت container اشاره می‌کند (در Deployment، `name: http`).

---

## فایل `chart/churn-api/templates/ingress.yaml`

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}
```

کل فایل داخل یک `if` است: با `ingress.enabled: false` هیچ شیئی ساخته نمی‌شود. بقیه همان `k8s/ingress.yaml` است، با این تفاوت که `host`، `path`، `className` و `port` از values و نام Service از `fullname` می‌آیند. با این کار Ingress هم جزو release است و با `helm rollback` یا `helm uninstall` همراه بقیه برمی‌گردد یا پاک می‌شود. به همین دلیل `k8s/ingress.yaml` را پیش از نصب chart پاک کردیم.

---

## فایل `chart/churn-api/templates/NOTES.txt`

متنی که **بعد از `helm install` و `helm upgrade`** چاپ می‌شود. می‌توانید `{{ }}` در آن بنویسید (مثلاً `.Release.Revision`، `.Values.ingress.host`). برای بسته‌ای که دیگران نصب می‌کنند، جای خوبی است برای «حالا این دستور را بزنید». این فایل شیء Kubernetes نمی‌سازد.

---

## فایل `chart/churn-api/.helmignore`

فهرست الگوهای فایل که `helm package` داخل بسته نمی‌گذارد (مثل `.git/`، فایل‌های `.swp` و `.bak`). همان `.gitignore` برای chart.

---

## فایل `Makefile`

هدف‌های قبلی (جلسه‌ی ۱ تا ۱۱) همه مانده‌اند. تازه‌ها:

```make
HELM = helm --kube-context $(KCTX)
TRAEFIK_CHART ?= $(LAB_DIR)/charts/traefik-41.5.0.tgz
TRAEFIK_VALUES ?= $(LAB_DIR)/k8s/traefik-values.yaml
CHART ?= chart/churn-api
RELEASE ?= churn-api
STAGE ?= dev
NS ?= churn
HELM_ARGS ?=
```

- `HELM`: مثل `KUBECTL` جلسه‌ی ۱۱، همیشه `--kube-context kind-mlops` را می‌دهد، تا هیچ‌وقت به cluster دیگری نرسد.
- `STAGE`: کدام فایل مقدار (`dev` یا `prod`). `NS`: namespace release. `HELM_ARGS`: گزینه‌های اضافه، مثل `HELM_ARGS="--set replicaCount=3"`.
- `?=` یعنی «فقط اگر از بیرون داده نشده»: `make helm-deploy STAGE=prod NS=churn-prod`.

| هدف | کار |
|---|---|
| `ingress-up` | `helm upgrade --install traefik` از فایل chart آفلاین، با `traefik-values.yaml` (`--wait`، حداکثر ۱۲۰ ثانیه) |
| `ingress-apply` | `kubectl apply -f k8s/ingress.yaml` (گام ۲) |
| `helm-lint` | `helm lint` با فایل مقدار `STAGE` |
| `helm-template` | `helm template`: YAML نهایی را چاپ می‌کند، به cluster دست نمی‌زند |
| `helm-deploy` | `helm upgrade --install` با `--create-namespace`، فایل مقدار `STAGE`، و `--wait` |
| `helm-status` | `helm list`، `helm history` و `kubectl get` برای namespace |
| `helm-rollback` | `helm rollback RELEASE REV`: `make helm-rollback REV=2` |
| `helm-uninstall` | `helm uninstall` (namespace می‌ماند) |

`helm upgrade --install` هم برای نصب و هم برای به‌روزرسانی کار می‌کند؛ برای همین یک هدف `helm-deploy` کافی است. `--wait` تا آماده شدن pod‌ها (یا پایان `--timeout`) صبر می‌کند، پس اگر چیزی خراب باشد دستور با خطا تمام می‌شود و شما همان لحظه می‌فهمید.

---

## فایل `k8s/traefik-values.yaml` (از مخزن دوره)

مقدارهای chart رسمی Traefik برای cluster ما. مهم‌ترین‌ها:

- `service.spec.type: NodePort` با `ports.web.nodePort: 30080` و `ports.websecure.nodePort: 30443`: چون kind load balancer ندارد، Traefik روی دو پورت ثابت node باز می‌شود، و `kind-config.yaml` همان دو را به ۸۰۸۰ و ۸۴۴۳ لپ‌تاپ وصل کرده است. (در نسخه‌ی ۴۱ chart نوع Service زیر `service.spec` است؛ نوشتن `service.type` نادیده گرفته می‌شود و Service از نوع `LoadBalancer` با `EXTERNAL-IP` بی‌پایانِ `<pending>` می‌ماند.)
- `ingressClass.isDefaultClass: true`: Ingress‌های بدون `ingressClassName` هم به Traefik می‌رسند.
- `providers.kubernetesGateway.enabled: false`: Gateway API خاموش است (فقط پیش‌نمایش).
- `nodeSelector` با `ingress-ready: "true"`: pod روی node‌ای می‌رود که در `kind-config.yaml` این label را گرفته و پورت‌ها را دارد.
- `resources`: Traefik حدود ۵۰ مگابایت حافظه می‌گیرد؛ سقف ۲۵۶ مگابایت گذاشته‌ایم.

---

## دستورهای Helm که در این جلسه می‌زنید

| دستور | کار |
|---|---|
| `helm lint CHART` | chart را بررسی کن (خطای template و ساختار) |
| `helm template RELEASE CHART -f ...` | YAML نهایی را چاپ کن؛ به cluster دست نمی‌زند |
| `helm install RELEASE CHART -n NS --create-namespace -f ...` | نصب تازه |
| `helm upgrade --install RELEASE CHART ...` | اگر هست به‌روز کن، اگر نیست نصب کن |
| `--set کلید=مقدار` | یک مقدار را روی فایل‌ها override کن (برای آزمایش) |
| `--wait --timeout 120s` | تا آماده شدن منبع‌ها صبر کن؛ وگرنه خطا |
| `helm list -A` | همه‌ی release‌ها در همه‌ی namespace‌ها |
| `helm status RELEASE -n NS` | وضعیت یک release |
| `helm history RELEASE -n NS` | تاریخچه‌ی revision‌ها (با وضعیت `failed` و `superseded` و `deployed`) |
| `helm get values RELEASE -n NS` | مقدارهای ثبت‌شده (`-a`: همه‌ی مقدارها، `--revision N`: یک revision) |
| `helm get manifest RELEASE -n NS` | YAML که آخرین بار اعمال شد |
| `helm rollback RELEASE REV -n NS` | برگشت به revision (یک revision تازه می‌سازد) |
| `helm uninstall RELEASE -n NS` | release را پاک کن (namespace می‌ماند) |
| `helm package CHART` | chart را به یک فایل `.tgz` تبدیل کن (برای اشتراک‌گذاری) |

سه تفاوت مهم با kubectl: Helm **نام و تاریخچه** نگه می‌دارد (`history`)؛ برگشتش **همه‌ی شیء‌های release** را برمی‌گرداند (ConfigMap هم)؛ و فقط شیء‌هایی را مدیریت می‌کند که خودش ساخته (برچسب `managed-by: Helm`). به همین دلیل با یک release Helm، با `kubectl set image` و `kubectl edit` کار نکنید.

---

## پرسش‌هایی برای فکر کردن

1. در Ingress، `pathType: Prefix` با `path: /api` چه آدرس‌هایی را می‌گیرد؟ `/apiary` چه؟ چرا `Exact` گاهی بهتر است؟
2. اگر دو Ingress با یک host و یک path در دو namespace بسازید، Traefik چه می‌کند؟ چرا قاعده‌ی «Ingress هم‌namespace Service» ایمنی می‌دهد؟
3. چرا مقدار `ingress.host` در `values-dev.yaml` و `values-prod.yaml` فرق می‌کند، ولی `service.port` را در هیچ‌کدام ننوشتیم؟ چه چیزی باید باشد که یک مقدار «در فایل محیط» برود و نه «در پیش‌فرض»؟
4. اگر خط `checksum/config` را از `deployment.yaml` پاک کنید و مدل را با `helm upgrade --set config.modelUri=models:/churn/1` عوض کنید، چه اتفاقی می‌افتد؟ `helm history` چه می‌گوید و کاربران چه می‌بینند؟ (اشاره: به جلسه‌ی ۱۱، بخش ConfigMap فکر کنید.)
5. `helm rollback` یک revision تازه می‌سازد. چرا به‌جای «برگرداندن شمارنده» این کار را می‌کند؟ این چه فایده‌ای برای ردیابی دارد؟
6. اگر یک بار روی release Helm با `kubectl rollout undo` برگردید، بعد `helm rollback` بزنید، چرا ممکن است pod‌ها عوض نشوند؟ (اشاره: Helm قالب جدید را با قالب *فعلی* مقایسه می‌کند.)
7. تفاوت `helm template` و `helm install --dry-run=server` چیست؟ هر کدام را چه وقت به کار می‌برید؟
8. چرا در prod مدل را روی یک نسخه‌ی عددی ثابت کردیم؟ چه هزینه‌ای دارد (چه کسی و چه وقت باید آن عدد را عوض کند)؟

</div>
