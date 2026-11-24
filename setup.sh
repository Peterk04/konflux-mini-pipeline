#!/usr/bin/env bash
# Brings up the whole demo on a fresh Minikube cluster, in order.
# Safe to run again: every step applies or skips if it already exists.
#
# Before running, export your secrets (they are never stored in git):
#   export QUAY_USER='peterk04+tekton'
#   export QUAY_TOKEN='<robot token>'
#   export WEBHOOK_SECRET='<same secret as the GitHub webhook>'
set -e

TEKTON=https://infra.tekton.dev/tekton-releases

echo "1. Start the cluster"
minikube start --driver=docker --cpus=4 --memory=6144 \
  --ports=8080:30080,8081:30081,9097:30097

echo "2. Install Tekton Pipelines, Triggers and Dashboard"
kubectl apply -f $TEKTON/pipeline/previous/v1.18.0/release.yaml
kubectl wait -n tekton-pipelines --for=condition=Available deploy --all --timeout=300s
kubectl apply -f $TEKTON/triggers/previous/v0.38.0/release.yaml
kubectl apply -f $TEKTON/triggers/previous/v0.38.0/interceptors.yaml
kubectl apply -f $TEKTON/dashboard/previous/v0.74.0/release.yaml
kubectl wait -n tekton-pipelines --for=condition=Available deploy --all --timeout=300s
kubectl patch svc tekton-dashboard -n tekton-pipelines \
  -p '{"spec":{"type":"NodePort","ports":[{"port":9097,"targetPort":9097,"nodePort":30097}]}}'

echo "3. Start Clair and its PostgreSQL database"
kubectl create ns clair --dry-run=client -o yaml | kubectl apply -f -
kubectl -n clair get secret clair-db >/dev/null 2>&1 || \
  kubectl -n clair create secret generic clair-db --from-literal=password="$(openssl rand -hex 16)"
kubectl apply -f infra/clair.yaml
kubectl -n clair wait --for=condition=Available deploy --all --timeout=300s

echo "4. Secrets and permissions for the pipeline"
kubectl create secret docker-registry quay-creds --docker-server=quay.io \
  --docker-username="$QUAY_USER" --docker-password="$QUAY_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount pipeline-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl create role pipeline-deployer --verb=get,list,watch,create,update,patch \
  --resource=deployments.apps,services --dry-run=client -o yaml | kubectl apply -f -
kubectl create role pipeline-watcher --verb=get,list,watch \
  --resource=pods,replicasets.apps --dry-run=client -o yaml | kubectl apply -f -
kubectl create rolebinding pipeline-deployer --role=pipeline-deployer \
  --serviceaccount=default:pipeline-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl create rolebinding pipeline-watcher --role=pipeline-watcher \
  --serviceaccount=default:pipeline-sa --dry-run=client -o yaml | kubectl apply -f -

echo "5. Deploy the app (first run only, so a re-run doesn't undo the pipeline's last deploy)"
kubectl get deploy demo-app >/dev/null 2>&1 || kubectl apply -f k8s/

echo "6. Add the pipeline"
kubectl apply -f tekton/pipeline.yaml

echo "7. Webhook trigger"
kubectl create secret generic github-webhook --from-literal=token="$WEBHOOK_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount tekton-triggers-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl create rolebinding tekton-triggers-sa-eventlistener \
  --clusterrole=tekton-triggers-eventlistener-roles \
  --serviceaccount=default:tekton-triggers-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl create clusterrolebinding tekton-triggers-sa-eventlistener-cluster \
  --clusterrole=tekton-triggers-eventlistener-clusterroles \
  --serviceaccount=default:tekton-triggers-sa --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f tekton/triggers.yaml
kubectl wait --for=condition=Ready eventlistener/github-listener --timeout=180s
kubectl create service nodeport el-github-nodeport --tcp=8080:8080 --node-port=30080 \
  --dry-run=client -o yaml \
  | sed 's/app: el-github-nodeport/eventlistener: github-listener/' \
  | kubectl apply -f -

echo "Done. Dashboard: http://localhost:9097   App: http://localhost:8081"
echo "Now run:  cloudflared tunnel --url http://localhost:8080"
echo "and put the printed https URL into the GitHub webhook."
