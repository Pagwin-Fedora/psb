FROM haskell

RUN mkdir -p /github/workspace

RUN cabal update

COPY ./psb.cabal /mnt
WORKDIR /mnt
RUN cabal build --only-dependencies

COPY . /mnt

RUN cabal build

WORKDIR /github/workspace

RUN export folder=$(ls /mnt/dist-newstyle/build/x86_64-linux) && mv /mnt/dist-newstyle/build/x86_64-linux/"$folder"/psb-0.1.0.0/x/psb/build/psb/psb /mnt/psb

ENTRYPOINT ["/mnt/psb", "build"]
