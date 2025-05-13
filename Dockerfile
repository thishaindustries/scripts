# Stage 1: Base image with common dependencies and user setup
FROM ubuntu:noble AS base
ARG SSH_PUBLIC_KEY

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=8 \
    USER_HOME=/home/ubuntu

# Install essential runtime packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    sudo \
    nvtop \
    curl \
    gnupg \
    openssh-server \
    openjdk-21-jdk-headless \
    python3.12 \
    python3-pip \
    tesseract-ocr \
    tesseract-ocr-eng \
    libtesseract-dev \
    libleptonica-dev \
    pkg-config \
    libgl1 \
    libglib2.0-0 \
    libgomp1 \
    supervisor \
    ca-certificates \
    && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create non-root user 'ubuntu', set up sudo for supervisorctl, and configure SSH
RUN (getent passwd ubuntu >/dev/null && userdel -r ubuntu || true) && \
    useradd -ms /bin/bash -u 1001 -G sudo -m -d ${USER_HOME} ubuntu && \
    echo "ubuntu ALL=(ALL) NOPASSWD: /usr/bin/supervisorctl" >> /etc/sudoers && \
    mkdir -p /var/run/sshd /var/log/supervisor && \
    chown root:root /var/log/supervisor && \
    mkdir -p ${USER_HOME}/.ssh && \
    chown ubuntu:ubuntu ${USER_HOME}/.ssh && \
    chmod 700 ${USER_HOME}/.ssh && \
    if [ -n "${SSH_PUBLIC_KEY}" ]; then \
        echo "${SSH_PUBLIC_KEY}" > ${USER_HOME}/.ssh/authorized_keys && \
        chown ubuntu:ubuntu ${USER_HOME}/.ssh/authorized_keys && \
        chmod 600 ${USER_HOME}/.ssh/authorized_keys; \
    else \
        echo "Warning: SSH_PUBLIC_KEY build-arg not provided. SSH key login will not be pre-configured." >&2; \
        touch ${USER_HOME}/.ssh/authorized_keys && \
        chown ubuntu:ubuntu ${USER_HOME}/.ssh/authorized_keys && \
        chmod 600 ${USER_HOME}/.ssh/authorized_keys; \
    fi && \
    sed -i 's/^#?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PubkeyAuthentication .*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/^#?StrictModes .*/StrictModes yes/' /etc/ssh/sshd_config

# Create directories for models and caches, owned by ubuntu user
RUN mkdir -p /opt/models /opt/layoutreader /opt/.cache && \
    chown -R 1001:1001 /opt/models /opt/layoutreader /opt/.cache && \ 
    mkdir -p ${USER_HOME}/.cache/docling/models ${USER_HOME}/logs ${USER_HOME}/hf_tmp_downloads && \
    chown -R 1001:1001 ${USER_HOME}/.cache ${USER_HOME}/logs ${USER_HOME}/hf_tmp_downloads

# Stage 2: Builder for Python dependencies
FROM base AS builder
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git \
    python3.12-venv \
    build-essential \
    && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

USER ubuntu
WORKDIR ${USER_HOME}
RUN git clone https://github.com/thishaindustries/scripts.git ${USER_HOME}/scripts

USER root
RUN if [ -f "${USER_HOME}/scripts/nvidia-settings.sh" ]; then \
        echo "Making nvidia-settings.sh executable and running as root..." && \
        chmod +x ${USER_HOME}/scripts/nvidia-settings.sh && \
        bash ${USER_HOME}/scripts/nvidia-settings.sh || \
        { echo "ERROR: nvidia-settings.sh failed during build. Check script and GPU environment."; exit 1; }; \
    else \
        echo "Warning: nvidia-settings.sh not found at ${USER_HOME}/scripts/nvidia-settings.sh. Skipping execution." >&2; \
    fi

USER ubuntu
WORKDIR ${USER_HOME}
RUN python3 -m venv ${USER_HOME}/venv
ENV PATH="${USER_HOME}/venv/bin:$PATH"

COPY --chown=ubuntu:ubuntu requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt

# Stage 3: Model Downloader
FROM builder AS model_downloader
ENV HF_HOME=${USER_HOME}/.cache/huggingface \
    HUGGINGFACE_HUB_TMP_DIR=${USER_HOME}/hf_tmp_downloads \
    MINERU_MODELS_DIR_BASE=/opt \
    MINERU_MODELS_DIR=/opt/models \
    MINERU_LAYOUTREADER_MODEL_DIR=/opt/layoutreader \
    DOCLING_SERVE_ARTIFACTS_PATH=${USER_HOME}/.cache/docling/models

