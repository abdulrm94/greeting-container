FROM python:3.12-slim@sha256:a6e34c598f2467ed0e9a8d349809fcd8b5c603269512df273a0bb1784edc11b1

WORKDIR /app

# Install dependencies first so this layer is cached when only the code changes
COPY app/requirements.txt app/requirements.txt

# Don't keep pip's download cache in the image (hadolint DL3042, KICS "Pip install keeping cached packages")
RUN pip install --no-cache-dir -r app/requirements.txt

COPY app/ app/

EXPOSE 8080

# The app is copied to /app/app, so gunicorn starts from there.
CMD ["gunicorn", "--chdir", "app", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
