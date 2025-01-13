export http_proxy=http://192.168.6.173:1080
export https_proxy=http://192.168.6.173:1080
export HTTP_PROXY=http://192.168.6.173:1080
export HTTPS_PROXY=http://192.168.6.173:1080
export NO_PROXY=localhost,127.0.0.0/8,*.internal.example.net

##########################################################################################
# Define versions
LDB_TOOLCHAIN_VERSION=0.21
PRODUCT_VERSION=2.1.7-rc03
JAVA_VERSION=8
NODE_VERSION=12.22.12

##########################################################################################
# Install dependencies
# https://adoptium.net/en-GB/installation/linux/#_centosrhelfedora_instructions
# https://adoptium.net/en-GB/installation/linux/#_centosrhelfedora_instructions
    cat <<EOF > /etc/yum.repos.d/adoptium.repo
[Adoptium]
name=Adoptium
baseurl=https://packages.adoptium.net/artifactory/rpm/${DISTRIBUTION_NAME:-$(. /etc/os-release; echo $ID)}/\$releasever/\$basearch
enabled=1
gpgcheck=1
gpgkey=https://packages.adoptium.net/artifactory/api/gpg/key/public
EOF

dnf update -y --setopt=install_weak_deps=False
dnf install -y --setopt=install_weak_deps=False \
    bzip2 \
    gzip \
    hostname \
    jq \
    maven-openjdk${JAVA_VERSION} \
    nodejs \
    patch \
    perl-CPAN \
    pkg-config \
    tar \
    temurin-${JAVA_VERSION}-jdk \
    tzdata-java \
    which \
    unzip \
    wget \
    xz

dnf clean all
rm -rf /var/cache/yum

export JAVA_HOME=/usr/lib/jvm/temurin-${PRODUCT_VERSION}-jdk
export JAVA_VERSION=${PRODUCT_VERSION}


##########################################################################################
# alias python to python3
ln -s /usr/bin/python3 /usr/bin/python


##########################################################################################
# Get already installed gettext version
# Because of the gettext of dnf is lack autopoint, so we need to install gettext from source.
# Download gettext https://ftp.gnu.org/gnu/gettext/gettext-0.21.tar.gz
# GETTEXT_VERSION=$(gettext --version | head -n 1 | awk '{print $4}')
GETTEXT_VERSION=0.21

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



##########################################################################################
# Build Doris
mkdir -p /build/doris
pushd /build/doris
curl -sSLf https://github.com/apache/doris/archive/refs/tags/${PRODUCT_VERSION}.tar.gz \
    | tar -xz --strip-components=1

# Add 'set -x' after 'set -euo pipefail'
sed -i '/set -eo pipefail/a set -x' /build/doris/build.sh
sed -i '/set -eo pipefail/a set -x' /build/doris/thirdparty/build-thirdparty.sh


# get tag sha
tag_sha=$(curl -s -H "Accept: application/vnd.github.v3.raw" "https://api.github.com/repos/apache/doris/git/ref/tags/${PRODUCT_VERSION}" | jq -r '.object.sha')
# get submodule sha from tag sha
# apache-orc: be/src/apache-orc
# clucene: be/src/clucene
submodule_apache_orc_sha=$(curl -s -H "Accept: application/vnd.github.v3.raw" "https://api.github.com/repos/apache/doris/git/trees/${tag_sha}?recursive=1" | jq -r '.tree[] | select(.path == "be/src/apache-orc") | .sha')
submodule_clucene_sha=$(curl -s -H "Accept: application/vnd.github.v3.raw" "https://api.github.com/repos/apache/doris/git/trees/${tag_sha}?recursive=1" | jq -r '.tree[] | select(.path == "be/src/clucene") | .sha')

# Patch build.sh submodule sha
sed -i "s|/refs/heads/orc.tar.gz|/${submodule_apache_orc_sha}/orc.tar.gz|" build.sh
sed -i "s|/refs/heads/clucene.tar.gz|/${submodule_clucene_sha}/clucene.tar.gz|" build.sh


LDB_TOOLCHAIN_VERSION=0.21
PRODUCT_VERSION=2.1.7-rc03
JAVA_VERSION=8
export PATH="/opt/gettext/bin:$PATH"
export PATH="/opt/ldb-toolchain/bin:$PATH"
export JAVA_HOME=/usr/lib/jvm/temurin-${JAVA_VERSION}-jdk

# build doris, disable avx2
export USE_AVX2=OFF
export USE_UNWIND=OFF
export DISABLE_BUILD_AZURE=OFF
# ./build.sh > /tmp/build.log 2>&1
nohup ./build.sh -j 7 > /tmp/build.log 2>&1 &
tail -f /tmp/build.log
