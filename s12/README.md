<div dir="rtl">

# آزمایشگاه جلسه‌ی ۱۲ — Ingress با Traefik و بسته‌بندی با Helm

در جلسه‌ی ۱۱ سرویس churn را روی Kubernetes بردید، ولی برای دیدنش از `port-forward` استفاده کردید: یک تونل موقت، فقط برای خودتان، که با عوض شدن pod هم می‌شکست. در این جلسه دو مشکل را حل می‌کنید.

اول، **دسترسی واقعی**: با یک **Ingress** و یک **Ingress controller** به نام **Traefik**، سرویس با یک نام (`churn.localhost`) و یک آدرس ثابت از لپ‌تاپ در دسترس می‌شود. Traefik به آدرس (host) درخواست نگاه می‌کند و آن را به Service درست می‌فرستد (**host-based routing**).

دوم، **تکرار و برگشت**: در جلسه‌ی ۱۱ چهار فایل YAML را با دست `apply` کردید و برگشت از یک تغییر خراب (مثل ConfigMap) سخت بود. با **Helm** همان چهار فایل را یک بار به شکل یک **chart** (یک بسته‌ی قابل تنظیم) درمی‌آورید. بعد برای هر محیط فقط یک فایل مقدار (`values-dev.yaml` و `values-prod.yaml`) می‌نویسید، با یک دستور به‌روزرسانی می‌کنید، و با یک دستور (`helm rollback`) به نسخه‌ی قبل برمی‌گردید، **این بار همراه با ConfigMap**.

زمان تقریبی: ۷۵ دقیقه.

## پیش از شروع

1. پروژه‌ی جلسه‌ی ۱۱ سالم باشد: `main` شامل tag `v0.9.0` است.
2. <bdi dir="rtl">cluster به نام `mlops` از جلسه‌ی ۱۱ روشن است و دو pod به نام `churn-api` در namespace با نام `churn` دارد. اگر cluster را پاک کرده‌اید، در گام ۱ دوباره می‌سازید.</bdi>
3. سرویس‌های جلسه‌های قبل پاک نشده‌اند (`docker compose down -v` نزده باشید) و registry محلی (`localhost:5001`) image `churn-api:0.7.0` را دارد.
4. **حافظه‌ی Docker حداقل ۸ گیگابایت.** در این جلسه چند pod دیگر اضافه می‌شود (Traefik و نسخه‌ی prod)؛ node ما در اوج حدود ۲٫۲ گیگابایت می‌گیرد.
5. **پورت‌های ۸۰۸۰ و ۸۴۴۳ لپ‌تاپ آزاد باشند.** این دو پورت در جلسه‌ی ۱۱ به node وصل شده‌اند (فایل `k8s/kind-config.yaml` مخزن دوره). اگر برنامه‌ی دیگری روی ۸۰۸۰ باشد، preflight هشدار می‌دهد.
6. <bdi dir="rtl">kind، kubectl و **helm** نصب باشند (در بسته‌ی آفلاین دوره هستند). بررسی آمادگی را اجرا کنید:</bdi>

```bash
~/mlops-lab/s12/preflight.sh
```

اگر خطایی داد، پیام آن راه‌حل را می‌گوید. بعد مخزن دوره را به‌روز کنید و مسیر این پوشه را نگه دارید:

```bash
git -C ~/mlops-lab pull
```

```bash
S=~/mlops-lab/s12
```

در این جلسه **یک ترمینال** کافی است (دیگر `port-forward` نداریم). اگر ترمینال را بستید، خط `S=...` را دوباره بزنید. دانشجوهای Windows همه‌ی دستورها را داخل WSL Ubuntu اجرا کنند، نه PowerShell. دانشجوهای macOS: Docker Desktop (یا Colima) باید در حال اجرا باشد.

### قاعده‌ی context (مثل جلسه‌ی ۱۱)

<bdi dir="rtl">kubectl و helm هر دو دستور را به «context فعلی» می‌فرستند. اگر `~/.kube/config` شما cluster دیگری هم دارد، یک دستور بدون context ممکن است به آن برسد. پس همیشه context را صریح بدهید: Makefile این کار را می‌کند، و در دستورهای دستی از دو alias استفاده می‌کنیم (در گام ۱ می‌سازید): `k` برای kubectl و `h` برای helm.</bdi>

## مفهوم‌ها در یک نگاه

| واژه | معنی |
| --- | --- |
| Ingress | یک شیء Kubernetes که قانون مسیریابی را می‌نویسد: «درخواست برای این host و این path برود به این Service». خودش ترافیک را جابه‌جا نمی‌کند، فقط قانون است |
| Ingress controller | برنامه‌ای که قانون‌های Ingress را می‌خواند و واقعاً ترافیک را مسیریابی می‌کند. ما **Traefik** را داریم (ingress-nginx بازنشسته شده است) |
| IngressClass | اسمی که می‌گوید یک Ingress را کدام controller بردارد. ما `traefik` داریم و پیش‌فرض است |
| host-based routing | انتخاب مقصد از روی نام host در درخواست (`churn.localhost` یا `prod.churn.localhost`). چند سرویس با یک ورودی (یک پورت) |
| NodePort | روشی که Service را روی یک پورت ثابت node (اینجا ۳۰۰۸۰) باز می‌کند. kind آن را به پورت ۸۰۸۰ لپ‌تاپ وصل کرده است |
| `*.localhost` | هر نامی که به `.localhost` ختم شود خودکار به لپ‌تاپ خودتان (`127.0.0.1`) می‌رسد؛ نیازی به ویرایش `/etc/hosts` نیست |
| Gateway API | نسل تازه‌ی Ingress (فقط پیش‌نمایش): GatewayClass، Gateway و HTTPRoute. جدا کردن نقش «تیم پلتفرم» از «تیم برنامه» |
| Helm | «مدیر بسته» Kubernetes: YAML‌های الگو‌دار (template) را با مقدار‌ها پر می‌کند و نصب را ثبت می‌کند |
| chart | بسته‌ی Helm: پوشه‌ای با `Chart.yaml`، `values.yaml` و `templates/` |
| values | مقدار‌های قابل تنظیم chart. `values.yaml` پیش‌فرض است؛ `-f` و `--set` آن را برای هر محیط عوض می‌کنند |
| template | فایل YAML با جاهای خالی مثل `{{ .Values.replicaCount }}` که Helm پر می‌کند |
| release | یک نصب مشخص از یک chart در یک namespace (مثلاً release با نام `churn-api`). Helm برای هر release تاریخچه نگه می‌دارد |
| revision | شماره‌ی هر تغییر در تاریخچه‌ی release. `helm rollback` هم یک revision تازه می‌سازد |
| `helm lint` و `helm template` | بررسی chart و دیدن YAML نهایی، بدون دست زدن به cluster |
| `helm upgrade` و `helm rollback` | به‌روزرسانی release با مقدار تازه، و برگشت به یک revision قبلی |

