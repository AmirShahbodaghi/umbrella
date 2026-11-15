# Argo CD Applications

GitOps configuration repository for managing Kubernetes application deployments with Argo CD ApplicationSets and the shared `helm-generic` chart.

This repository defines **which applications are deployed, which project governs them, and where they are deployed**. Helm templates and application-specific values are maintained separately in `helm-generic`.

## Repositories

| Repository | Responsibility |
| --- | --- |
| `https://gitlab.ir/devops/cd/umbrella/argocd-apps.git` | ApplicationSets, AppProjects, and deployment orchestration |
| `https://gitlab.ir/devops/cd/umbrella/helm-generic.git` | Shared Helm templates and per-application values |

The supplied configuration tracks the `main` branch in both repositories.

## Repository Structure

```text
argocd-apps/
├── README.md
├── appsets/
│   ├── general.yaml
└── projects/
    └── platform-admin-project.yaml
```

A root Argo CD Application named `root-app` watches this repository. Its bootstrap manifest, referred to below as `rootapp.yml`, may be maintained separately; it is not shown in the repository layout above.

| Directory | Purpose |
| --- | --- |
| `appsets/` | ApplicationSet definitions for application groups or environments |
| `projects/` | AppProject definitions controlling permitted sources, destinations, and resource kinds |

> Filenames identify the intended groups. Inspect each ApplicationSet for its actual generator, repository, destination, and project. Only the supplied `general.yaml` configuration is detailed in this guide; the contents of the other ApplicationSets have not been provided.

## Architecture

```text
root-app (Argo CD Application in argocd)
    |
    | Reads argocd-apps / appsets/*.yaml
    v
ApplicationSets
    |
    | Discover application configuration in Git
    v
Generated Argo CD Applications
    |
    | Render helm-generic with application values
    v
Kubernetes workloads in the configured destination namespaces
```

### Resource Responsibilities

- **Root Application:** synchronizes ApplicationSet manifests from this repository.
- **ApplicationSet:** discovers inputs and creates or updates child Applications.
- **Child Application:** defines the chart source, values file, destination, project, and sync policy for a workload.
- **AppProject:** controls permitted repositories, destinations, and resource kinds for Applications assigned to it.
- **Helm chart:** renders Kubernetes manifests from shared templates and application values.

All Application, ApplicationSet, and AppProject resources described here live in the `argocd` namespace. Workloads are deployed to the destination namespace configured in each child Application.

## Important Configuration Review

The original supplied manifests need the following review before using the administrative project as intended:

| Original setting | Implication / recommendation |
| --- | --- |
| `root-app.spec.project: default` | The root application is governed by `default`, not `platform-admin`. Assign it to `platform-admin` if that isolation is intended. |
| `platform-admin.sourceRepos` points to `devops/cd/test/general/argocd-apps.git` | This does not match the actual `devops/cd/umbrella/argocd-apps.git` source. Correct the allowed URL. |
| AppProject and ApplicationSet are listed as cluster-scoped resources | Both are namespaced resources; place them in `namespaceResourceWhitelist`. |
| Root source includes only `appsets/*.yaml` | Files under `projects/` are not synchronized by the root application. Bootstrap and update them separately. |
| Generated Applications use `project: default` | The root application's project is not inherited by child Applications. Configure workload projects explicitly when isolation is required. |

The examples below use a corrected administrative project for the root application while retaining `default` for general workloads to match the supplied ApplicationSet.

## Root Application

Apply the root Application once as part of bootstrap:

