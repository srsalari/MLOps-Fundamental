#!/usr/bin/env bash
# =============================================================================
# s12/preflight.sh — ready for session 12? Run it BEFORE class:
#     ~/mlops-lab/s12/preflight.sh                 (PROJECT=/path to check another folder)
# Checks the laptop (helm, kind, kubectl, ports 8080/8443) and that
# ~/work/churn-mlops is at the end state of session 11, plus what the lab needs:
# the kind cluster "mlops" with its port mapping, the Traefik chart, MLflow with @champion.
# Exit code: 0 = ready, 1 = something to fix. Read-only.
# =============================================================================
SESSION=12
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/preflight-lib.sh"
preflight_begin

KCTX="${KCTX:-kind-mlops}"
K8S_NODE="${K8S_NODE:-mlops-control-plane}"

s11_code()     { tracked k8s/deployment.yaml k8s/service.yaml k8s/configmap.yaml k8s/namespace.yaml && grep -q '^k8s-deploy:' Makefile; }
s09_champion() { CHAMP=$(mlf_get "api/2.0/mlflow/registered-models/alias?name=churn&alias=champion" \
                   | jq_py "print(d['model_version']['version'])") && [ -n "$CHAMP" ]; }
lab_network()  { docker network inspect mlops-lab >/dev/null 2>&1; }
cluster_up()   { kubectl --context "$KCTX" get nodes 2>/dev/null | grep -q ' Ready '; }
node_ports()   { docker port "$K8S_NODE" 30080 2>/dev/null | grep -q ':8080$' && docker port "$K8S_NODE" 30443 2>/dev/null | grep -q ':8443$'; }
node_on_lab()  { docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$K8S_NODE" 2>/dev/null | grep -qw mlops-lab; }
image_in_reg() { curl -fsS --max-time 5 http://localhost:5001/v2/churn-api/tags/list 2>/dev/null | grep -q '"0.7.0"'; }
chart_file()   { ls "$LAB"/charts/traefik-*.tgz >/dev/null 2>&1; }
helm_cmd()     { command -v helm >/dev/null 2>&1; }
churn_pods()   { N=$(kubectl --context "$KCTX" -n churn get pods --no-headers 2>/dev/null | grep -c ' 1/1 '); [ "${N:-0}" -ge 1 ]; }
traefik_img()  { docker exec "$K8S_NODE" crictl images 2>/dev/null | grep -q '/traefik '; }

if project_begin "end of session 11"; then
  soft  on_main  "on branch main"                                   "git switch main && git pull"
  check s11_code "k8s/ manifests and the k8s-deploy target are committed" "s11/README.md, steps 2 and 5"
  check_tag v0.9.0 "session 11" s11
fi
echo "[Lab services]"
svc_s3
svc_mlflow
check s09_champion "registered model 'churn' has the alias @champion" "make promote   (s07/README.md, step 3)"
[ -n "${CHAMP:-}" ] && info "@champion = version $CHAMP"
check lab_network "Docker network mlops-lab exists" "cd ~/mlops-lab/compose && docker compose up -d seaweedfs mlflow"
echo "[Cluster from session 11]"
check cluster_up  "kind cluster answers on context $KCTX (node Ready)" "make k8s-up   (in the project; Docker must be running)"
check node_ports  "the node maps its ports 30080/30443 to laptop ports 8080/8443 (Traefik needs them)" "the cluster was made with an old kind config: kind delete cluster --name mlops ; make k8s-up ; make push ; make k8s-deploy"
soft  node_on_lab "the node is connected to the Docker network mlops-lab (pods reach MLflow)" "docker network connect mlops-lab $K8S_NODE"
soft  image_in_reg "churn-api:0.7.0 is in the local registry localhost:5001" "make push   (in the project)"
soft  churn_pods  "the session 11 pods are running in namespace churn (the lab replaces them with a Helm release)" "make k8s-deploy"
info "current kubectl context: $(kubectl config current-context 2>/dev/null || echo none)   (the lab always passes --context $KCTX)"
echo "[Helm and Traefik]"
check helm_cmd    "helm is installed: $(helm version --short 2>/dev/null | head -1)" "install it from the offline bundle (~/mlops-lab/scripts/install-from-bundle.sh) or from the instructor"
soft  chart_file  "the Traefik chart file exists in ~/mlops-lab/charts/ (it comes with the offline bundle)" "install-from-bundle.sh puts it there; with internet: helm repo add traefik https://traefik.github.io/charts && helm pull traefik/traefik --version 41.5.0 -d ~/mlops-lab/charts"
soft  traefik_img "the Traefik image is already in the cluster node (no internet needed)" "online it is pulled in the lab (about 50MB); offline: kind load image-archive from the bundle (scripts/kind-up.sh does it)"
preflight_end
