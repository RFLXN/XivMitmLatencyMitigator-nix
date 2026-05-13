FROM python:3.13-slim

ARG XIVMITM_REPO=https://github.com/Soreepeong/XivMitmLatencyMitigator.git
ARG XIVMITM_REV=2ddfb8c3310782dbb7baaecdab17fc9c89ccce90

ENV PYTHONUNBUFFERED=1

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates git \
  && rm -rf /var/lib/apt/lists/*

RUN git clone "${XIVMITM_REPO}" /opt/xivmitm \
  && cd /opt/xivmitm \
  && git checkout "${XIVMITM_REV}"

WORKDIR /data

ENTRYPOINT ["python", "/opt/xivmitm/src/__main__.py"]

