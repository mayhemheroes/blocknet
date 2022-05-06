# Build via docker:
# docker build --build-arg cores=8 -t blocknetdx/blocknet:latest .
FROM ubuntu:bionic AS builder

ARG cores=4
ENV ecores=$cores

RUN apt update \
  && apt install -y --no-install-recommends \
  software-properties-common \
  ca-certificates \
  wget curl git python vim \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN add-apt-repository ppa:bitcoin/bitcoin \
  && apt update \
  && apt install -y --no-install-recommends \
  build-essential libtool autotools-dev bsdmainutils \
  libevent-dev autoconf automake pkg-config libssl-dev \
  libdb4.8-dev libdb4.8++-dev python-setuptools cmake \
  libcap-dev \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# gcc 8
RUN add-apt-repository ppa:ubuntu-toolchain-r/test \
  && apt update \
  && apt install -y --no-install-recommends \
  g++-8-multilib gcc-8-multilib binutils-gold \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PROJECTDIR=/opt/blocknet/blocknet
ENV BASEPREFIX=$PROJECTDIR/depends
ENV HOST=x86_64-pc-linux-gnu

# Copy source files
RUN mkdir -p /opt/blocknet/blocknet
ADD . /opt/blocknet/blocknet

RUN mkdir -p /opt/blockchain/config \
  && mkdir -p /opt/blockchain/data \
  && ln -s /opt/blockchain/config /root/.blocknet 
WORKDIR ${BASEPREFIX}
RUN make -j$ecores 
RUN make install 
WORKDIR ${PROJECTDIR}
RUN chmod +x ./autogen.sh; sync \
  && ./autogen.sh 
# && CONFIG_SITE=$BASEPREFIX/$HOST/share/config.site ./configure CC=gcc-8 CXX=g++-8 CFLAGS='-Wno-deprecated' CXXFLAGS='-Wno-deprecated' --disable-ccache --disable-maintainer-mode --disable-dependency-tracking --without-gui --enable-hardening --prefix=/ 

# # Write default blocknet.conf (can be overridden on commandline)
# RUN echo "datadir=/opt/blockchain/data    \n\
#                                           \n\
# maxmempoolxbridge=128                     \n\
#                                           \n\
# port=41412    # testnet: 41474            \n\
# rpcport=41414 # testnet: 41419            \n\
#                                           \n\
# server=1                                  \n\
# logtimestamps=1                           \n\
# logips=1                                  \n\
#                                           \n\
# rpcbind=0.0.0.0                           \n\
# rpcallowip=127.0.0.1                      \n\
# rpctimeout=60                             \n\
# rpcclienttimeout=30" > /opt/blockchain/config/blocknet.conf


# RUN git clone https://github.com/bitcoin-core/qa-assets
# ENV DIR_FUZZ_IN=$PWD/qa-assets/fuzz_seed_corpus

RUN mkdir outputs
ENV AFLOUT=/opt/blocknet/blocknet/outputs

RUN wget http://lcamtuf.coredump.cx/afl/releases/afl-latest.tgz
RUN tar -zxvf afl-latest.tgz
WORKDIR /opt/blocknet/blocknet/afl-2.52b
RUN make
ENV AFLPATH=/opt/blocknet/blocknet/afl-2.52b

WORKDIR /opt/blocknet/blocknet

RUN add-apt-repository ppa:bitcoin/bitcoin
RUN apt-get update
RUN apt-get install -y libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev
RUN ./configure --disable-ccache --disable-shared --enable-tests --enable-fuzz --disable-wallet --disable-bench --with-utils=no --with-daemon=no --with-libs=no --with-gui=no CC=${AFLPATH}/afl-gcc CXX=${AFLPATH}/afl-g++
ENV AFL_HARDEN=1
WORKDIR /opt/blocknet/blocknet/src
RUN make


FROM ubuntu:bionic
RUN apt-get update
RUN apt-get install -y software-properties-common
RUN add-apt-repository ppa:bitcoin/bitcoin
RUN apt-get update
RUN apt-get install -y libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev
COPY --from=builder /opt/blocknet/blocknet/src/test/fuzz/ ./fuzz