```yaml
# rootapp.yml — bootstrap manifest
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: platform-admin
  source:
    repoURL: https://gitlab.ir/devops/cd/umbrella/argocd-apps.git
    targetRevision: main
    path: .
    directory:
      recurse: true
      include: "appsets/*.yaml"
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

### Behavior

- `directory.recurse` enables traversal of subdirectories.
- `directory.include` restricts the manifests selected for synchronization to `appsets/*.yaml`.
- `prune: true` allows removal of previously managed resources absent from desired state, subject to Argo CD safety settings.
- `selfHeal: true` reconciles manual changes back to the Git-defined configuration.
- `CreateNamespace=true` requests creation of the destination namespace when needed and permitted. Argo CD must already be installed before bootstrap.
- The resource finalizer enables cascading deletion of the root application's managed resources.

Neither `projects/` nor the root bootstrap manifest is managed by this source filter. Committing a change to those files alone does not apply it to the cluster.

## Administrative AppProject

Recommended corrected `projects/platform-admin-project.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: platform-admin
  namespace: argocd
spec:
  description: "Administrative project for GitOps bootstrap resources"
  sourceRepos:
    - "https://gitlab.ir/devops/cd/umbrella/argocd-apps.git"
  destinations:
    - namespace: argocd
      server: https://kubernetes.default.svc
  clusterResourceWhitelist: []
  namespaceResourceWhitelist:
    - group: argoproj.io
      kind: AppProject
    - group: argoproj.io
      kind: ApplicationSet
    - group: argoproj.io
      kind: Application
```

AppProject, ApplicationSet, and Application are namespaced resources. This project permits the listed kinds in the permitted destination and does not allow cluster-scoped resources.

For the current root filter, only ApplicationSet is required. Remove the other permissions if they are not needed for your administrative workflow.

> **Security:** Permission to deploy into `argocd`, especially permission to manage AppProjects or ApplicationSets, is administrative access. Protect this repository and require trusted reviews. This project must not be treated as a security boundary for untrusted contributors.

AppProject permissions do not grant Kubernetes permissions to controllers. Argo CD's Kubernetes RBAC must also allow the required operations.

## General ApplicationSet

`appsets/general.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: general-apps
  namespace: argocd
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

### How Discovery Works

For every matching file in `helm-generic/values/general/`:

1. The Git files generator reads the file.
2. Its top-level `appName` supplies the Argo CD Application name.
3. The generator's path parameters select that same file as a Helm values override.
4. Argo CD renders the chart at repository root.
5. The resulting resources are deployed to `general`.

For example:

```yaml
# In helm-generic: values/general/payeshnotify.yaml
appName: payeshnotify
# Remaining fields must follow the actual Helm chart schema.
```

| Generated setting | Value |
| --- | --- |
| Application name | `payeshnotify` |
| Application namespace | `argocd` |
| Helm source path | `.` |
| Helm values file | `values/general/payeshnotify.yaml` |
| Workload namespace | `general` |
| Workload project | `default` |

Application names must be valid Kubernetes resource names and unique among Applications in `argocd`. Resource names rendered by Helm must also avoid collisions between Applications deploying to the same namespace.

Only `.yaml` files matching the configured glob are discovered. Creating another values folder or using `.yml` does not make it part of this generator.

### Template Syntax

The supplied ApplicationSet uses legacy templating syntax. If migrating to `goTemplate: true`, update the expressions:

| Legacy expression | Go-template expression |
| --- | --- |
| `{{appName}}` | `{{ .appName }}` |
| `{{path}}/{{path.filename}}` | `{{ .path.path }}/{{ .path.filename }}` |

Do not enable Go templates without migrating and validating the template.

## Prerequisites

Before bootstrap, confirm:

- Kubernetes is available and the intended context is selected.
- Argo CD, its CRDs, and the ApplicationSet controller are installed.
- Argo CD can authenticate to both private Git repositories.
- Repository TLS certificates are trusted by Argo CD.
- Argo CD's controllers have the required Kubernetes permissions.
- Workload projects permit their source repositories, destinations, and resource kinds.
- Namespace creation is permitted where `CreateNamespace=true` is used, or namespaces are provisioned separately.
- Workload prerequisites such as registry credentials, secrets, CRDs, storage, and routing controllers are available.

Keep repository credentials and plaintext secrets out of Git. Configure them through the approved secret-management and Argo CD repository-access process.

## Bootstrap

### 1. Clone the Repository

```bash
git clone https://gitlab.ir/devops/cd/umbrella/argocd-apps.git
cd argocd-apps
kubectl config current-context
```

### 2. Create the Administrative Project

```bash
kubectl apply -f projects/platform-admin-project.yaml
```

Use the corrected project definition if assigning `root-app` to `platform-admin`.

### 3. Apply the Root Application

Save the root manifest above as `rootapp.yml` in your approved bootstrap location, then run:

```bash
kubectl apply -f /path/to/rootapp.yml
```

The root application should synchronize the ApplicationSets. The ApplicationSet controller then generates the child Applications.

### 4. Verify

```bash
kubectl -n argocd get appprojects
kubectl -n argocd get applicationsets
kubectl -n argocd get applications
```

With an authenticated Argo CD CLI:

```bash
argocd app get root-app
argocd app get payeshnotify
argocd app wait payeshnotify --sync --health --timeout 300
```

Reconciliation is asynchronous. A successful Git merge does not mean the workloads are already deployed or healthy.

## Day-to-Day Workflow

### Add an Application to an Existing Group

If an ApplicationSet already watches the intended values folder:

1. Create a values file in `helm-generic`, such as `values/general/my-service.yaml`.
2. Set a unique `appName` and valid chart configuration.
3. Run Helm linting and rendering in `helm-generic`.
4. Merge the reviewed change into its tracked branch.
5. Verify the generated Application and workload health.

No change to `argocd-apps` is normally needed when the file matches an existing generator.

### Add an Environment or Application Group

1. Create or select the values directory in `helm-generic`.
2. Copy an appropriate ApplicationSet in this repository.
3. Update the following fields:

| Field | Example for a new group |
| --- | --- |
| Manifest filename | `appsets/example-dev.yaml` |
| `metadata.name` | `example-dev-apps` |
| Generator file path | `values/example-dev/*.yaml` |
| Destination namespace | `example-dev` |
| Child Application project | An approved workload project |

4. Bootstrap any new workload AppProject before referring to it.
5. Ensure application names are unique; use names such as `example-dev-api`.
6. Validate and merge the changes in both repositories.
7. Verify the ApplicationSet and generated Applications.

Do not infer a destination from a filename alone; check the manifest. Avoid having two ApplicationSets generate the same Application or two Applications manage the same Kubernetes resource.

### Update an ApplicationSet

Create a branch, edit the relevant manifest, validate, and open a merge request. After merge, `root-app` synchronizes it.

Changes to generator paths, naming templates, projects, or destinations can affect every generated Application. Review creation, replacement, and deletion implications before merging.

### Update Projects or Bootstrap Configuration

Under the current root source filter, apply project changes separately:

```bash
kubectl apply -f projects/platform-admin-project.yaml
```

Apply root manifest changes through the approved bootstrap process as well.

If moving project management into GitOps later, use a deliberate design that ensures workload projects exist before dependent Applications and avoids unsafe management of the root application's own permissions. Merely adding files under `projects/` does not activate them.

## Validation Before Merge

From this repository, use server-side dry-run against an appropriate cluster with Argo CD CRDs installed:

```bash
kubectl apply --dry-run=server -f projects/platform-admin-project.yaml
kubectl apply --dry-run=server -f appsets/
```

This checks API acceptance and admission behavior. It does not prove that generators can access Git, that child Applications will be valid, or that workloads will become healthy.

For application configuration, validate in the `helm-generic` checkout:

```bash
helm lint . -f values/general/my-service.yaml
helm template my-service . \
  --namespace general \
  -f values/general/my-service.yaml
```

Build dependencies first if required by the chart. Validate all affected application configurations when changing shared templates or defaults.

## Sync, Rollback, and Deletion

### Automated Sync

The supplied root and child Applications enable:

- **Automated synchronization:** reconcile tracked Git changes.
- **Pruning:** remove resources no longer in desired state, subject to safety settings.
- **Self-healing:** correct drift from Git's desired state.

Persistent changes should be made in Git, not by editing generated Applications or live workloads.

### Rollback

Prefer reverting the relevant commit in the repository that owns the change:

- Revert `argocd-apps` for ApplicationSet configuration changes.
- Revert `helm-generic` for chart or application values changes.
- Reapply bootstrap files explicitly when reverting manually managed project or root configuration.

Use a reviewed merge request for the revert. A manifest rollback does not restore deleted data or undo database migrations.

### Deletion Risks

Under normal default controller behavior:

- Removing a matching values file can delete the generated Application and its workloads.
- Removing an ApplicationSet from this repository can cause root pruning and cascading deletion of child Applications and their workloads.
- Deleting `root-app` with its resource finalizer can cascade into managed ApplicationSets and downstream resources.
- Changing `appName` can replace an Application rather than rename it in place.

ApplicationSet controller policies, resource-preservation settings, finalizers, and Argo CD empty-application safeguards can change the exact outcome. Inspect the live configuration before deletion; do not assume removal is harmless or immediate.

Before deleting or renaming anything, review the affected resources, obtain approval, and verify backups and persistent-volume retention settings. Do not delete a values file as a way to pause a deployment.

## Troubleshooting

| Symptom | Checks |
| --- | --- |
| Root application cannot sync | Repository access, project existence, allowed source URL, destination, resource whitelist |
| ApplicationSet is missing | File is under `appsets/`, ends in `.yaml`, and is included by the root filter |
| Project changes have no effect | `projects/` is excluded from the root source; apply through the bootstrap process |
| Child Application is missing | Generator path, branch, Git access, YAML content, `appName`, duplicate names, ApplicationSet status |
| Values file cannot be found | Generated Helm values path is correct relative to the chart source path |
| Repository or destination is denied | Check the affected child Application's project, not only the root project |
| Namespace creation fails | Workload project permissions and controller Kubernetes RBAC |
| Helm rendering fails | Chart dependencies, values schema, required settings, template errors |
| Synced but unhealthy | Workload logs/events, image pulls, probes, secrets, storage, and external dependencies |
| Manual configuration is reverted | Git reconciliation or ApplicationSet reconciliation is restoring desired state |
| New values folder has no effect | No ApplicationSet watches that path |

Useful commands:

```bash
kubectl -n argocd describe application root-app
kubectl -n argocd describe applicationset general-apps
kubectl -n argocd get application payeshnotify -o yaml
kubectl -n argocd get pods
kubectl -n general get deployments,pods,services
kubectl -n general get events --sort-by=.metadata.creationTimestamp
kubectl -n general describe pod <pod-name>
kubectl -n general logs <pod-name> --all-containers=true --tail=100
```

For generator problems, locate the ApplicationSet controller pod in `argocd` and inspect its logs. Controller names and labels depend on the Argo CD installation.

## Security and Operational Guidelines

- Protect `main` and require reviewed merge requests.
- Restrict changes to projects, generators, destinations, and templated project fields to trusted administrators.
- Prefer dedicated workload AppProjects over `default` for environment isolation.
- Treat deployment permissions into `argocd` as administrative access.
- Store credentials outside Git using the approved secret-management process.
- Use unique application names and unambiguous resource ownership.
- Validate shared chart changes against affected applications before merge.
- Monitor both sync status and runtime health.
- Maintain tested backup and recovery procedures for stateful workloads.

## Merge Request Checklist

- [ ] ApplicationSet name is unique.
- [ ] Generator repository, branch, and file pattern are correct.
- [ ] Generated Application names are valid and unique.
- [ ] Workload project exists and permits the required source, destination, and resources.
- [ ] Destination cluster and namespace are correct.
- [ ] Helm chart and values paths are valid.
- [ ] No credentials or plaintext secrets are committed.
- [ ] Replacement, pruning, and cascading-deletion risks are reviewed.
- [ ] Manifest and chart validation are complete.
- [ ] Required bootstrap changes have a separate application plan.
- [ ] Argo CD sync and workload health are verified after merge.
