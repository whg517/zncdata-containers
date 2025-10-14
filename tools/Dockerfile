# syntax=docker/dockerfile:1.17.1@sha256:38387523653efa0039f8e1c89bb74a30504e76ee9f565e25c9a09841f9427b05
# check=error=true

## stage: builder
FROM zncdatadev/image/kubedoop-base AS tools-builder

ARG GETTEXT_VERSION=0.22.5

RUN <<EOF
    microdnf update
    microdnf install \
        gcc \
        make \
        tar \
        xz
    microdnf clean all
    rm -rf /var/cache/yum
EOF

WORKDIR /build

# Build envsubst from gettext source if not available in package
RUN <<EOF
    set -ex
    
    # Download gettext source
    curl -sSfL \
        https://ftp.gnu.org/pub/gnu/gettext/gettext-${GETTEXT_VERSION}.tar.xz \
        -o gettext.tar.xz
    tar -xf gettext.tar.xz
    cd gettext-${GETTEXT_VERSION}
    
    # Configure and build only envsubst (minimal build)
    ./configure --prefix=/usr/local/envsubst --disable-nls --disable-dependency-tracking
    make -C gettext-runtime/src envsubst
    make -C gettext-runtime/src install-binPROGRAMS bindir=/usr/local/bin
    
    # Verify it was built
    test -f /usr/local/bin/envsubst || (echo "envsubst build failed" && exit 1)
    /usr/local/bin/envsubst --version
EOF


## stage: final
FROM zncdatadev/image/kubedoop-base

COPY --from=tools-builder /usr/local/bin/envsubst /usr/local/bin/envsubst

ARG PRODUCT_VERSION
ARG KUBECTL_VERSION
ARG JQ_VERSION
ARG YQ_VERSION

RUN <<EOF
    microdnf update

    microdnf install \
        gzip \
        iputils \
        openssl \
        tar \
        zip

    microdnf clean all
    rm -rf /var/cache/yum

EOF

WORKDIR /kubedoop/bin

ENV PATH="/kubedoop/bin:${PATH}"

RUN <<EOF
    set -ex
    ARCH=$(uname -m)
    ARCH=${ARCH/x86_64/amd64}
    ARCH=${ARCH/aarch64/arm64}

    # Download jq from https://github.com/jqlang/jq/releases
    curl -sSfL \
        https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${ARCH} \
        -o /kubedoop/bin/jq
    chmod +x /kubedoop/bin/jq

    # smoke test jq installation
    jq --version || (echo "jq installation failed" && exit 1)

    # Download yq from https://github.com/mikefarah/yq/releases
    curl -sSfL \
        https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH} \
        -o /kubedoop/bin/yq
    chmod +x /kubedoop/bin/yq

    # smoke test yq installation
    yq --version || (echo "yq installation failed" && exit 1)

    # Download kubectl from https://dl.k8s.io/release
    curl -sSfL \
        https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl \
        -o /kubedoop/bin/kubectl
    chmod +x /kubedoop/bin/kubectl
    # smoke test kubectl installation
    kubectl version --client || (echo "kubectl installation failed" && exit 1)

    # Verify envsubst is available (built from source in builder stage)
    envsubst --version || (echo "envsubst verification failed" && exit 1)

    chown -R kubedoop:kubedoop /kubedoop
EOF

USER kubedoop

WORKDIR /kubedoop
