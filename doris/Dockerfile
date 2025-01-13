
FROM quay.io/zncdatadev/java-devel:8-kubedoop0.0.0-dev AS doris-build-env

ARG LDB_TOOLCHAIN_VERSION

WORKDIR /build

# install system requirements
RUN <<EOF
    microdnf update
    microdnf install \
        automake \
        autoconf \
        bzip2 \
        jq \
        libtool \
        perl-CPAN

    microdnf clean all
    rm -rf /var/cache/dnf
EOF

# setup gettext
# Because of the gettext of dnf is lack autopoint, so we need to install gettext from source.
# Download gettext https://ftp.gnu.org/gnu/gettext/gettext-0.21.tar.gz
RUN <<EOF
    set -ex
    # Get already installed gettext version
    GETTEXT_VERSION=$(gettext --version 2>/dev/null | head -n 1 | awk '{print $4}' || echo "0.21")

    mkdir -p /build/gettext
    mkdir -p /opt/gettext
    pushd /build/gettext
    curl -sSLf https://ftp.gnu.org/gnu/gettext/gettext-${GETTEXT_VERSION}.tar.gz \
        | tar -xz --strip-components=1

    ./configure --prefix=/opt/gettext
    make -j$(nproc)
    make install
    popd

    # cleanup
    rm -rf /build/gettext
EOF

ENV PATH="/opt/gettext/bin:$PATH"

# setup ldb-toolchain
# Download ldb_toolchain_gen.aarch64.sh
# https://github.com/amosbird/ldb_toolchain_gen/releases/download/v0.9.1/ldb_toolchain_gen.aarch64.sh
# or https://github.com/amosbird/ldb_toolchain_gen/releases/download/v0.9.1/ldb_toolchain_gen.sh
# Note:
#   - In 0.9.1, ldb-toolchain containes curl, it will cause dns resolution error
#   - In 0.21, ldb-toolchain containes curl, it will verify the certificate
#     file /etc/ssl/certs/ca-certificates.crt. But ca-certificates package generate a default
#     file /etc/ssl/certs/ca-bundle.crt, so we need to create a symlink to fix it.
#   - 0.14.1 aaarch64 version is error to build doris
RUN <<EOF
    set -ex
    ARCH=$(uname -m)
    ARCH=${ARCH/arm64/aarch64}

    release_file="ldb_toolchain_gen.sh"
    if [ "$ARCH" == "aarch64" ]; then
        release_file="ldb_toolchain_gen.aarch64.sh"
    fi

    mkdir -p /build/ldb-toolchain
    pushd /build/ldb-toolchain
    curl -sSLf https://github.com/amosbird/ldb_toolchain_gen/releases/download/v${LDB_TOOLCHAIN_VERSION}/${release_file} \
        -o ldb_toolchain_gen.sh

    chmod +x ldb_toolchain_gen.sh

    ./ldb_toolchain_gen.sh /opt/ldb-toolchain
    popd

    # create a symlink to bison, because doris need byacc
    ln -s /opt/ldb-toolchain/bin/bison /opt/ldb-toolchain/bin/byacc

    # fix /opt/ldb-toolchain/bin/curl certificate verify failed
    ln -s /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt

    # cleanup
    rm -rf /build/ldb-toolchain
EOF

ENV PATH="/opt/ldb-toolchain/bin:$PATH"

# alias python3 to python
RUN ln -s /usr/bin/python3 /usr/bin/python


# build doris thirdparty
FROM doris-build-env AS doris-thirdparty-prebuild

ARG PRODUCT_VERSION

WORKDIR /build

# build doris
# Download doris https://github.com/apache/doris/archive/refs/tags/3.0.3-rc04.tar.gz
RUN <<EOF
    set -ex

    mkdir -p /build/doris
    pushd /build/doris
    wget -qO- https://github.com/apache/doris/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
        | tar -xz --strip-components=1

    # build doris
    export USE_AVX2=OFF
    export USE_UNWIND=OFF
    export DISABLE_BUILD_AZURE=OFF
    cd thirdparty
    ./build-thirdparty.sh -j "$(nproc)"

    KERNEL=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    ARCH=${ARCH/aaarch64/arm64}
    ARCH=${ARCH/x86_64/amd64}

    # package prebuild thirdparty directory `installed` to /build/doris-thirdparty-${kernel}-${arch}.tar.xz
    tar -cJf /build/doris-thirdparty-${KERNEL}-${ARCH}.tar.xz installed

    popd

    # cleanup
    rm -rf /build/doris
EOF

FROM doris-build-env AS doris-build

ARG PRODUCT_VERSION

WORKDIR /build

COPY --from=doris-thirdparty-prebuild /build/doris-thirdparty-linux-amd64.tar.xz /build/doris-thirdparty-linux-amd64.tar.xz

# build doris
# Download doris https://github.com/apache/doris/archive/refs/tags/3.0.3-rc04.tar.gz
RUN <<EOF
    set -ex
    mkdir -p /build/doris
    pushd /build/doris
    wget -qO- https://github.com/apache/doris/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
        | tar -xz --strip-components=1

    # extract prebuild thirdparty
    tar -xJf /build/doris-thirdparty-linux-amd64.tar.xz -C thirdparty

    # build doris
    export USE_AVX2=OFF
    export USE_UNWIND=OFF
    export DISABLE_BUILD_AZURE=OFF
    ./build.sh

    # TODO
EOF
