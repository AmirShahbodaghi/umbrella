# Helm Generic

Shared Helm chart for deploying applications to Kubernetes using a consistent set of templates and per-application values files.

This repository is used with Argo CD and ApplicationSets. Each matching application values file generates an Argo CD Application that renders the chart at the repository root.

- **Repository:** `https://gitlab.ir/devops/cd/umbrella/helm-generic.git`
- **Tracked branch:** `main`
- **Chart path:** `.`
- **General application values:** `values/general/*.yaml`

> This README describes the repository layout and deployment workflow. For exact supported values, defaults, and enable/disable conditions, refer to `values.yaml` and the files in `templates/`. Resource names and settings below must be checked against those templates.

## Repository Structure

```text
helm-generic/
├── Chart.yaml
├── README.md
├── values.yaml
├── templates/
│   ├── _helpers.tpl
│   ├── Backendtrafficpolicy.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── grpcroute.yaml
│   ├── hpa.yaml
│   ├── httproute.yaml
│   ├── pvc.yaml
│   ├── service.yaml
│   ├── serviceaccount.yaml
│   └── servicemonitor.yaml
└── values/
    ├── general/
    │   ├── payeshnotify.yaml
    │   ├── requestback.yaml
    │   └── requestfront.yaml
```

| Path | Purpose |
| --- | --- |
| `Chart.yaml` | Chart metadata and dependencies, if any |
| `values.yaml` | Default chart configuration |
| `templates/` | Kubernetes manifest templates shared by applications |
| `templates/_helpers.tpl` | Reusable Helm template helpers |
| `values/<group>/<application>.yaml` | Overrides for a specific application and environment/group |

The directory name identifies an environment or application group. It does **not** automatically select the destination namespace; that is configured in the Argo CD ApplicationSet.

## Chart Templates

The repository contains templates for the following resource types. Whether a resource is rendered, and how it is configured, depends on the actual template conditions and values.

| Template | Intended purpose | Requirements to check |
| --- | --- | --- |
| `deployment.yaml` | Application pods and rollout configuration | Images, container settings, probes, resource requests/limits |
| `service.yaml` | Network access to application pods | Service ports, target ports, and pod selectors |
| `configmap.yaml` | Non-secret application configuration | Required keys and how the workload consumes them |
| `serviceaccount.yaml` | Pod identity | Required RBAC and any workload identity integration |
| `pvc.yaml` | Persistent storage claims | Storage class, capacity, access modes, and retention behavior |
| `hpa.yaml` | Horizontal Pod Autoscaler | Appropriate metrics APIs; resource requests when using utilization-based metrics |
| `httproute.yaml` | HTTP routing through Gateway API | Compatible Gateway API CRDs, controller, Gateway, and route attachment permissions |
| `grpcroute.yaml` | gRPC routing through Gateway API | Compatible GRPCRoute CRD and controller support |
| `Backendtrafficpolicy.yaml` | Backend traffic policy | The CRD and controller matching the template's actual `apiVersion` and `kind` |
| `servicemonitor.yaml` | Metrics scrape configuration | ServiceMonitor CRD and a Prometheus configuration selecting the resource |

> A template file does not guarantee its resource is enabled. Inspect the rendered manifests to see what a particular application's values produce. Do not assume that installing this chart also installs external CRDs or controllers.

## Configuration Model

Each application uses two configuration layers:

```text
values.yaml                              Shared chart defaults
    +
values/<group>/<application>.yaml         Application-specific overrides
    =
Rendered Kubernetes manifests
```

Helm merges the supplied values over the chart defaults. Map entries are merged; lists are generally replaced rather than appended.

### Application Identity

The current Git files generator expects a top-level `appName` in each matching values file:

```yaml
# values/general/payeshnotify.yaml
appName: payeshnotify

# Add the remaining settings required by this chart.
# Use values.yaml and a working application file as references.
```

This is an identity example, **not a complete deployment configuration**.

- `appName` becomes the generated Argo CD Application name.
- It must be a valid Kubernetes resource name.
- It must be unique among Applications in the `argocd` namespace.
- Use environment-qualified names when necessary, such as `finance-dev-api` and `finance-prod-api`.
- Keep filenames aligned with application names for clarity, although the generator takes the name from `appName`, not the filename.

Kubernetes workload naming depends on the chart helpers and templates. Verify that multiple applications in the same namespace do not render resources with conflicting names.

### Where to Find Supported Settings

Before changing an application:

1. Read the root `values.yaml` for defaults and configuration structure.
2. Check a working values file for a similar application.
3. Read the relevant template for required fields and rendering conditions.
4. Render the chart to verify the resulting manifests.

Do not introduce assumed keys such as `ingress.enabled`, `image.tag`, or `autoscaling.enabled` unless the templates actually support them. Unknown values may be silently unused unless schema validation catches them.