### <bdi dir="rtl">Gateway API در یک نگاه (فقط مفهوم)</bdi>

<bdi dir="rtl">Ingress یک قانون ساده دارد (host و path) و هر controller ویژگی‌های اضافه را با annotation‌های مخصوص خودش می‌گیرد. **Gateway API** این را به سه شیء تقسیم می‌کند: `GatewayClass` (کدام controller)، `Gateway` (پورت‌ها و ورودی‌ها؛ مال تیم پلتفرم) و `HTTPRoute` (قانون host و path؛ مال تیم برنامه). مسیر ما در این استاندارد این شکل می‌شد:</bdi>

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: churn-api
  namespace: churn
spec:
  parentRefs:
    - name: traefik-gateway
      namespace: traefik
  hostnames: ["gw.churn.localhost"]
  rules:
    - matches:
        - path: {type: PathPrefix, value: /}
      backendRefs:
        - name: churn-api
          port: 80
```

ما این را در آزمایشگاه اجرا نمی‌کنیم (CRD‌های Gateway API جداگانه نصب می‌شوند و دانلود اینترنتی لازم دارند). Traefik در `traefik-values.yaml` ما این قابلیت را عمداً خاموش دارد. مدرس در کلاس فقط نشان می‌دهد.

## نتیجه‌ی نهایی

- <bdi dir="rtl">Traefik در namespace با نام `traefik` (به‌عنوان یک Helm release) و دسترسی از لپ‌تاپ روی `http://churn.localhost:8080`</bdi>
- یک Ingress با host-based routing: `churn.localhost` به API می‌رسد و هر host ناشناس `404` می‌گیرد
- <bdi dir="rtl">chart با نام `chart/churn-api/` در پروژه (Deployment، Service، ConfigMap، Ingress، `values-dev.yaml`، `values-prod.yaml`)</bdi>
- <bdi dir="rtl">release با نام `churn-api` در namespace `churn` (dev) و release دیگری از همان chart در namespace `churn-prod` (prod)</bdi>
- دیدن و فهمیدن: `helm lint`، `helm template`، `helm upgrade`، یک upgrade خراب، `helm history`، `helm rollback`، و فرق آن با `kubectl rollout undo`
- پوشه‌ی `chart/`، فایل `k8s/ingress.yaml` و Makefile تازه در پروژه، با tag نسخه‌ی `v0.10.0`

## فایل‌های این پوشه

| فایل | مقصد در پروژه | کار |
| --- | --- | --- |
| `k8s/ingress.yaml` | پوشه‌ی `k8s/` در پروژه | Ingress ساده برای `churn.localhost` (گام ۲) |
| `chart/churn-api/` | پوشه‌ی `chart/` در پروژه | chart کامل: `Chart.yaml`، `values*.yaml`، و `templates/` |
| `Makefile` | ریشه‌ی پروژه (جای Makefile جلسه‌ی ۱۱) | هدف‌های تازه‌ی `ingress-up`، `ingress-apply`، `helm-lint`، `helm-template`، `helm-deploy`، `helm-status`، `helm-rollback`، `helm-uninstall` |
| `preflight.sh` | اجرا از همین پوشه | بررسی آمادگی پیش از کلاس |

فایل‌هایی از مخزن دوره که فقط استفاده می‌کنید و کپی نمی‌کنید: chart آماده‌ی Traefik (`~/mlops-lab/charts/traefik-41.5.0.tgz`) و مقدارهای آن (`~/mlops-lab/k8s/traefik-values.yaml`). توضیح خط‌به‌خط همه‌ی فایل‌ها به فارسی: [CODE.md](CODE.md) (در VS Code با Ctrl+Shift+V یا در GitHub باز کنید).

---

## گام ۱ — آماده‌سازی و نصب Traefik (۱۰ دقیقه)

```bash
cd ~/work/churn-mlops && git switch main && git pull
```

```bash
git describe --tags
```

انتظار: `v0.9.0` (اگر تکلیف جلسه‌ی ۱۱ را merge کرده‌اید چیزی مثل `v0.9.0-2-g1a2b3c4` می‌بینید؛ مشکلی نیست)

```bash
git switch -c feature/ingress-helm
```

سرویس‌های جلسه‌های قبل (MLflow و شبکه‌ی `mlops-lab`) را روشن کنید:

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

<bdi dir="rtl">Makefile جلسه‌ی ۱۱ را با Makefile این جلسه عوض کنید (هدف‌های قبلی همه در آن هستند):</bdi>

```bash
cp $S/Makefile .
```

دو alias را بسازید (فقط در همین ترمینال زنده‌اند؛ برای ترمینال تازه دوباره بزنید):

```bash
alias k='kubectl --context kind-mlops'
```

```bash
alias h='helm --kube-context kind-mlops'
```

<bdi dir="rtl">cluster را بررسی کنید:</bdi>

```bash
k get nodes
```

انتظار: یک node به نام `mlops-control-plane` با وضعیت `Ready`. اگر خطای اتصال گرفتید یا cluster پاک شده است، آن را با `make k8s-up` بسازید (حدود ۱ دقیقه)، سپس `make push` و `make k8s-deploy` را بزنید تا به وضعیت پایان جلسه‌ی ۱۱ برسید.

حالا مطمئن شوید node دو پورت Traefik را به لپ‌تاپ وصل کرده است:

```bash
docker port mlops-control-plane
```

انتظار: خط‌هایی شبیه این (پورت اول، `6443`، هر عددی می‌تواند باشد):

```
6443/tcp -> 127.0.0.1:65358
30080/tcp -> 127.0.0.1:8080
30443/tcp -> 127.0.0.1:8443
```

دو خط `30080` و `30443` مهم‌اند: «پورت ۳۰۰۸۰ داخل node همان ۸۰۸۰ لپ‌تاپ است». اگر نبودند، جدول عیب‌یابی را ببینید.

<bdi dir="rtl">pod‌های جلسه‌ی ۱۱ باید هنوز زنده باشند:</bdi>

```bash
k -n churn get pods
```

انتظار: دو pod به نام `churn-api-...` با `1/1 Running`. (اگر pod‌ها نیستند: `make k8s-deploy`.)

ابزار helm را ببینید:

```bash
helm version --short
```

