# DevOps Interview Task (Part 1): Containerize

**This is a take-home task.** Please submit by the date given when the task was
issued.

## Overview

You are given a small web application (`app/`). A working `Dockerfile` is
provided, but it was written quickly and does **not** follow container best
practices. Your job is to refactor it into a production-quality image and push
it to a container registry.

You do **not** need to modify the application code.

## What we provide

Clone this repository into your local account.

> **Do Not** fork this repository. Clone it and re-push it into your local account.

The following is provided as part of this repository:

```text
Dockerfile            # a working but non-production Dockerfile — improve it
app/
  app.py              # a minimal Python Flask web app (do not modify)
  requirements.txt    # the app's dependencies (do not modify)
```

The application:

-   Listens on the port given by the `PORT` environment variable (default `8080`).
-   Reads a `GREETING` environment variable used in its response.
-   Exposes `GET /`, `GET /healthz`, and `GET /info`.

## My solution

### Results

| Measure                               | Original                     | Now                                   |
| ------------------------------------- | ---------------------------- | ------------------------------------- |
| Image size                            | 1.73 GB                      | 205 MB                                |
| HIGH/CRITICAL vulnerabilities (Trivy) | 413                          | 44, none with a fix available         |
| hadolint warnings                     | 4                            | 0                                     |
| KICS findings                         | 9 (1 HIGH)                   | 0                                     |
| Runs as                               | root                         | non-root user (UID 10001)             |
| Files copied into the image           | whole repo, including `.git` | `app/` only                           |
| Health check                          | none                         | yes, on `/healthz`                    |
| Port and workers                      | hard-coded in `CMD`          | `PORT` and `WEB_CONCURRENCY` settings |

### Running it

Build and run the image:

```bash
docker build -t sample-app:dev .
docker run --rm -p 8080:8080 -e GREETING="Hello from Docker" sample-app:dev
```

Then visit <http://localhost:8080/>, `/healthz` or `/info`.

The port and number of gunicorn workers can be changed without rebuilding:

```bash
docker run --rm -p 8080:9000 -e PORT=9000 -e WEB_CONCURRENCY=4 sample-app:dev
```

### What changed in the Dockerfile

Each change was made in its own commit, so the history shows the effect of each one.

| Change                                          | Why                                                                                                                                                   |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.dockerignore` (allow `app/` only)             | Stops `.git` and other repo files ending up in the image. New files are blocked by default.                                                           |
| Removed `gcc`, `build-essential`, `curl`, `vim` | The app doesn't use them. Each extra package adds vulnerabilities and tools an attacker could use.                                                    |
| `python:3.12-slim` base image, pinned by digest | The full image is built for development and carried most of the vulnerabilities. The digest makes every build use exactly the same base.              |
| Install dependencies before copying the code    | Docker caches the install step, so a code change doesn't reinstall every package.                                                                     |
| `pip install --no-cache-dir`                    | Pip's download cache isn't needed inside an image (hadolint DL3042).                                                                                  |
| Multi-stage build with a virtual environment    | Packages are installed in a build stage and only the virtual environment is copied into the final image.                                              |
| Non-root user (`USER 10001`)                    | Limits what an attacker could do if they got in. A numeric UID lets Kubernetes check the container isn't root. App files stay read-only to this user. |
| OCI labels                                      | Records where the image came from. The `source` label links the package to this repository on GHCR.                                                   |
| `PYTHONUNBUFFERED=1`                            | Logs appear straight away and aren't lost if the app crashes.                                                                                         |
| `PORT` and `WEB_CONCURRENCY` settings           | Gunicorn reads these itself, so the port and number of workers can be changed without a rebuild, and the app and gunicorn agree on the port.          |
| `HEALTHCHECK` using Python                      | Docker can tell if the app stops responding. It uses Python because `curl` was removed.                                                               |

### Checks

The same checks run locally and in CI. They are defined once in `Taskfile.yml` ([Task](https://taskfile.dev)) and use pinned scanner versions.

| Tool                                             | What it checks                                         | Fails the build when                                 |
| ------------------------------------------------ | ------------------------------------------------------ | ---------------------------------------------------- |
| [hadolint](https://github.com/hadolint/hadolint) | Dockerfile best practice                               | any warning                                          |
| [KICS](https://docs.kics.io)                     | Dockerfile security issues                             | any finding                                          |
| Smoke test (`curl`)                              | The app starts and `/healthz`, `/` and `/info` respond | any request fails                                    |
| [Trivy](https://trivy.dev)                       | Known vulnerabilities in the image                     | a HIGH or CRITICAL vulnerability has a fix available |

| Command      | What it does                                                      |
| ------------ | ----------------------------------------------------------------- |
| `task lint`  | Runs hadolint and KICS on the Dockerfile                          |
| `task build` | Builds the image as `sample-app:dev`                              |
| `task test`  | Builds, starts the container, checks the endpoints, then stops it |
| `task scan`  | Scans the image with Trivy                                        |
| `task ci`    | Runs all of the above, the same as the pipeline                   |

The checks started in report-only mode to record the baseline, then were made strict once the Dockerfile was fixed.

### CI

GitHub Actions (`.github/workflows/ci.yml`) runs `task lint`, `task test` and `task scan` on every push.

-   The workflow token is read-only by default.
-   Actions are pinned to commit SHAs rather than tags, so the code they run can't change underneath the pipeline.
-   Dependabot (`.github/dependabot.yml`) checks weekly for new versions of the actions and the base image.

### Publishing

The image is published to the GitHub Container Registry as `ghcr.io/abdulrm94/sample-app`.

```bash
docker pull ghcr.io/abdulrm94/sample-app:v1
docker run --rm -p 8080:8080 ghcr.io/abdulrm94/sample-app:v1
```

Publishing is done by the `publish` job in the CI workflow, not by hand:

1.  It only runs when a version tag such as `v1` is pushed, and only if the checks pass.
2.  It waits for manual approval in the `production` environment. Only tags matching `v*` can use the environment, and administrators can't bypass the approval.
3.  It logs in with the workflow's temporary `GITHUB_TOKEN`, so no personal access token is stored.
4.  It pushes the image tagged with the version (`v1`) and the commit (`sha-...`). It never pushes `latest`.

### Remaining vulnerabilities

Trivy reports 44 HIGH/CRITICAL vulnerabilities in the base image's operating system packages. None of them has a fix available yet. The scan fails the build on HIGH/CRITICAL vulnerabilities **with** a fix, so when Debian releases one, Dependabot's base image update must be applied for the build to pass.

The Python packages (Flask, gunicorn and their dependencies) have no known vulnerabilities.

### What I'd add next

-   Show Trivy results in GitHub's Security tab (SARIF upload).
-   Sign the image and attach an SBOM.
-   Consider a distroless base image to reduce the remaining operating system vulnerabilities.
-   Kubernetes liveness and readiness probes on `/healthz` (Part 2).
