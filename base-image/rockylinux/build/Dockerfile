FROM rockylinux/rockylinux:9

# Install packages that we want to make available at build time
RUN dnf -y install --setopt=install_weak_deps=False \
    wget \
    xz \
    && dnf clean all

# Set the default user and group ID
ARG cnb_uid=1000
ARG cnb_gid=1000
ENV CNB_USER_ID=${cnb_uid}
ENV CNB_GROUP_ID=${cnb_gid}

# Create the user and group
RUN groupadd --gid ${CNB_GROUP_ID} cnb && \
    useradd --uid ${CNB_USER_ID} --gid ${CNB_GROUP_ID} --home-dir /home/cnb --no-create-home cnb

# Set the default user
USER ${CNB_USER_ID}:${CNB_GROUP_ID}

# Set CNB target information
LABEL io.buildpacks.base.distro.name="rockylinux"
LABEL io.buildpacks.base.distro.version="9"