انتظار: چیزی مثل `v4.2.4+g...` (نسخه‌ی دقیق روی سیستم شما ممکن است کمی فرق کند؛ مشکلی نیست).

### نصب Traefik

<bdi dir="rtl">Traefik را با Helm نصب می‌کنیم؛ chart آماده‌ی آن در مخزن دوره است (آفلاین کار می‌کند) و مقدارهای ما در `traefik-values.yaml` است: دو پورت ثابت ۳۰۰۸۰ و ۳۰۴۴۳، یک کپی، و Traefik به‌عنوان IngressClass پیش‌فرض. یک بار بخوانیدش:</bdi>

```bash
cat ~/mlops-lab/k8s/traefik-values.yaml
```

```bash
make ingress-up
```

انتظار: حدود **۲۰ تا ۳۰ ثانیه** (بار اول image حدود ۵۰ مگابایتی Traefik دانلود می‌شود؛ اگر با بسته‌ی آفلاین cluster ساخته‌اید، از قبل آماده است). خروجی:

```
Release "traefik" does not exist. Installing it now.
NAME: traefik
LAST DEPLOYED: Thu Oct 29 08:28:22 2026
NAMESPACE: traefik
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
traefik with docker.io/traefik:v3.7.13 has been deployed successfully on traefik namespace!
```

(تاریخ و ساعت شما فرق دارد.) همین یک دستور اولین آشنایی شما با Helm است: `helm upgrade --install` یعنی «اگر نیست نصب کن، اگر هست به‌روز کن» و `--wait` یعنی «تا pod‌ها آماده نشدند برنگرد».

ببینید چه نصب شد:

```bash
k -n traefik get pods,svc
```

انتظار:

```
NAME                          READY   STATUS    RESTARTS   AGE
pod/traefik-d9f457cfb-w69fq   1/1     Running   0          40s

NAME              TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
service/traefik   NodePort   10.96.105.41   <none>        80:30080/TCP,443:30443/TCP   40s
```

توجه کنید: `TYPE` برابر `NodePort` است و `80:30080` یعنی «پورت ۸۰ سرویس روی ۳۰۰۸۰ node باز است»؛ همان پورتی که kind به ۸۰۸۰ لپ‌تاپ وصل کرده.

```bash
k get ingressclass
```

انتظار: یک ردیف `traefik (default)` با `CONTROLLER` برابر `traefik.io/ingress-controller`.

```bash
h list -A
```

انتظار: یک release به نام `traefik` در namespace با نام `traefik`، `STATUS` برابر `deployed`، `CHART` برابر `traefik-41.5.0`.

حالا از لپ‌تاپ به Traefik درخواست بزنید. هنوز هیچ Ingress نداریم:

```bash
curl -i http://localhost:8080/
```

انتظار:

```
HTTP/1.1 404 Not Found
Content-Type: text/plain; charset=utf-8
X-Content-Type-Options: nosniff
Date: Thu, 29 Oct 2026 08:44:10 GMT
Content-Length: 19

404 page not found
```

این `404` **خبر خوب** است: درخواست از لپ‌تاپ، از پورت ۸۰۸۰، از node، به Traefik رسید و Traefik گفت «برای این آدرس قانونی ندارم». مسیر شبکه کامل کار می‌کند؛ فقط قانون (Ingress) لازم داریم.

## گام ۲ — Ingress و host-based routing (۱۵ دقیقه)

فایل Ingress را به پروژه کپی کنید:

```bash
cp $S/k8s/ingress.yaml k8s/
```

```bash
cat k8s/ingress.yaml
```

این فایل یک قانون می‌نویسد: **اگر host برابر `churn.localhost` بود، همه‌ی مسیرها (`/`) برود به Service با نام `churn-api` روی پورت ۸۰.** `ingressClassName: traefik` می‌گوید کدام controller این قانون را بردارد. توضیح خط‌به‌خط در [CODE.md](CODE.md) است. اعمالش کنید:

```bash
make ingress-apply
```

انتظار: `ingress.networking.k8s.io/churn-api created`

```bash
k -n churn get ingress
```

انتظار:

```
NAME        CLASS     HOSTS             ADDRESS   PORTS   AGE
churn-api   traefik   churn.localhost             80      5s
```

(ستون `ADDRESS` در kind **خالی** می‌ماند، چون load balancer ابری نداریم. مشکلی نیست.) حالا API را با نام و بدون `port-forward` صدا بزنید:

```bash
curl -i http://churn.localhost:8080/ready
```

انتظار:

```
HTTP/1.1 200 OK
Content-Length: 38
Content-Type: application/json
Date: Thu, 29 Oct 2026 08:30:05 GMT
Server: uvicorn

{"status":"ready","model_version":"2"}
```

(سرآیند‌های `Date` و گاهی چند خط دیگر فرق می‌کنند.) نام `churn.localhost` بدون هیچ تنظیمی به لپ‌تاپ شما می‌رسد، و Traefik از روی همین نام، درخواست را به Service داد. پیش‌بینی هم بگیرید:

```bash
curl -s -X POST http://churn.localhost:8080/predict -H 'Content-Type: application/json' -d @examples/customer.json
```

انتظار: `{"churn_probability":0.9032,"churn":true,"threshold":0.5,"model_version":"2"}` (همان عددی که در جلسه‌ی ۱۱ با port-forward گرفتید).

### <bdi dir="rtl">host-based routing یعنی چه؟</bdi>

حالا با یک نام دیگر امتحان کنید:

```bash
curl -i http://other.localhost:8080/ready
```

انتظار: `HTTP/1.1 404 Not Found` و `404 page not found`. هر دو نام به همان لپ‌تاپ و همان پورت ۸۰۸۰ می‌رسند؛ **فقط نام host فرق دارد** و Traefik از روی آن تصمیم می‌گیرد. برای `other.localhost` قانونی ننوشته‌ایم، پس `404`.

مرورگر وقتی آدرس می‌زنید، نام host را در سرآیند `Host` می‌فرستد. می‌توانید همین را با `curl` هم ببینید، حتی بدون وابستگی به نام‌گذاری `.localhost`:

```bash
curl -s -H 'Host: churn.localhost' http://localhost:8080/ready
```

انتظار: همان `{"status":"ready","model_version":"2"}`. پس مسیریابی بر اساس سرآیند `Host` است، نه بر اساس خود آدرس IP. در گام ۴ یک host دوم (`prod.churn.localhost`) به همین ترتیب اضافه می‌شود: **یک ورودی، چند سرویس.**

اگر مرورگر دارید، `http://churn.localhost:8080/docs` را باز کنید؛ صفحه‌ی Swagger همان API را می‌بینید.

