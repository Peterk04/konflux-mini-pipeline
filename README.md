# konflux-mini-pipeline

A small CI/CD pipeline I built for my Cloud Computing 1 term paper. It's a mini version of Konflux, the build system I used at Red Hat. You push code, it gets built and scanned, and it only gets deployed if the scan passes.

## What happens on a push

1. GitHub sends a webhook through a cloudflared tunnel to Tekton Triggers, which starts a run.
2. clone: grabs the commit you pushed.
3. build-push: Buildah builds the image and pushes it to Quay, tagged with the commit SHA.
4. sbom: Syft lists every package in the image.
5. scan: Clair checks those packages for known vulnerabilities.
6. gate: fails the run if there are any High or Critical vulnerabilities that have a fix.
7. deploy: if the gate passed, the app gets updated to the new image by its digest.

## What's in here

- `app/` is the demo web page.
- `Dockerfile` builds the page into an image on `python:3.13-slim`.
- `k8s/` has the Deployment and a NodePort Service, so the app shows up on localhost:8081.
- `tekton/pipeline.yaml` is the pipeline.
- `tekton/run-manual.yaml` starts a run by hand.
- `tekton/triggers.yaml` is the webhook listener, binding and template.

## Running it

You'll need Minikube with Tekton Pipelines and Triggers installed and Clair running in the cluster. Before the first run, create the `quay-creds` secret (a Quay robot account), the `github-webhook` secret, and the `pipeline-sa` and `tekton-triggers-sa` service accounts.

```bash
kubectl apply -f k8s/
kubectl apply -f tekton/pipeline.yaml -f tekton/triggers.yaml
kubectl create -f tekton/run-manual.yaml   # one manual run
```

For runs on every push, point a GitHub webhook at the tunnel URL (JSON, push events only, same secret).

## Trying the gate

Change the `FROM` line in the Dockerfile to `python:3.11.4-slim-bookworm` and push. The gate blocks it and the old version stays up. Put it back to `python:3.13-slim`, push again, and it deploys.

Peter Keappock, 20068658. AI use is declared in the term paper.