COPY --chown=ubuntu:ubuntu mineru_download_models.py .
RUN chmod +x mineru_download_models.py && \
    echo "Downloading Mineru models..." && \
    python ./mineru_download_models.py

RUN echo "Downloading Docling models to ${DOCLING_SERVE_ARTIFACTS_PATH}..." && \
    docling-tools models download -o "${DOCLING_SERVE_ARTIFACTS_PATH}"

# Stage 4: Final runtime image
FROM base AS final
ENV PATH="${USER_HOME}/venv/bin:$PATH" \
    HF_HOME=${USER_HOME}/.cache/huggingface \
    HUGGINGFACE_HUB_TMP_DIR=${USER_HOME}/hf_tmp_downloads \
    MINERU_MODELS_DIR_BASE=/opt \
    MINERU_MODELS_DIR=/opt/models \
    MINERU_LAYOUTREADER_MODEL_DIR=/opt/layoutreader \
    DOCLING_SERVE_ARTIFACTS_PATH=${USER_HOME}/.cache/docling/models \
    DOCLING_SERVE_MAX_SYNC_WAIT=300 \
    DOCLING_SERVE_ENG_LOC_NUM_WORKERS=16

USER ubuntu
WORKDIR ${USER_HOME}

COPY --chown=ubuntu:ubuntu --from=builder ${USER_HOME}/venv ${USER_HOME}/venv
COPY --chown=ubuntu:ubuntu --from=builder ${USER_HOME}/scripts ${USER_HOME}/scripts

COPY --chown=ubuntu:ubuntu --from=model_downloader ${MINERU_MODELS_DIR} ${MINERU_MODELS_DIR}
COPY --chown=ubuntu:ubuntu --from=model_downloader ${MINERU_LAYOUTREADER_MODEL_DIR} ${MINERU_LAYOUTREADER_MODEL_DIR}
COPY --chown=ubuntu:ubuntu --from=model_downloader ${DOCLING_SERVE_ARTIFACTS_PATH} ${DOCLING_SERVE_ARTIFACTS_PATH}

COPY --chown=ubuntu:ubuntu mineru_app.py .
COPY --chown=ubuntu:ubuntu magic-pdf.json .

RUN echo '\n# Custom environment variables and venv activation for interactive shells' >> ${USER_HOME}/.bashrc && \
    echo 'TESS_PREFIX_PATH_BASHRC=$(dpkg -L tesseract-ocr-eng | grep "tessdata$" | head -n 1 || true); if [ -n "$TESS_PREFIX_PATH_BASHRC" ]; then export TESSDATA_PREFIX="${TESS_PREFIX_PATH_BASHRC}/"; else export TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata/; fi' >> ${USER_HOME}/.bashrc && \
    echo "export DOCLING_SERVE_MAX_SYNC_WAIT=${DOCLING_SERVE_MAX_SYNC_WAIT}" >> ${USER_HOME}/.bashrc && \
    echo "export DOCLING_SERVE_ENG_LOC_NUM_WORKERS=${DOCLING_SERVE_ENG_LOC_NUM_WORKERS}" >> ${USER_HOME}/.bashrc && \
    echo "export DOCLING_SERVE_ARTIFACTS_PATH=${DOCLING_SERVE_ARTIFACTS_PATH}" >> ${USER_HOME}/.bashrc && \
    echo "export MINERU_MODELS_DIR=${MINERU_MODELS_DIR}" >> ${USER_HOME}/.bashrc && \
    echo "export MINERU_LAYOUTREADER_MODEL_DIR=${MINERU_LAYOUTREADER_MODEL_DIR}" >> ${USER_HOME}/.bashrc && \
    echo 'export PATH="/home/ubuntu/venv/bin:$PATH"' >> ${USER_HOME}/.bashrc && \
    echo 'if [ -f "/home/ubuntu/venv/bin/activate" ]; then source /home/ubuntu/venv/bin/activate; else echo "Venv not found for .bashrc activation"; fi' >> ${USER_HOME}/.bashrc

USER root
COPY --chown=root:root supervisord_app.conf /etc/supervisor/conf.d/supervisord_app.conf
COPY --chown=ubuntu:ubuntu entrypoint.sh ${USER_HOME}/entrypoint.sh
COPY --chown=ubuntu:ubuntu control_api.sh /usr/local/bin/control_api.sh
RUN chmod +x ${USER_HOME}/entrypoint.sh /usr/local/bin/control_api.sh

EXPOSE 22 8000 9000

ENTRYPOINT ["/home/ubuntu/entrypoint.sh"]
CMD ["echo", "Container starting with supervisord. Java CommandServer and SSHD will start by default."]