یک نکته‌ی مهم: قانون Ingress یک شیء در cluster است. اگر آن را پاک کنید (`k -n churn delete ingress churn-api`)، API هنوز کار می‌کند (pod‌ها و Service سر جایشان هستند)، فقط راه ورود از بیرون بسته می‌شود. نیازی به این کار نیست؛ همین الان آن را نزنید، چون در گام بعد خودش پاک می‌شود.

## گام ۳ — chart: بسته‌بندی با Helm (۲۰ دقیقه)

تا اینجا هر YAML را با `kubectl apply` اعمال کردید. اگر بخواهید همین سرویس را در یک محیط دوم با تعداد pod دیگر یا مدل دیگر بسازید، باید فایل‌ها را کپی و دستی ویرایش کنید. Helm این را حل می‌کند: **یک بار الگو، چند بار مقدار.**

<bdi dir="rtl">chart را به پروژه کپی کنید:</bdi>

```bash
cp -r $S/chart .
```

```bash
find chart -type f | sort
```

انتظار:

```
chart/churn-api/.helmignore
chart/churn-api/Chart.yaml
chart/churn-api/templates/NOTES.txt
chart/churn-api/templates/_helpers.tpl
chart/churn-api/templates/configmap.yaml
chart/churn-api/templates/deployment.yaml
chart/churn-api/templates/ingress.yaml
chart/churn-api/templates/service.yaml
chart/churn-api/values-dev.yaml
chart/churn-api/values-prod.yaml
chart/churn-api/values.yaml
```

این ساختار را بشناسید:

- <bdi dir="rtl">`Chart.yaml`: نام و نسخه‌ی chart.</bdi>
- <bdi dir="rtl">`values.yaml`: مقدار‌های پیش‌فرض. `values-dev.yaml` و `values-prod.yaml` فقط چیزهای متفاوت را می‌نویسند.</bdi>
- <bdi dir="rtl">`templates/`: همان YAML‌های جلسه‌ی ۱۱ (Deployment، Service، ConfigMap) به‌اضافه‌ی Ingress، ولی عددها و نام‌ها به `{{ .Values.... }}` تبدیل شده‌اند. فایل `_helpers.tpl` شیء نمی‌سازد، فقط تکه‌های مشترک (مثل نام و label‌ها) را نگه می‌دارد. `NOTES.txt` پیامی است که بعد از نصب چاپ می‌شود.</bdi>

مقدار‌ها را ببینید (قلب chart):

```bash
cat chart/churn-api/values.yaml
```

```bash
cat chart/churn-api/values-dev.yaml chart/churn-api/values-prod.yaml
```

<bdi dir="rtl">dev: یک pod، مدل `@champion`. prod: سه pod، **یک نسخه‌ی ثابت** مدل (`models:/churn/2`) تا یک `@champion` تازه، production را ناگهان عوض نکند، و host مخصوص خودش.</bdi>

### <bdi dir="rtl">lint و template</bdi>

اول chart را بررسی کنید:

```bash
make helm-lint
```

انتظار:

```
==> Linting chart/churn-api
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

خط `[INFO] ... icon is recommended` عادی است (فقط توصیه است). خطای واقعی با `[ERROR]` شروع می‌شود. حالا ببینید Helm با مقدار‌های dev چه YAML می‌سازد، **بدون اینکه به cluster دست بزند**:

```bash
make helm-template | head -50
```

انتظار: چهار شیء پشت‌سرهم (`ConfigMap`، `Service`، `Deployment`، `Ingress`) که هر کدام با `# Source: churn-api/templates/...` شروع می‌شوند. این دقیقاً مثل فایل‌های جلسه‌ی ۱۱ است، با نام `churn-api` و label‌های `app.kubernetes.io/...`. تعداد شیء‌ها را بشمارید:

```bash
make helm-template | grep -c '^kind:'
```

انتظار: `4`

حالا همین را با مقدار‌های prod بسازید و فرق‌ها را ببینید (تعداد replica و مدل و host):

```bash
make helm-template STAGE=prod | grep -E '^  replicas:|MODEL_URI|- host:'
```

انتظار:

```
  MODEL_URI: "models:/churn/2"
  replicas: 3
    - host: "prod.churn.localhost"
```

### پاک کردن شیء‌های جلسه‌ی ۱۱

اگر الان `helm install` بزنید خطا می‌گیرید. امتحان کنید (ضرر ندارد):

```bash
h install churn-api chart/churn-api -n churn -f chart/churn-api/values-dev.yaml
```

انتظار: خطا (یک خط طولانی):

```
Error: INSTALLATION FAILED: unable to continue with install: ConfigMap "churn-api-config" in namespace "churn" exists and cannot be imported into the current release: invalid ownership metadata; label validation error: missing key "app.kubernetes.io/managed-by": must be set to "Helm"; ...
```

علت: شیء‌هایی با همین نام را قبلاً **kubectl** ساخته و Helm فقط شیء‌های خودش را مدیریت می‌کند (هر شیء Helm یک label به نام `managed-by: Helm` دارد). پس اول شیء‌های جلسه‌ی ۱۱ را پاک می‌کنیم. این دستور همه‌ی فایل‌های `k8s/` را پاک می‌کند، **از جمله namespace با نام `churn`** و همه‌ی چیزهای داخلش (Deployment، Service، ConfigMap و Ingress):

```bash
k delete -f k8s/
```

انتظار: پنج خط `... deleted` (ConfigMap، Deployment، Ingress، Namespace، Service). حدود ۱۰ ثانیه طول می‌کشد. از این لحظه API خاموش است؛ چند دقیقه‌ی دیگر با Helm برمی‌گردد.

### نصب با Helm

یک نکته: image نسخه‌ی تازه را در گام ۴ لازم داریم؛ همین الان بسازیم که بعداً معطل نشویم. این همان image جلسه‌ی ۹ است با یک نام (tag) جدید، مثل وقتی که «نسخه‌ی ۰٫۷٫۱ منتشر شده»:

```bash
docker tag churn-api:0.7.0 churn-api:0.7.1
```

```bash
make push TAG=0.7.1
```

انتظار: چند خط `Layer already exists` و آخرش `0.7.1: digest: sha256:... size: 856` (حدود ۲ ثانیه).

حالا release را نصب کنید. `make helm-deploy` از `values-dev.yaml` استفاده می‌کند، namespace را می‌سازد و صبر می‌کند تا pod آماده شود:

```bash
make helm-deploy
```

انتظار (حدود ۱۰ ثانیه):

