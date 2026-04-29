# Build environment for the Inferno port of llama2.c.
#
# Inferno's hosted Linux build only ships an i386 mkfile, so we use a
# 32-bit base image (this works on amd64 hosts via QEMU user-mode binfmt).
# Ubuntu dropped i386 images after 18.04, so we use Debian's i386 image
# which is still actively maintained.
FROM i386/debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get -y update && apt-get install -y --no-install-recommends \
        libx11-dev libxext-dev libc6-dev gcc make ca-certificates git wget \
    && rm -rf /var/lib/apt/lists/*

ENV INFERNO=/inferno
ARG INFERNO_REV=master
RUN git clone --recurse-submodules https://github.com/inferno-os/inferno-os.git $INFERNO \
 && (cd $INFERNO && git checkout $INFERNO_REV && git submodule update --init --recursive)

WORKDIR $INFERNO

# mkconfig copied verbatim from inferno-os/inferno-os/Dockerfile.
RUN echo  > mkconfig "ROOT=$INFERNO" \
 && echo >> mkconfig "TKSTYLE=std"   \
 && echo >> mkconfig "SYSHOST=Linux" \
 && echo >> mkconfig "SYSTARG=Linux" \
 && echo >> mkconfig "OBJTYPE=386"   \
 && echo >> mkconfig 'OBJDIR=$SYSTARG/$OBJTYPE' \
 && echo >> mkconfig '<$ROOT/mkfiles/mkhost-$SYSHOST' \
 && echo >> mkconfig '<$ROOT/mkfiles/mkfile-$SYSTARG-$OBJTYPE'

RUN ./makemk.sh
ENV PATH="$INFERNO/Linux/386/bin:${PATH}"
RUN mk nuke && mk install

# project workspace.  The CI workflow bind-mounts the repository at /work.
WORKDIR /work
