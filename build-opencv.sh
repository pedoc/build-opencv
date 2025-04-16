#!/bin/bash

set -e

# export https_proxy="http://192.168.1.2:10808"
# export http_proxy="http://192.168.1.2:10808"
# export ftp_proxy="http://192.168.1.2:10808"

# shellcheck disable=SC1091
source /etc/profile

ARCH=$(uname -m)
VCPKG_ARCH=""
case "$ARCH" in
"x86_64")
    ARCH="amd64"
    VCPKG_ARCH="x64"
    ;;
"aarch64")
    ARCH="aarch64"
    VCPKG_ARCH="arm64"
    ;;
*)
    err "Unsupport arch: $ARCH"
    exit 1
    ;;
esac

echo "os info:"
cat /etc/os-release
uname -a
echo "cpu info:"
lscpu
echo "sources list:"
cat /etc/apt/sources.list

OPENCV_VERSION="4.5.5"
OPENCV_VERSION_NO_DOT="${OPENCV_VERSION//./}"
OPENCV_CONTRIB_VERSION="4.x"

INSTALL_DIR="/usr/local"
BUILD_DIR="$HOME/opencv_build"
mkdir -p "$BUILD_DIR"

NUM_JOBS=$(nproc)

echo "prepare deps..."
sed -i 's|^deb cdrom:|#&|' /etc/apt/sources.list
apt update
apt install -y sudo libssl-dev wget curl zip build-essential git pkg-config python3 python3-pip python3-dev ccache zlib1g-dev libsqlite3-dev bison nasm libx11-dev libxft-dev libxext-dev linux-libc-dev libxmu-dev libxi-dev libgl-dev autoconf libtool gfortran libxt-dev libxtst-dev

install_bellsoft_jdk8() {
    local url="https://download.bell-sw.com/java/8u432+7/bellsoft-jdk8u432+7-linux-${ARCH}.tar.gz"
    local archive="bellsoft-jdk8u432+7-linux-${ARCH}.tar.gz"
    local install_dir="/opt/bellsoft-jdk8u432+7"
    local profile_file="/etc/profile.d/bellsoft-jdk8.sh"

    if [ -d "$install_dir" ]; then
        echo "bellsoft jdk8 already installed to $install_dir"
        return 0
    fi
    echo "install bellsoft jdk8 ..."
    wget -c "$url" -O "/tmp/$archive" || {
        return 1
    }

    sudo mkdir -p "$install_dir"
    sudo tar -xzf "/tmp/$archive" --strip-components=1 -C "$install_dir"

    sudo tee "$profile_file" >/dev/null <<EOF
export JAVA_HOME=$install_dir
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
    # shellcheck disable=SC1091
    source /etc/profile
    echo "bellsoft jdk8 installed to $install_dir"
    java -version
}

install_ant() {
    ANT_VERSION="1.10.15"
    ANT_TAR_URL="https://downloads.apache.org/ant/binaries/apache-ant-${ANT_VERSION}-bin.tar.gz"
    INSTALL_DIR="/opt/ant"

    if [ -d "$INSTALL_DIR" ]; then
        echo "ant already installed to $INSTALL_DIR"
        return 0
    fi

    sudo mkdir -p $INSTALL_DIR

    echo "Downloading Apache Ant version ${ANT_VERSION}..."
    wget -q $ANT_TAR_URL -O /tmp/apache-ant-${ANT_VERSION}.tar.gz

    if [ $? -ne 0 ]; then
        echo "Download failed!"
        exit 1
    fi

    echo "Installing Apache Ant to ${INSTALL_DIR}..."
    sudo tar -xzf /tmp/apache-ant-${ANT_VERSION}.tar.gz -C $INSTALL_DIR --strip-components=1

    echo "Configuring environment variables..."

    echo "export ANT_HOME=${INSTALL_DIR}" | sudo tee -a /etc/profile.d/ant.sh
    echo "export PATH=\$ANT_HOME/bin:\$PATH" | sudo tee -a /etc/profile.d/ant.sh

    # shellcheck disable=SC1091
    source /etc/profile

    echo "Apache Ant installation complete. Verifying version..."
    ant -version

    if [ $? -eq 0 ]; then
        echo "Apache Ant ${ANT_VERSION} successfully installed!"
    else
        echo "Ant installation failed!"
    fi
}