```
Release "churn-api" does not exist. Installing it now.
NAME: churn-api
LAST DEPLOYED: Thu Oct 29 08:30:31 2026
NAMESPACE: churn
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
Release churn-api (revision 1) of churn-api-0.1.0 is installed in namespace churn.
Model:    models:/churn@champion
Image:    localhost:5001/churn-api:0.7.0
Replicas: 1

Try it (the host name resolves to your laptop; 8080 is the Traefik port):
  curl http://churn.localhost:8080/ready

Watch the rollout:
  kubectl --context <your-context> -n churn rollout status deployment/churn-api
```

متن `NOTES` از فایل `templates/NOTES.txt` آمده است (بخش `Model`، `Image` و `Replicas` از مقدار‌های شما پر شده‌اند). بررسی کنید:

```bash
make helm-status
```

انتظار: سه بخش. اول `helm list` با یک ردیف (`churn-api`، `REVISION` برابر ۱، `deployed`، `CHART` برابر `churn-api-0.1.0`، `APP VERSION` برابر `0.7.0`). دوم `helm history` با یک revision به نام `Install complete`. سوم `kubectl get`:

```
NAME                        READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/churn-api   1/1     1            1           6s

NAME                             READY   STATUS    RESTARTS   AGE
pod/churn-api-6b7bb96668-jmbg2   1/1     Running   0          6s

NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/churn-api   ClusterIP   10.96.118.143   <none>        80/TCP    6s

NAME                                  CLASS     HOSTS             ADDRESS   PORTS   AGE
ingress.networking.k8s.io/churn-api   traefik   churn.localhost             80      6s
```

(نام pod و IP شما فرق دارد.) فقط **یک** pod است، چون `values-dev.yaml` این را خواسته. و:

```bash
curl -s http://churn.localhost:8080/ready
```

انتظار: `{"status":"ready","model_version":"2"}`. سرویس با Helm برگشت. همین است که «از دید کاربر هیچ چیز عوض نشد، ولی از دید ما هر شیء حالا یک release دارد».

نگاهی به مقدار‌هایی که Helm ثبت کرده:

```bash
h get values churn-api -n churn
```

انتظار: `USER-SUPPLIED VALUES:` و محتوای `values-dev.yaml` شما (یعنی `replicaCount: 1`، `config.modelUri`، `ingress.host` و `resources`).

## گام ۴ — upgrade، rollback و محیط prod (۲۰ دقیقه)

### یک upgrade سالم

سناریو: «نسخه‌ی ۰٫۷٫۱ آماده است و ترافیک زیاد شده». tag و تعداد replica را با `--set` عوض می‌کنیم. `--set` فقط برای این آزمایش است؛ در کار واقعی مقدار‌ها را در فایل می‌نویسید و در Git نگه می‌دارید. حتماً `-f values-dev.yaml` را هم بدهید (چرا، در عیب‌یابی آمده):

```bash
h upgrade churn-api chart/churn-api -n churn -f chart/churn-api/values-dev.yaml --set replicaCount=3 --set image.tag=0.7.1 --wait --timeout 120s
```

انتظار (حدود ۲۰ ثانیه، چون pod‌ها یکی‌یکی عوض می‌شوند):

```
Release "churn-api" has been upgraded. Happy Helming!
NAME: churn-api
LAST DEPLOYED: Thu Oct 29 08:31:35 2026
NAMESPACE: churn
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
TEST SUITE: None
...
```

```bash
k -n churn get pods
```

انتظار: سه pod با `1/1 Running`؛ تا چند ثانیه ممکن است pod قدیمی هم با `Terminating` دیده شود.

