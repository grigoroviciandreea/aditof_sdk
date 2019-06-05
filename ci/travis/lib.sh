#!/bin/bash

NUM_JOBS=4

echo_red() { printf "\033[1;31m$*\033[m\n"; }
echo_green() { printf "\033[1;32m$*\033[m\n"; }

############################################################################
# Check if the file given as input has .h or .cpp extension
############################################################################
is_source_file() {
    local file="$1"

    EXTENSIONS=".h .cpp"

    for extension in $EXTENSIONS; do
        [[ "${file: -2}" == "$extension" || "${file: -4}" == "$extension" ]] && return 0
    done;

    return 1
}

############################################################################
# Check if the files modified in the current commit / commit range respect
# the coding style defined in the .clang-format file
############################################################################
check_clangformat() {

    COMMIT_RANGE=$TRAVIS_COMMIT_RANGE

    if [ -z "$TRAVIS_PULL_REQUEST_SHA" ]
    then
        COMMIT_RANGE=HEAD~1
    fi

    git diff --name-only --diff-filter=d $COMMIT_RANGE | while read -r file; do
        if is_source_file "$file"
        then
            /usr/bin/clang-format-6.0 -i "$file"
        fi

    done;

    git diff --exit-code || {
        echo_red "The code is not properly formatted."
        exit 1
    }

}

############################################################################
# Run the cpp static analysis tool on the sdk
############################################################################
check_cppcheck() {
   cppcheck --quiet --force --enable=warning,performance,portability,style --std=c++11 sdk/ apps/
}

############################################################################
# Check if the documentation will be generated w/o warnings or errors
############################################################################
check_doxygen() {
    pushd ${TRAVIS_BUILD_DIR}/doc
    (cd build && ! doxygen doxygen_doc/sdk-api.doxy 2>&1 | grep -E "warning|error") || {
        echo_red "Documentation incomplete or errors in the generation of it have occured!"
        exit 1
    }
    popd
    echo_green "Documentation was generated successfully!"
}

############################################################################
# If the current build is not a pull request and it is on master the 
# documentation will be pushed to the gh-pages branch if changes occurred
# since the last version that was pushed
############################################################################
deploy_doxygen() {
    if [[ "${TRAVIS_PULL_REQUEST}" == "false" && "${TRAVIS_BRANCH}" == "master" ]]
    then
        pushd ${TRAVIS_BUILD_DIR}/doc
        git clone https://danielguramulta:${GITHUB_TOKEN}@github.com/analogdevicesinc/aditof_sdk --depth 1 --branch=gh-pages doc/html &>/dev/null

        pushd doc/html
        rm -rf *
        popd
        
        cp -R build/html/* doc/html/

        pushd doc/html
        CURRENT_COMMIT=$(git log -1 --pretty=%B)
        if [[ ${CURRENT_COMMIT:(-7)} != ${TRAVIS_COMMIT:0:7} ]]
        then
            git add --all .
            git commit --allow-empty --amend -m "Update documentation to ${TRAVIS_COMMIT:0:7}"
            git push origin gh-pages -f &>/dev/null
        else
            echo_green "Documentation already up to date!"
        fi
        popd
    else
        echo_green "Documentation will be updated when this commit gets on master!"
    fi
}

############################################################################
# Install v0.3.5 of glog in the /deps folder
############################################################################
install_glog() {
    pushd ${DEPS_DIR}
    [ -d "glog" ] || {
       git clone https://github.com/google/glog
    }
    pushd glog
    git checkout tags/v0.3.5
    mkdir -p build_0_3_5
    pushd build_0_3_5
    cmake -DWITH_GFLAGS=off ..
    sudo cmake --build . --target install 
    popd
    popd
    popd

}

############################################################################
# Install the latest version of doxygen in the /deps folder
############################################################################
install_doxygen() {
    DOXYGEN_URL="wget doxygen.nl/files/doxygen-1.8.15.src.tar.gz"
    pushd ${DEPS_DIR}
    [ -d "doxygen" ] || {
        mkdir doxygen && wget --quiet -O - ${DOXYGEN_URL} | tar --strip-components=1 -xz -C doxygen
    }
    pushd doxygen
    mkdir -p build && cd build
    cmake ..
    make -j${NUM_JOBS}
    sudo make install
    popd
    popd
}