install_gcc9() {
    echo "install gcc 9.5.0 ..."
    if ! command -v gcc &>/dev/null || [[ "$(gcc -dumpversion)" != "9.5.0" ]]; then
        cd "$BUILD_DIR"
        wget https://mirrors.tuna.tsinghua.edu.cn/gnu/gcc/gcc-9.5.0/gcc-9.5.0.tar.gz -O gcc-9.5.0.tar.gz
        tar -zxvf gcc-9.5.0.tar.gz
        cd gcc-9.5.0
        sed -i 's|ftp://|https://|g' ./contrib/download_prerequisites
        #sed -i "s|fetch='wget'|fetch='curl -LO -u anonymous:'|g" ./contrib/download_prerequisites
        ./contrib/download_prerequisites --force --no-verify
        rm -rf build || true
        mkdir -p build && cd build
        ../configure --prefix=/usr/local/gcc-9.5.0 \
            --enable-languages=c,c++ \
            --disable-multilib
        make -j"$NUM_JOBS"
        sudo make install

        rm -rf /usr/bin/gcc
        rm -rf /usr/bin/g++
        sudo ln -s /usr/local/gcc-9.5.0/bin/gcc /usr/bin/gcc
        sudo ln -s /usr/local/gcc-9.5.0/bin/g++ /usr/bin/g++
    fi
    gcc --version
    g++ --version
}

install_python38() {
    echo "install python 3.8.2 ..."
    if ! command -v python3 &>/dev/null || [[ "$(python3 --version)" != "Python 3.8.2" ]]; then
        cd "$BUILD_DIR"
        wget https://www.python.org/ftp/python/3.8.2/Python-3.8.2.tgz
        tar -zxvf Python-3.8.2.tgz
        cd Python-3.8.2
        ./configure --enable-optimizations --enable-loadable-sqlite-extensions
        make -j"$NUM_JOBS"
        sudo make install

        curl -O https://bootstrap.pypa.io/pip/get-pip.py
        python3 get-pip.py
        # /usr/local/bin/pip3.8 --version
        # sudo ln -sf /usr/local/bin/pip3.8 /usr/local/bin/pip
    fi
    python3 --version
    pip3 --version
}

install_bellsoft_jdk8
install_ant
# install_gcc9
install_python38
# apt install -y ant

pip3 install numpy --root-user-action=ignore

#for qt-base
pip3 install jinja2 --root-user-action=ignore
apt -y install '^libxcb.*-dev' libx11-xcb-dev libgl1-mesa-dev libxrender-dev libxi-dev libxkbcommon-dev libxkbcommon-x11-dev

cd "$BUILD_DIR"

# 低版本cmake无法识别到Java wrappers
if ! command -v cmake &>/dev/null || [ "$(cmake --version | head -n1 | awk '{print $3}')" != "3.31.7" ]; then
    echo "install cmake 3.31.7 ..."
    wget https://github.com/Kitware/CMake/releases/download/v3.31.7/cmake-3.31.7.tar.gz
    tar -zxvf cmake-3.31.7.tar.gz
    cd cmake-3.31.7
    ./bootstrap
    make
    sudo make install
    cmake --version
fi

if ! command -v vcpkg &>/dev/null; then
    cd "$BUILD_DIR"
    echo "install vcpkg..."
    if [ ! -d "opencv" ]; then
        git clone --depth 1 https://www.github.com/microsoft/vcpkg
    fi
    cd vcpkg/
    ./bootstrap-vcpkg.sh
    chmod +x vcpkg
    sudo ln -sf $(pwd)/vcpkg /usr/bin/vcpkg
    vcpkg version

    sudo tee /etc/profile.d/vcpkg.sh >/dev/null <<EOF
  export VCPKG_ROOT=$(pwd)
  export VCPKG_DISABLE_METRICS='1'
EOF
    source /etc/profile
fi

