#!/usr/bin/env bash

source ~/.nvm/nvm.sh

set -e -u

function publish() {
    if [[ ${COMMIT_MESSAGE} =~ "[publish binary]" ]]; then
        CFLAGS="${CFLAGS:-} -include $(pwd)/src/gcc-preinclude.h" CXXFLAGS="${CXXFLAGS:-} -include $(pwd)/src/gcc-preinclude.h" node-pre-gyp rebuild  --clang=1
        node-pre-gyp package testpackage
        npm run upload-binary
#        node-pre-gyp publish
#        node-pre-gyp info
        make clean
    fi
}

echo "building binaries for publishing"
CFLAGS="${CFLAGS:-} -include $(pwd)/src/gcc-preinclude.h" CXXFLAGS="${CXXFLAGS:-} -include $(pwd)/src/gcc-preinclude.h" V=1 npm install --build-from-source  --clang=1
nm lib/binding/*/node_sqlite3.node | grep "GLIBCXX_" | c++filt  || true
nm lib/binding/*/node_sqlite3.node | grep "GLIBC_" | c++filt || true
npm test

publish

# now test building against shared sqlite
echo "building from source to test against external libsqlite3"
export NODE_SQLITE3_JSON1=no
if [[ $(uname -s) == 'Darwin' ]]; then
    brew update
    brew install sqlite
    npm install --build-from-source --sqlite=$(brew --prefix) --clang=1
else
    npm install --build-from-source --sqlite=/usr --clang=1
fi
npm test
export NODE_SQLITE3_JSON1=yes

platform=$(uname -s | sed "y/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/")

: '
if [[ $(uname -s) == 'Linux' ]]; then
    # node v0.8 and above provide pre-built 32 bit and 64 bit binaries
    # so here we use the 32 bit ones to also test 32 bit builds
    NVER=`node -v`
    # enable 32 bit node
    export PATH=$(pwd)/node-${NVER}-${platform}-x86/bin:$PATH
    if [[ ${NODE_VERSION:0:4} == 'iojs' ]]; then
        wget https://iojs.org/download/release/${NVER}/iojs-${NVER}-${platform}-x86.tar.gz
        tar xf iojs-${NVER}-${platform}-x86.tar.gz
        # enable 32 bit iojs
        export PATH=$(pwd)/iojs-${NVER}-${platform}-x86/bin:$(pwd)/iojs-${NVER}-${platform}-ia32/bin:$PATH
    else
        wget https://nodejs.org/dist/${NVER}/node-${NVER}-${platform}-x86.tar.gz
        tar xf node-${NVER}-${platform}-x86.tar.gz
        # enable 32 bit node
        export PATH=$(pwd)/node-${NVER}-${platform}-x86/bin:$(pwd)/node-${NVER}-${platform}-ia32/bin:$PATH
    fi
    which node
    ls -l $(which node)
    #node -e "console.log(process.arch,process.execPath)"
    # install 32 bit compiler toolchain and X11
    # test source compile in 32 bit mode with internal libsqlite3
    CC=gcc-4.6 CXX=g++-4.6 npm install --build-from-source  --clang=1
    node-pre-gyp package testpackage
    npm test
    publish
    make clean
    # broken for some unknown reason against io.js
    if [[ ${NODE_VERSION:0:4} != 'iojs' ]]; then
        # test source compile in 32 bit mode against external libsqlite3
        export NODE_SQLITE3_JSON1=no
        CC=gcc-4.6 CXX=g++-4.6 npm install --build-from-source --sqlite=/usr  --clang=1
        npm test
    fi
fi

'
