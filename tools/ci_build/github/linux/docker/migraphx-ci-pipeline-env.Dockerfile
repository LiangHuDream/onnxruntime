# Refer to https://github.com/RadeonOpenCompute/ROCm-docker/blob/master/dev/Dockerfile-ubuntu-22.04-complete
FROM ubuntu:22.04

ARG ROCM_VERSION=6.4
ARG AMDGPU_VERSION=${ROCM_VERSION}
ARG APT_PREF='Package: *\nPin: release o=repo.radeon.com\nPin-Priority: 600'

CMD ["/bin/bash"]

RUN echo "$APT_PREF" > /etc/apt/preferences.d/rocm-pin-600

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates git unzip zip curl libnuma-dev gnupg && \
    curl -sL https://repo.radeon.com/rocm/rocm.gpg.key | apt-key add -   &&\
    printf "deb [arch=amd64] https://repo.radeon.com/rocm/apt/$ROCM_VERSION/ jammy main" | tee /etc/apt/sources.list.d/rocm.list   && \
    printf "deb [arch=amd64] https://repo.radeon.com/amdgpu/$AMDGPU_VERSION/ubuntu jammy main" | tee /etc/apt/sources.list.d/amdgpu.list   && \
    apt-get update && apt-get install -y --no-install-recommends  \
    sudo   \
    libelf1   \
    kmod   \
    file   \
    python3   \
    python3-pip   \
    rocm-dev   \
    rocm-libs   \
    build-essential pkg-config && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Upgrade to meet security requirements
RUN apt-get update -y && apt-get upgrade -y && apt-get autoremove -y && \
    apt-get install  -y locales cifs-utils wget half libnuma-dev lsb-release && \
    apt-get clean -y

# Cmake
ENV CMAKE_VERSION=3.31.5
RUN cd /usr/local && \
    wget -q https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz && \
    tar -zxf /usr/local/cmake-3.31.5-Linux-x86_64.tar.gz --strip=1 -C /usr

# Install Ninja
COPY scripts/install-ninja.sh /build_scripts/
RUN /bin/bash /build_scripts/install-ninja.sh

# Install VCPKG
ENV VCPKG_INSTALLATION_ROOT=/usr/local/share/vcpkg
ENV VCPKG_FORCE_SYSTEM_BINARIES=ON
COPY scripts/install-vcpkg.sh /build_scripts/
RUN /bin/bash /build_scripts/install-vcpkg.sh

RUN groupadd -g 109 render


ENV MIGRAPHX_DISABLE_FAST_GELU=1
RUN locale-gen en_US.UTF-8
RUN update-locale LANG=en_US.UTF-8
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8

WORKDIR /stage


# ccache
RUN mkdir -p /tmp/ccache && \
    cd /tmp/ccache && \
    wget -q -O - https://github.com/ccache/ccache/releases/download/v4.7.4/ccache-4.7.4-linux-x86_64.tar.xz | tar --strip 1 -J -xf - && \
    cp /tmp/ccache/ccache /usr/bin && \
    rm -rf /tmp/ccache

# Install Conda
ENV PATH /opt/miniconda/bin:${PATH}
RUN wget --quiet https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O ~/miniconda.sh --no-check-certificate && /bin/bash ~/miniconda.sh -b -p /opt/miniconda && \
    conda init bash && \
    conda config --set auto_activate_base false && \
    conda update --all && \
    rm ~/miniconda.sh && conda clean -ya

# Create migraphx-ci environment
ENV CONDA_ENVIRONMENT_PATH /opt/miniconda/envs/migraphx-ci
ENV CONDA_DEFAULT_ENV migraphx-ci
RUN conda create -y -n ${CONDA_DEFAULT_ENV} python=3.10
ENV PATH ${CONDA_ENVIRONMENT_PATH}/bin:${PATH}

# Enable migraphx-ci environment
SHELL ["conda", "run", "-n", "migraphx-ci", "/bin/bash", "-c"]

# ln -sf is needed to make sure that version `GLIBCXX_3.4.30' is found
RUN ln -sf /usr/lib/x86_64-linux-gnu/libstdc++.so.6 ${CONDA_ENVIRONMENT_PATH}/bin/../lib/libstdc++.so.6

# Install migraphx
RUN apt update && apt install -y migraphx

RUN pip install numpy packaging ml_dtypes==0.5.0
ARG BUILD_UID=1000
ARG BUILD_USER=onnxruntimedev
RUN adduser --gecos 'onnxruntime Build User' --disabled-password $BUILD_USER --uid $BUILD_UID
USER $BUILD_USER
WORKDIR /home/$BUILD_USER