cd "$BUILD_DIR"
echo "[$(pwd)] clone opencv($OPENCV_VERSION)..."
if [ ! -d "opencv" ]; then
    git clone -b "$OPENCV_VERSION" --depth 1 https://github.com/opencv/opencv.git
fi

echo "[$(pwd)] clone opencv_contrib($OPENCV_CONTRIB_VERSION)..."
if [ ! -d "opencv_contrib" ]; then
    git clone -b "$OPENCV_CONTRIB_VERSION" --depth 1 https://github.com/opencv/opencv_contrib.git
fi

export VCPKG_DEFAULT_TRIPLET="${VCPKG_ARCH}-linux"
export VCPKG_BUILD_TYPE=release
echo "[$(pwd)] set vcpkg triplet to $VCPKG_DEFAULT_TRIPLET, build type to $VCPKG_BUILD_TYPE"

echo "[$(pwd)] install opencv dependencies over vcpkg ..."
# vcpkg install libpng libjpeg-turbo libwebp tiff openexr openblas lapack vtk ffmpeg hdf5 eigen3 tesseract freetype openssl qt5-base
# vcpkg install libpng libjpeg-turbo libwebp tiff openexr openblas lapack ffmpeg hdf5 freetype openssl qt5-base

echo "libwebp portfile:"
cat "$VCPKG_ROOT/ports/libwebp/portfile.cmake"

vcpkg install zlib libpng libjpeg-turbo libwebp tiff openjpeg

rm -rf "$BUILD_DIR/build" || true
mkdir -p "$BUILD_DIR/build"
cd "$BUILD_DIR/build"

echo "[$(pwd)] configure opencv..."
cmake -D CMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
    -D VCPKG_TARGET_TRIPLET=$VCPKG_DEFAULT_TRIPLET \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -D OPENCV_EXTRA_MODULES_PATH="$BUILD_DIR/opencv_contrib/modules" \
    -D ENABLE_PRECOMPILED_HEADERS=ON \
    -D BUILD_EXAMPLES=OFF \
    -D BUILD_DOCS=OFF \
    -S "$BUILD_DIR/opencv" \
    -B "$BUILD_DIR/build" \
    -D BUILD_opencv_apps=OFF \
    -D BUILD_TESTS=OFF \
    -D BUILD_PERF_TESTS=OFF \
    -D OPENCV_ENABLE_JAVA=ON \
    -D BUILD_JAVA=ON \
    -D BUILD_opencv_java=ON \
    -D BUILD_opencv_java_bindings_generator=ON \
    -D BUILD_SHARED_LIBS=OFF \
    -D OPENCV_ENABLE_NONFREE=ON \
    -D BUILD_LIST=core,imgproc,highgui,imgcodecs,java,java_bindings_generator \
    -D WITH_QT=ON \
    -D ccitt=OFF \
    -D BUILD_ITT=OFF \
    -D WITH_ITT=OFF \
    -D WITH_VTK=OFF \
    -D WITH_OPENEXR=OFF \
    -D CV_TRACE=OFF \
    -D WITH_EIGEN=OFF \
    -D WITH_OPENCL=ON

echo "build..."
make -j"$NUM_JOBS"

echo "install $INSTALL_DIR ..."
sudo make install
#sudo ldconfig

echo "[$(pwd)] archive"
ARCHIVE_FILE="opencv-$OPENCV_VERSION-$(uname -m).tar.gz"
ARCHIVE_DIR="$BUILD_DIR/opencv-$OPENCV_VERSION-$(uname -m)"
mkdir -p "$ARCHIVE_DIR"
cp "$BUILD_DIR/build/bin/opencv-${OPENCV_VERSION_NO_DOT}.jar" "$ARCHIVE_DIR"
cp "$BUILD_DIR/build/lib/libopencv_java${OPENCV_VERSION_NO_DOT}.so" "$ARCHIVE_DIR"
tar -czvf "$BUILD_DIR/${ARCHIVE_FILE}" -C "$ARCHIVE_DIR" .
echo "[$(pwd)] archive done to $BUILD_DIR/${ARCHIVE_FILE}"

echo "done"
