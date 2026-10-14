# Build stage: install dependencies into a virtual environment
FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1 AS builder

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY app/requirements.txt /tmp/requirements.txt
# Don't keep pip's download cache in the image (hadolint DL3042)
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# Final stage: only the installed packages and the app
FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1

# Run as a non-root user (KICS "Missing User Instruction")
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --no-log-init --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY app/ app/

USER 10001

EXPOSE 8080

# The app is copied to /app/app, so gunicorn starts from there.
CMD ["gunicorn", "--chdir", "app", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
