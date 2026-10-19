# Public repo goldens

`TestPublicRepos` in `internal/kinds` checks two lists per repo against the `.rows` files here: the zero-config default set (`dir` and `project`) and the recipe the repo exercises. Run `testdata/fetch-repos.sh` first; a repo that isn't at its pinned commit in `testdata/repos.lock` is skipped. `go test ./internal/kinds -run TestPublicRepos -update-public` rewrites the goldens, so read the diff before committing one.

## Row counts

| Repo | Commit | default | Recipe | Rows |
|---|---|---|---|---|
| GoogleCloudPlatform/microservices-demo | 38e7348eb289 | 24 (12 dir, 12 project) | `project` | 12, one per service under `src/` |
| gruntwork-io/terragrunt-infrastructure-live-example | d106b47ad1e2 | 5 (5 dir, 0 project) | `tg` | 6, two units in each of qa, stage and prod |
| prometheus-community/helm-charts | 70e7805d8592 | 6 (6 dir, 0 project) | `helm` | 46 charts, two of them `crds` subcharts |

## What the project tuning rejects

Counts are `project` rows before and after each lever. The private repo is a 12k-file infrastructure monorepo, measured for noise and not checked in.

| Lever | microservices-demo | this repo | private monorepo | Rejected |
|---|---|---|---|---|
| none: the 16 markers alone | 13 | 1 | 60 | |
| `min_depth = 1` | 13 | 0 | 59 | the repo root, from a root `go.mod` or `Makefile` |
| `nested = false` | 13 | 0 | 54 | build, tools and test dirs inside a project, each with its own Makefile or Dockerfile |
| `*.sln` added | 12 | 0 | 54 | `src/cartservice/src` and `src/cartservice/tests` become one `cartservice` row, from `cartservice.sln` |
| the `exclude` list | 12 | 0 | 54 | nothing in these repos; it keeps vendored and fixture manifests out elsewhere |

Kept on purpose:

- `Dockerfile`: dropping it loses 4 of microservices-demo's 12 services (the Python ones with only `requirements.txt`) and 49 of the monorepo's 54 rows, every one a service dir.
- `Makefile`: 13 of the monorepo's rows have only a Makefile, and each is a service, function, tool or module dir, not a build output.
- `requirements.txt` stays out: it also turns up in docs and script dirs, such as helm-charts' `charts/kube-prometheus-stack/hack`.

## Known gaps

- The kind column is 5 characters wide, as in zsh hop 0.3.1, so `project` shows as `proj…`. Widening it would move existing configs' rows.
- A project at the top level, such as `api/`, has the scope `.`, as every no-layout kind has in 0.3.1.
- `terraform-modules` doesn't skip a dir that also holds `terragrunt.hcl`. None of these repos needs it; an `unless` marker option would.