## Deployment Through Argo CD

```text
Commit application values or chart changes to main
    ↓
ApplicationSet discovers matching values files
    ↓
One Argo CD Application is generated per file
    ↓
Argo CD renders this chart with that file
    ↓
Kubernetes resources are reconciled
```

The supplied `general-apps` ApplicationSet is maintained in the separate `argocd-apps` repository. Its relevant configuration is:

```yaml
spec:
  generators:
    - git:
        repoURL: https://gitlab.ir/devops/cd/umbrella/helm-generic.git
        revision: main
        files:
          - path: "values/general/*.yaml"
  template:
    metadata:
      name: "{{appName}}"
      namespace: argocd
    spec:
      project: default
      source:
        repoURL: https://gitlab.ir/devops/cd/umbrella/helm-generic.git
        targetRevision: main
        path: .
        helm:
          valueFiles:
            - "{{path}}/{{path.filename}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: general
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

This is an excerpt for reference, not a complete ApplicationSet manifest. It uses the existing legacy templating syntax; enabling Go templates requires updating the expressions.

For `values/general/payeshnotify.yaml`, this means:

| Setting | Value |
| --- | --- |
| Argo CD Application | Value of `appName`, for example `payeshnotify` |
| Application namespace | `argocd` |
| Workload destination namespace | `general` |
| Chart location | Repository root |
| Values override | `values/general/payeshnotify.yaml` |

Argo CD uses Helm to render manifests and manages the resources itself. Do not expect these deployments to appear as independently installed releases in `helm list`.

Only `values/general/*.yaml` is selected by this ApplicationSet. Other folders need their own ApplicationSets or an explicitly extended generator. A `.yml` file does not match the shown `.yaml` pattern.

## Prerequisites

### Local Validation

- Git access to this repository
- Helm 3
- Access to chart dependency repositories, if `Chart.yaml` declares dependencies
- Optionally, `kubectl` and access to a suitable validation cluster

### Cluster Deployment

- Argo CD and its ApplicationSet controller
- Argo CD access to this private Git repository
- A workload AppProject permitting the repository, destination, and required resource kinds
- Required namespaces, or permission for Argo CD to create them
- Container registry access and image pull credentials where needed
- Secrets referenced by the workload
- Required CRDs, controllers, metrics services, and storage infrastructure for enabled features

Never commit plaintext credentials or secrets in application values. Use the organization's approved secret-management mechanism.

## Add a New Application

### 1. Create a Branch

```bash
git clone https://gitlab.ir/devops/cd/umbrella/helm-generic.git
cd helm-generic
git switch -c add-my-service
```

### 2. Create the Application Values File

Copy a suitable existing configuration:

```bash
cp values/general/requestback.yaml values/general/my-service.yaml
```

Edit `values/general/my-service.yaml`:

- Set `appName: my-service`.
- Replace application-specific image and runtime configuration.
- Review ports, service settings, and routing configuration.
- Review resource requests/limits and health probes.
- Review configuration, secrets, storage, and monitoring requirements.
- Remove copied settings that do not apply to the new application.

Use the chart's actual values keys. Do not retain another application's hostnames, storage claims, or secret references unintentionally.

### 3. Validate

From the repository root:

```bash
# If dependencies are declared and Chart.lock is maintained:
helm dependency build .

helm lint . -f values/general/my-service.yaml

helm template my-service . \
  --namespace general \
  -f values/general/my-service.yaml \
  > /tmp/my-service-rendered.yaml
```

Inspect the output for:

- Expected resource kinds and names
- Correct workload namespace
- Consistent Service selectors and pod labels
- Correct container ports and Service target ports
- Valid route parent references and backend references
- Appropriate image references, probes, and resource settings
- Correct ConfigMap, Secret, and PVC references
- No unexpected resources or copied configuration

Optionally validate against a suitable cluster with its required CRDs installed:

```bash
kubectl --namespace general apply \
  --dry-run=server \
  -f /tmp/my-service-rendered.yaml
```

Use the correct Kubernetes context and an existing validation namespace. Server-side dry-run checks admission behavior but does not prove runtime health.

### 4. Submit the Change

```bash
git add values/general/my-service.yaml
git commit -m "Add my-service deployment values"
git push -u origin add-my-service
```

Open a merge request into `main`. After review and merge, allow time for ApplicationSet and Argo CD reconciliation.

### 5. Verify Deployment

```bash
kubectl -n argocd get application my-service
kubectl -n general get deployments,pods,services
```

With an authenticated Argo CD CLI:

```bash
argocd app get my-service
argocd app wait my-service --sync --health --timeout 300
```

Confirm both `Synced` and `Healthy`, then test the service's expected behavior.

## Update an Existing Application

1. Create a branch.
2. Edit its `values/<group>/<application>.yaml` file.
3. Run linting and rendering with that file.
4. Review the rendered changes.
5. Merge through the normal review process.
6. Monitor Argo CD status and workload health.

Use immutable image tags or digests where supported. Reusing a mutable tag without a manifest change may not trigger a workload rollout.

Manual cluster changes are not a durable update mechanism: `selfHeal: true` can restore the Git-defined state.

## Change Shared Templates or Defaults

Changes to `templates/`, `values.yaml`, or dependencies can affect every Application tracking this chart on `main`.

Before merging:

- Review compatibility with existing application values.
- Render affected application configurations, not only the application motivating the change.
- Check whether new default values unexpectedly enable resources.
- Review resource renames, selector changes, storage changes, and deletions carefully.
- Update `Chart.yaml` version according to the team's chart versioning policy.
- Document new or changed values in `values.yaml` and this README as appropriate.

> For Applications sourcing a chart from Git on `main`, changing a chart version is not the deployment trigger by itself. Changes to the tracked Git revision are what Argo CD reconciles.

## Add an Environment or Application Group

1. Add application values under `values/<group>/`.
2. Use unique `appName` values across environments.
3. Add or update an ApplicationSet in `argocd-apps` to watch that directory.
4. Configure the destination namespace and appropriate workload AppProject there.
5. Validate and review both repositories' changes.

For example, `values/finance-dev/api.yaml` might use `appName: finance-dev-api`, with an ApplicationSet targeting the `finance-dev` namespace.

Creating the directory alone does not deploy its contents.

## Rollback

Prefer reverting the relevant Git change and merging the revert into `main`:

```bash
git switch -c revert-my-service-change
git revert <commit-sha>
git push -u origin revert-my-service-change
```

Argo CD reconciles the reverted desired state after merge. Reverting shared templates may affect multiple applications.

A Git revert does not restore deleted persistent data or reverse database migrations. Handle those through the application's recovery procedure.

## Remove an Application

Removing a values file from the generator's matching path normally causes the ApplicationSet controller to delete its generated Application. Under normal default deletion behavior, its managed Kubernetes resources can also be deleted.

Before removal:

1. Confirm approval and dependencies on the service.
2. Review ApplicationSet deletion policies and Application finalizers.
3. Back up stateful data and check PVC/PV retention behavior.
4. Remove the values file through a reviewed merge request.
5. Verify the intended cleanup.

Renaming `appName` or moving a file outside the generator path can also cause application replacement or removal. Treat these as lifecycle changes, not cosmetic edits.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| No Application is generated | File path and extension, tracked branch, valid YAML, top-level `appName`, duplicate names, ApplicationSet status |
| Values file not found | Generated `spec.source.helm.valueFiles` and chart source path |
| Helm rendering fails | Required values, template conditions, dependency availability, chart schema if present |
| A setting has no effect | Whether any template actually reads that values key |
| Resource kind is unknown | Required CRD installation and supported API version |
| Application is rejected by its project | Source repository, destination namespace, and allowed resource kinds |
| Pods cannot pull images | Image reference, registry connectivity, image pull credentials |
| Pods are not ready | Probes, application logs, configuration, secrets, and resource availability |
| Service has no traffic | Pod readiness, selectors, endpoints, ports, and network policies |
| HTTP/gRPC route does not work | Route status conditions, Gateway attachment, controller support, backend references, DNS/TLS |
| PVC remains pending | Storage class, provisioner, capacity, access modes, and scheduling constraints |
| Autoscaling does not work | HPA status, metric availability, and relevant resource requests |
| Metrics are not scraped | ServiceMonitor selection, namespace selection, Service labels, and metrics endpoint |
| Manual changes disappear | Automated self-healing; make persistent changes in Git |

Useful commands:

```bash
kubectl -n argocd describe applicationset general-apps
kubectl -n argocd get application my-service -o yaml
kubectl -n general get events --sort-by=.metadata.creationTimestamp
kubectl -n general describe pod <pod-name>
kubectl -n general logs <pod-name> --all-containers=true --tail=100
kubectl -n general get service,endpointslices
kubectl -n general get pvc
kubectl -n general get hpa
```

For Gateway API resources, inspect their status if those APIs are installed:

```bash
kubectl -n general get httproutes,grpcroutes
kubectl -n general describe httproute <route-name>
```

## Merge Request Checklist

- [ ] Application values use supported chart keys.
- [ ] `appName` is valid and unique.
- [ ] The intended ApplicationSet watches the values file.
- [ ] Resource names do not conflict with another application.
- [ ] Helm linting and rendering succeed.
- [ ] Required CRDs, controllers, secrets, and storage are available.
- [ ] Image references and runtime configuration are correct.
- [ ] No plaintext credentials are committed.
- [ ] Shared changes are tested against affected applications.
- [ ] Deletion and persistent-data risks are reviewed.
- [ ] Deployment is verified after merge.