```bash
k -n churn get deployment churn-api -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

انتظار: `localhost:5001/churn-api:0.7.1`

### یک upgrade خراب

حالا کسی اشتباهاً tag را `0.7.9` می‌گذارد که وجود ندارد. با `--timeout 45s` منتظر می‌مانیم:

```bash
h upgrade churn-api chart/churn-api -n churn -f chart/churn-api/values-dev.yaml --set replicaCount=3 --set image.tag=0.7.9 --wait --timeout 45s
```

انتظار: بعد از ۴۵ ثانیه دستور با خطا تمام می‌شود:

```
level=WARN msg="upgrade failed" name=churn-api error="resource Deployment/churn/churn-api not ready. status: InProgress, message: Updated: 1/3\ncontext deadline exceeded"
Error: UPGRADE FAILED: resource Deployment/churn/churn-api not ready. status: InProgress, message: Updated: 1/3
context deadline exceeded
```

(خط `level=WARN` فقط در Helm نسخه‌ی ۴ هست.) مثل جلسه‌ی ۱۱ یادتان باشد: خطای «timed out» علت نیست، فقط می‌گوید برو دنبال علت. pod‌ها را ببینید:

```bash
k -n churn get pods
```

انتظار: سه pod قدیمی `1/1 Running` و یک pod تازه با `0/1` و وضعیت `ErrImagePull` یا `ImagePullBackOff`:

```
NAME                         READY   STATUS             RESTARTS   AGE
churn-api-5d9f655889-qkhks   1/1     Running            0          52s
churn-api-5d9f655889-qrjt2   1/1     Running            0          58s
churn-api-5d9f655889-vxfks   1/1     Running            0          64s
churn-api-5ddc8bcd7c-d557n   0/1     ImagePullBackOff   0          45s
```

کاربران مشکلی ندیدند (`maxUnavailable: 0`، همان درس جلسه‌ی ۱۱):

```bash
curl -s http://churn.localhost:8080/ready
```

انتظار: همچنان `{"status":"ready","model_version":"2"}`. تاریخچه‌ی release را ببینید:

```bash
h history churn-api -n churn
```

انتظار (ستون آخر کوتاه شده):

```
REVISION  UPDATED                   STATUS      CHART            APP VERSION  DESCRIPTION
1         Thu Oct 29 08:31:29 2026  superseded  churn-api-0.1.0  0.7.0        Install complete
2         Thu Oct 29 08:31:35 2026  deployed    churn-api-0.1.0  0.7.0        Upgrade complete
3         Thu Oct 29 08:31:53 2026  failed      churn-api-0.1.0  0.7.0        Upgrade "churn-api" failed: resource Deployment/churn/churn-api not ready. ...
```

سه نکته: revision ۲ هنوز آخرین نسخه‌ی سالم است؛ revision ۳ با `failed` ثبت شد؛ و ستون `APP VERSION` همچنان `0.7.0` است، چون آن فقط مقدار پیش‌فرض داخل `Chart.yaml` است و به tag واقعی image ربطی ندارد (tag را ما با `--set` عوض کردیم).

### rollback

به revision سالم ۲ برگردید:

```bash
h rollback churn-api 2 -n churn --wait --timeout 60s
```

انتظار: `Rollback was a success! Happy Helming!` (در کمتر از چند ثانیه؛ سه pod سالم هیچ‌وقت نرفته بودند).

```bash
h history churn-api -n churn
```

انتظار: یک revision **تازه** با شماره‌ی ۴ و `Rollback to 2`، و revision ۲ حالا `superseded` است:

```
2   ...  superseded  churn-api-0.1.0  0.7.0  Upgrade complete
3   ...  failed      churn-api-0.1.0  0.7.0  Upgrade "churn-api" failed: ...
4   ...  deployed    churn-api-0.1.0  0.7.0  Rollback to 2
```

<bdi dir="rtl">rollback تاریخچه را پاک نمی‌کند؛ یک قدم تازه به جلو می‌گذارد که محتوایش همان revision قدیمی است. pod خراب هم خودش رفت:</bdi>

```bash
k -n churn get pods
```

انتظار: سه pod با `1/1 Running` (و شاید یکی `Terminating` برای چند ثانیه).

### <bdi dir="rtl">Helm ConfigMap را هم نسخه می‌کند</bdi>

در جلسه‌ی ۱۱ دیدید که `kubectl rollout undo` تغییر ConfigMap را برنمی‌گرداند. حالا همان آزمایش با Helm. مدل را به نسخه‌ی ۱ می‌بریم (تغییری که با چشم دیده می‌شود، چون `model_version` عوض می‌شود). توجه کنید `checksum/config` در الگوی Deployment باعث می‌شود با عوض شدن ConfigMap، pod‌ها **خودشان** عوض شوند، بدون `rollout restart`:

```bash
h upgrade churn-api chart/churn-api -n churn -f chart/churn-api/values-dev.yaml --set replicaCount=3 --set image.tag=0.7.1 --set config.modelUri=models:/churn/1 --wait --timeout 90s
```

انتظار: `REVISION: 5` و `Upgrade complete` (حدود ۲۰ ثانیه).

```bash
curl -s http://churn.localhost:8080/ready
```

انتظار: `{"status":"ready","model_version":"1"}`

```bash
k -n churn get configmap churn-api-config -o jsonpath='{.data.MODEL_URI}{"\n"}'
```

انتظار: `models:/churn/1`

حالا یک دستور Helm برای برگشت به revision ۴:

```bash
h rollback churn-api 4 -n churn --wait --timeout 90s
```

انتظار: `Rollback was a success! Happy Helming!`

```bash
k -n churn get configmap churn-api-config -o jsonpath='{.data.MODEL_URI}{"\n"}'
```

انتظار: `models:/churn@champion`. **ConfigMap هم برگشت.** چند ثانیه صبر کنید تا pod‌ها عوض شوند، بعد:

```bash
curl -s http://churn.localhost:8080/ready
```

انتظار: `{"status":"ready","model_version":"2"}`. (اگر هنوز `1` دیدید، ۵ تا ۱۰ ثانیه بعد دوباره بزنید.) در جلسه‌ی ۱۱ برای همین برگشت باید فایل را دستی اصلاح و `rollout restart` می‌کردید. با Helm هر چیزی که در release بود (ConfigMap، image، تعداد replica، Ingress) یک‌جا با یک شماره‌ی revision نگه داشته می‌شود.

**هشدار مهم:** روی یک release که Helm مدیریت می‌کند، با `kubectl` تغییر ندهید (`set image`، `edit`، `rollout undo`). Helm از این تغییرها خبر ندارد و بعداً یا آن‌ها را از بین می‌برد یا وضعیتی می‌سازد که نه با Git می‌خواند و نه با Helm (مثلاً ConfigMap یک چیز می‌گوید و pod‌ها چیز دیگر). هر تغییر: مقدار را عوض کنید و `helm upgrade` بزنید.

### محیط prod: همان chart، مقدار دیگر

یک release دوم از **همان chart** در یک namespace دیگر می‌سازیم، فقط با فایل مقدار prod:

```bash
make helm-deploy STAGE=prod NS=churn-prod
```

انتظار (حدود ۱۰ ثانیه): `STATUS: deployed`، `REVISION: 1`، و در `NOTES`: `Model: models:/churn/2`، `Replicas: 3`، و خط `curl http://prod.churn.localhost:8080/ready`.

```bash
h list -A
```

انتظار: سه release، `churn-api` در `churn`، `churn-api` در `churn-prod`، و `traefik`:

```
NAME      	NAMESPACE 	REVISION	UPDATED                             	STATUS  	CHART          	APP VERSION
churn-api 	churn    	6       	...	deployed	churn-api-0.1.0	0.7.0
churn-api 	churn-prod	1       	...	deployed	churn-api-0.1.0	0.7.0
traefik   	traefik  	1       	...	deployed	traefik-41.5.0 	v3.7.13
```

(ترتیب ردیف‌ها و شماره‌ی `REVISION` ممکن است فرق کند.) release دوم همان نام را دارد، چون در namespace دیگری است. حالا دو host را مقایسه کنید:

```bash
curl -s http://prod.churn.localhost:8080/ready
```

```bash
curl -s http://churn.localhost:8080/ready
```

انتظار: هر دو `{"status":"ready","model_version":"2"}`، ولی از دو جا: `churn.localhost` از release dev (یک مدل متحرک `@champion`) و `prod.churn.localhost` از release prod (مدل ثابت `models:/churn/2`). تعداد pod‌ها را ببینید:

```bash
k -n churn-prod get deploy
```

انتظار: `churn-api   3/3   3   3`. این **host-based routing** است که در گام ۲ دیدید، این بار با دو سرویس واقعی پشت یک ورودی.

در پایان، release dev را به همان چیزی برگردانید که فایل می‌گوید (بدون `--set`، یک replica):

```bash
make helm-deploy
```

انتظار: `REVISION` بعدی، `Upgrade complete`. (چون `--set` ندادید، تعداد replica به ۱ برمی‌گردد و Helm یک pod را حذف می‌کند.)

## گام ۵ — commit، tag و بررسی نهایی (۱۰ دقیقه)

وضعیت Git:

```bash
git status --short
```

انتظار: `Makefile` با `M`؛ و `chart/` و فایل `k8s/ingress.yaml` با `??` (فایل‌های جلسه‌ی ۱۱ در `k8s/` دست‌نخورده‌اند).

```bash
git add chart k8s Makefile && git commit -m "feat: Ingress (Traefik) and a Helm chart for the API"
```

انتظار: چند فایل تغییر کرده است (`chart/` یازده فایل، `k8s/ingress.yaml` و `Makefile`).

```bash
git status --short
```

انتظار: خالی.

```bash
git push -u origin feature/ingress-helm
```

در Gitea (`http://localhost:3000`) برای شاخه‌ی `feature/ingress-helm` یک Pull Request بسازید و در توضیح بنویسید:

```
Expose the API with Traefik and package it as a Helm chart.
k8s/ingress.yaml: host-based routing for churn.localhost (ingressClassName traefik).
chart/churn-api: Deployment, Service, ConfigMap, Ingress as templates; values.yaml +
values-dev.yaml + values-prod.yaml; checksum/config annotation rolls the pods when settings change.
Makefile: ingress-up, helm-lint, helm-template, helm-deploy, helm-status, helm-rollback (every
helm and kubectl call uses --kube-context / --context kind-mlops).
```

بازبینی و Merge کنید، بعد:

```bash
git switch main && git pull
```

```bash
git tag -a v0.10.0 -m "Session 12: Ingress with Traefik and a Helm chart"
```

```bash
git push origin v0.10.0
```

یک نکته: فایل‌های `k8s/` جلسه‌ی ۱۱ در Git می‌مانند (سابقه و مرجع‌اند)، ولی از حالا **منبع حقیقت** برای استقرار chart است. دیگر `make k8s-deploy` نزنید، چون شیء‌های Helm را زیر دست خود kubectl می‌گیرد.

---

## بررسی پایان کار

<bdi dir="rtl">Traefik، release `churn-api` در `churn` و release در `churn-prod` باید روشن باشند، و MLflow هم. بعد:</bdi>

```bash
~/mlops-lab/scripts/verify.sh s12
```

انتظار: همه‌ی خط‌ها `[PASS]` باشند (۹ بررسی). اگر خطی `[FAIL]` شد، متن آن می‌گوید چه چیزی کم است؛ جدول عیب‌یابی را ببینید. خروجی را همراه با تکلیف برای مدرس بفرستید.

## معیار پایان کار

- [ ] شاخه‌ی `feature/ingress-helm` ساخته شد و با Pull Request وارد `main` شد
- [ ] `make ingress-up` اجرا شد و `k -n traefik get pods` یک pod `1/1` نشان می‌دهد
- [ ] `curl http://localhost:8080/` پیش از Ingress `404` داد و می‌دانید چرا این خبر خوب بود
- [ ] `curl http://churn.localhost:8080/ready` جواب `model_version` را داد و `other.localhost` جواب `404` گرفت
- [ ] می‌توانید با یک جمله بگویید Ingress و Ingress controller چه فرقی دارند
- [ ] `helm lint` و `helm template` را اجرا کردید و فرق خروجی dev و prod را دیدید
- [ ] شیء‌های جلسه‌ی ۱۱ را پاک کردید و می‌دانید چرا `helm install` روی آن‌ها خطا داد
- [ ] release `churn-api` را در `churn` نصب کردید و با `helm upgrade` تعداد replica و tag را عوض کردید
- [ ] upgrade خراب (`0.7.9`) را دیدید، علتش را از `ImagePullBackOff` فهمیدید، و با `helm rollback` برگشتید
- [ ] `helm history` یک revision `failed` و یک `Rollback to` نشان می‌دهد (Helm فقط ۱۰ revision آخر را نگه می‌دارد؛ revision‌های قدیمی خودشان حذف می‌شوند)
- [ ] دیدید که `helm rollback` ConfigMap را هم برمی‌گرداند و می‌توانید فرقش با `kubectl rollout undo` را توضیح دهید
- [ ] release prod در `churn-prod` از `prod.churn.localhost` جواب می‌دهد
- [ ] tag `v0.10.0` روی `main` است و push شده
- [ ] `~/mlops-lab/scripts/verify.sh s12` همه‌ی بررسی‌ها را `PASS` داد

## عیب‌یابی

اصل کلی: برای Kubernetes مثل جلسه‌ی ۱۱ **اول events** (`k -n churn get events --sort-by=.lastTimestamp`)؛ برای Helm: `h status churn-api -n churn`، `h history churn-api -n churn` و `make helm-template` (ببینید Helm چه YAML ساخته).

| نشانه | علت | راه‌حل |
| --- | --- | --- |
| `curl http://churn.localhost:8080/...` می‌گوید `404 page not found` | Traefik کار می‌کند ولی Ingress برای این host نیست، یا نامش اشتباه است | `k get ingress -A` را ببینید. ستون `HOSTS` باید دقیقاً `churn.localhost` باشد و `CLASS` برابر `traefik`. در گام ۲ `make ingress-apply` را بزنید |
| `curl: (7) Failed to connect to ... port 8080` یا `Connection refused` | پورت ۳۰۰۸۰ node به ۸۰۸۰ لپ‌تاپ وصل نیست، یا Traefik نصب نیست | `docker port mlops-control-plane` باید خط `30080/tcp -> 127.0.0.1:8080` داشته باشد. اگر ندارد، cluster با تنظیم قدیمی ساخته شده: `kind delete cluster --name mlops`، بعد `make k8s-up`، `make push`، `make k8s-deploy` و دوباره گام ۱. اگر دارد: `k -n traefik get pods` را ببینید |
| `curl: (6) Could not resolve host: churn.localhost` | سیستم شما نام `.localhost` را خودکار حل نمی‌کند (curl یا DNS قدیمی) | `curl --resolve churn.localhost:8080:127.0.0.1 http://churn.localhost:8080/ready` یا `curl -H 'Host: churn.localhost' http://localhost:8080/ready` |
| `make ingress-up`: `no such file or directory ... traefik-41.5.0.tgz` | فایل chart از بسته‌ی آفلاین نصب نشده | با اینترنت: `helm repo add traefik https://traefik.github.io/charts`، بعد `helm pull traefik/traefik --version 41.5.0 -d ~/mlops-lab/charts`. بدون اینترنت: از مدرس بپرسید. نکته: در Helm نسخه‌ی ۴ دستور `helm pull traefik --repo ...` کار نمی‌کند، حتماً اول `repo add` |
| pod Traefik `ImagePullBackOff` | image `traefik:v3.7.13` در cluster نیست و اینترنت هم نیست | با اینترنت خودش دانلود می‌شود (۵۰ مگابایت). آفلاین: image باید با بسته‌ی دوره به cluster داده شود (`scripts/kind-up.sh` در جلسه‌ی ۱۱ این کار را می‌کرد). از مدرس بپرسید |
| `make ingress-up`: `Error: INSTALLATION FAILED: ... cannot reuse a name that is still in use` | release `traefik` از قبل هست و در حالت خراب مانده | `h list -A` را ببینید (Helm نسخه‌ی ۴ همه‌ی وضعیت‌ها را نشان می‌دهد). `h uninstall traefik -n traefik` و دوباره `make ingress-up` |
| `EXTERNAL-IP` سرویس Traefik `<pending>` است | فایل `traefik-values.yaml` قدیمی است (در آن `service.type` ناشناخته بود) | `git -C ~/mlops-lab pull` و دوباره `make ingress-up`. حتی با `<pending>` پورت‌های NodePort کار می‌کردند |
| `helm install` می‌گوید `exists and cannot be imported into the current release: invalid ownership metadata` | شیء‌های جلسه‌ی ۱۱ (ساخته‌ی kubectl) هنوز هستند | `k delete -f k8s/` و بعد دوباره `make helm-deploy` (گام ۳) |
| `Error: INSTALLATION FAILED: ... cannot reuse a name that is still in use` برای `churn-api` | release با این نام قبلاً هست (مثلاً نصب نیمه‌کاره) | `h list -n churn`. اگر `failed` است: `h uninstall churn-api -n churn` و دوباره `make helm-deploy` |
| `make helm-lint` خطای `[ERROR] templates/...: nil pointer evaluating interface {}.xyz` | غلط تایپی در نام یک مقدار (`.Values.ingres.host`) یا مقداری که در `values.yaml` نیست | شماره‌ی خط و نام در پیام هست. نام را با `values.yaml` مقایسه کنید. `make helm-template` همان خطا را نشان می‌دهد |
| `Error: YAML parse error ... did not find expected key` یا `mapping values are not allowed` | تورفتگی خراب در یک template (معمولاً `nindent` با عدد اشتباه) | `h template churn-api chart/churn-api --debug` YAML ناقص را چاپ می‌کند؛ نزدیک خط خطا را ببینید. `toYaml ... \| nindent N` باید N را برابر تورفتگی همان خط بگیرد |
| بعد از `helm upgrade` تعداد replica یا host به پیش‌فرض برگشت | `-f values-dev.yaml` را ندادید. Helm مقدار‌های upgrade قبلی را **به‌صورت پیش‌فرض نگه نمی‌دارد** | همیشه `-f` را بدهید (یا `make helm-deploy`). برای نگه داشتن مقدارهای قبلی: `--reuse-values`. ببینید چه ثبت شده: `h get values churn-api -n churn` |
| `helm upgrade --wait` خطای `context deadline exceeded` می‌دهد | pod جدید آماده نمی‌شود (image نیست، probe شکست می‌خورد، MLflow خاموش است) | `k -n churn get pods` و `k -n churn describe pod NAME` (Events). بعد `h rollback churn-api REV -n churn` (REV از `h history`) |
| بعد از `helm rollback` هنوز مدل قدیمی/اشتباه جواب می‌دهد | روی release با `kubectl rollout undo` یا `set image` دست زده‌اید | روی release Helm با kubectl تغییر ندهید. درست‌کردن: `make helm-deploy` (مقدار درست از فایل) و اگر pod‌ها عوض نشدند `k -n churn rollout restart deployment/churn-api` |
| `h rollback`: `Error: release has no 2` (یا مشابه) | شماره‌ی revision اشتباه است | `h history churn-api -n churn` و شماره‌ی یک revision `superseded` یا `deployed` را بدهید |
| `make helm-deploy STAGE=prod NS=churn-prod` می‌گوید `Error: INSTALLATION FAILED: ... namespaces "churn-prod" not found` | از دستور دستی بدون `--create-namespace` استفاده کرده‌اید | با `make helm-deploy` (که `--create-namespace` دارد) بزنید |
| `Error: ... no such file or directory: chart/churn-api` | در پوشه‌ی پروژه نیستید یا chart کپی نشده | `cd ~/work/churn-mlops` و `cp -r $S/chart .` (و `S=~/mlops-lab/s12`) |
| `h: command not found` یا `k: command not found` | alias در این ترمینال تعریف نشده | دو `alias` گام ۱ را دوباره بزنید |
| `helm: command not found` | helm نصب نیست | از بسته‌ی آفلاین دوره نصب کنید (`~/mlops-lab/scripts/install-from-bundle.sh`) یا از مدرس بپرسید؛ بعد `~/mlops-lab/s12/preflight.sh` |
| `kubectl config current-context` چیزی غیر از `kind-mlops` نشان می‌دهد | context فعلی به cluster دیگری اشاره می‌کند | با `k`، `h` و `make` ادامه دهید و بدون context به cluster دیگر دستور نزنید. `kubectl config get-contexts` |
| `Cannot connect to the Docker daemon` / `Unable to connect to the server` | Docker یا cluster روشن نیست | Docker را روشن کنید. `docker ps --filter name=mlops-control-plane`؛ اگر `Exited` است: `docker start mlops-control-plane` یا `make k8s-up` |
| پورت ۸۰۸۰ لپ‌تاپ را برنامه‌ی دیگری گرفته (preflight هشدار داد) | یک سرویس یا container دیگر روی ۸۰۸۰ | آن را موقتاً خاموش کنید (`docker ps --filter publish=8080`). cluster با `kind-config.yaml` ساخته شده و پورت ثابت است |
| Windows: دستورها خطای عجیب می‌دهند | از PowerShell استفاده می‌کنید | همه‌ی دستورها را داخل WSL Ubuntu بزنید |
| `verify.sh s12` در یکی از بررسی‌ها `FAIL` می‌دهد | release یا Traefik نیست، یا commit یا tag کم است | متن همان خط را بخوانید؛ `h list -A` و `git describe --tags` را بررسی کنید و گام مربوط را کامل کنید |
| tag `v0.10.0` روی commit قدیمی است (پیش از merge زده شده) | tag را پیش از `git switch main && git pull` ساخته‌اید | `git tag -d v0.10.0 && git push origin :refs/tags/v0.10.0`، بعد روی `main` به‌روز دوباره tag و push |

*<bdi dir="rtl">*cluster را نگه دارید.** در جلسه‌ی ۱۳ (مانیتورینگ) روی همین cluster کار می‌کنیم؛ Traefik و release‌ها باید بمانند. فقط وقتی مدرس گفت (آخر دوره) cluster را پاک کنید:</bdi>

```text
kind delete cluster --name mlops
```

سرویس‌های آزمایشگاه (SeaweedFS، MLflow، registry محلی) را هم نگه دارید و `docker compose down -v` نزنید. تکلیف در [HOMEWORK.md](HOMEWORK.md) است.

</div>
