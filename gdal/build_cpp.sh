#!/bin/bash
set -e

ANDROID_NDK=$1
MIN_SDK_VERSION=$2
BUILD_TYPE=$3 # Debug or Release

export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    x86_64)
        HOST_TAG="linux-x86_64"
        ;;
    aarch64)
        HOST_TAG="linux-aarch64"
        ;;
    *)
        echo "Unsupported architecture: $HOST_ARCH"
        exit 1
        ;;
esac
TOOLCHAIN=$ANDROID_NDK/toolchains/llvm/prebuilt/$HOST_TAG
CMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake
BUILD_THREADS=$(getconf _NPROCESSORS_ONLN)
SOURCE_DIR=$(realpath "$(dirname $0)")/cpp

function build_iconv() {
  local TARGET=$1
  local ABI=$2
  local API=$3
  local BUILD_DIR=$4
  local INSTALL_DIR=$5
  local BUILD_THREADS=$6

  local SOURCE_DIR=$(pwd)

  cd $BUILD_DIR

  local CONFIGURE_FLAGS="--host=$TARGET --prefix=$INSTALL_DIR --enable-shared --disable-static"
  local BUILD_CFLAGS
  if [[ "${BUILD_TYPE,,}" == "release" ]]; then
    BUILD_CFLAGS="-O3 -g0 -finline-functions"
  else
    BUILD_CFLAGS="-O0 -g -fno-inline-functions"
  fi

  $SOURCE_DIR/configure $CONFIGURE_FLAGS \
    CC="$CC" CXX="$CXX" \
    CFLAGS="${BUILD_CFLAGS}" \
    CXXFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="-Wl,-z,max-page-size=16384"

  make clean
  make -j$BUILD_THREADS
  make install
}

function build_sqlite() {
  local TARGET=$1
  local ABI=$2
  local API=$3
  local BUILD_DIR=$4
  local INSTALL_DIR=$5
  local BUILD_THREADS=$6

  # Use CMake to ensure correct cross-compilation for SQLite
  cmake -S . -B $BUILD_DIR \
        -DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE \
        -DANDROID_ABI=$ABI \
        -DANDROID_PLATFORM=$API \
        -DANDROID_STL=c++_shared \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"

  cmake --build $BUILD_DIR --parallel $BUILD_THREADS --target install

  # Manually copy the sqlite3ext.h header, which is required by the GDAL
  # OGR SQLite driver but not installed by default.
  cp sqlite3ext.h $INSTALL_DIR/include/
}

function build_proj() {
  local TARGET=$1
  local ABI=$2
  local API=$3
  local BUILD_DIR=$4
  local INSTALL_DIR=$5
  local BUILD_THREADS=$6

  export PKG_CONFIG_PATH=$INSTALL_DIR/lib/pkgconfig

  cmake -S . -B $BUILD_DIR \
        -DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE \
        -DANDROID_ABI=$ABI \
        -DANDROID_PLATFORM=$API \
        -DANDROID_STL=c++_shared \
        -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
        -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
        -DCMAKE_PREFIX_PATH=$INSTALL_DIR \
        -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
        -DSQLITE3_INCLUDE_DIR=$INSTALL_DIR/include \
        -DSQLITE3_LIBRARY=$INSTALL_DIR/lib/libsqlite3.so \
        -DENABLE_TIFF=OFF \
        -DENABLE_CURL=OFF \
        -DBUILD_APPS=OFF \
        -DBUILD_TESTING=OFF \
        -DEXE_SQLITE3=/usr/bin/sqlite3

  cmake --build $BUILD_DIR --parallel $BUILD_THREADS --target install
}

function build_expat() {
  local TARGET=$1
  local ABI=$2
  local API=$3
  local BUILD_DIR=$4
  local INSTALL_DIR=$5
  local BUILD_THREADS=$6

  local SOURCE_DIR=$(pwd)

  cd $BUILD_DIR

  local BUILD_CFLAGS
  if [[ "${BUILD_TYPE,,}" == "release" ]]; then
    BUILD_CFLAGS="-O3 -g0 -finline-functions"
  else
    BUILD_CFLAGS="-O0 -g -fno-inline-functions"
  fi


  $SOURCE_DIR/configure --host=$TARGET --prefix=$INSTALL_DIR \
    CC="$CC" CXX="$CXX" \
    CFLAGS="${BUILD_CFLAGS}" \
    CXXFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="-Wl,-z,max-page-size=16384"

  make clean
  make -j$BUILD_THREADS
  make install
}

function build_png() {
  local TARGET=$1
  local ABI=$2
  local API=$3
  local BUILD_DIR=$4
  local INSTALL_DIR=$5
  local BUILD_THREADS=$6

  local SOURCE_DIR=$(pwd)

  cd $BUILD_DIR

  local BUILD_CFLAGS
  if [[ "${BUILD_TYPE,,}" == "release" ]]; then
    BUILD_CFLAGS="-O3 -g0 -finline-functions"
  else
    BUILD_CFLAGS="-O0 -g -fno-inline-functions"
  fi

  $SOURCE_DIR/configure --host=$TARGET --prefix=$INSTALL_DIR --enable-shared --disable-static \
    CC="$CC" CXX="$CXX" \
    CFLAGS="${BUILD_CFLAGS}" \
    CXXFLAGS="${BUILD_CFLAGS}" \
    LDFLAGS="-Wl,-z,max-page-size=16384"

  make clean
  make -j$BUILD_THREADS
  make install
}

function build_gdal() {
  local TARGET=$1
  local ABI=$2
  local API=$3
  local BUILD_DIR=$4
  local INSTALL_DIR=$5
  local BUILD_THREADS=$6

  # Unsetting PKG_CONFIG_PATH turns off pkg-config, which struggles with this part of the build
  # since it finds proj.pc, which requires sqlite3, but sqlite3 does not provide an sqlite3.pc file.
  # Then, pkg-config returns NOT FOUND for PROJ but ignores the path arguments below.
  unset PKG_CONFIG_PATH

  # For 32-bit ABIs, we must add the _FILE_OFFSET_BITS=64 definition.
  # Passing it directly as a compile definition is the most reliable way
  # to ensure the NDK's CMake toolchain respects it.
  local ARCH_SPECIFIC_DEFS=""
  if [[ "$ABI" == "x86" || "$ABI" == "armeabi-v7a" ]]; then
    ARCH_SPECIFIC_DEFS="-DBUILD_WITHOUT_64BIT_OFFSET"
  fi

  cmake -S . -B $BUILD_DIR \
   -DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE \
   -DANDROID_ABI=$ABI \
   -DANDROID_PLATFORM=$API \
   -DANDROID_STL=c++_shared \
   -DCMAKE_INSTALL_PREFIX=$INSTALL_DIR \
   -DCMAKE_PREFIX_PATH=$INSTALL_DIR \
   -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
   -DCMAKE_C_FLAGS="${ARCH_SPECIFIC_DEFS}" \
   -DCMAKE_CXX_FLAGS="${ARCH_SPECIFIC_DEFS}" \
   -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384" \
   -DJAVA_AWT_LIBRARY=$JAVA_HOME/lib/server/libawt.so \
   -DJAVA_AWT_INCLUDE_PATH=$JAVA_HOME/include \
   -DJAVA_JVM_LIBRARY=$JAVA_HOME/lib/server/libjvm.so \
   -DJAVA_INCLUDE_PATH=$JAVA_HOME/include \
   -DJAVA_INCLUDE_PATH2=$JAVA_HOME/include/linux \
   -DIconv_INCLUDE_DIR=$INSTALL_DIR/include \
   -DIconv_LIBRARY=$INSTALL_DIR/lib/libiconv.so \
   -DEXPAT_INCLUDE_DIR=$INSTALL_DIR/include \
   -DEXPAT_LIBRARY=$INSTALL_DIR/lib/libexpat.so \
   -DPNG_PNG_INCLUDE_DIR=$INSTALL_DIR/include \
   -DPNG_LIBRARY=$INSTALL_DIR/lib/libpng.so \
   -DPROJ_INCLUDE_DIR=$INSTALL_DIR/include \
   -DPROJ_LIBRARY=$INSTALL_DIR/lib/libproj.so \
   -DSQLITE3_INCLUDE_DIR=$INSTALL_DIR/include \
   -DSQLITE3_LIBRARY=$INSTALL_DIR/lib/libsqlite3.so \
   -DGDAL_USE_PLUGINS=OFF \
   -DGDAL_USE_SQLITE3=ON \
   -DGDAL_USE_EXPAT=ON \
   -DGDAL_USE_ICONV=ON \
   -DGDAL_USE_PNG=ON \
   -DBUILD_PYTHON_BINDINGS=OFF \
   -DBUILD_CSHARP_BINDINGS=OFF \
   -DBUILD_JAVA_BINDINGS=ON \
   -DBUILD_TESTING=OFF \
   -DGDAL_JAVA_BUILD_APPS=OFF \
   -DSWIG_DEFINES="-DSWIGANDROID"

  cmake --build $BUILD_DIR --parallel $BUILD_THREADS --target install
}

function build_for_target() {
    local TARGET=$1
    local ABI=$2
    local API=$3

    echo "############################ Build for $TARGET: $BUILD_TYPE ###############################"

    mkdir -p $SOURCE_DIR
    cd $SOURCE_DIR

    # download file if necessary
    local SQLITE=sqlite-amalgamation-3420000
    local PROJ=proj-9.2.1
    local GDAL=gdal-3.5.0
    local EXPAT=expat-2.5.0
    local ICONV=libiconv-1.17
    local PNG=libpng-1.6.37
    local SQLITE_ZIP=$SQLITE.zip
    local PROJ_TARBALL=$PROJ.tar.gz
    local GDAL_TARBALL=$GDAL.tar.gz
    local EXPAT_TARBALL=$EXPAT.tar.gz
    local ICONV_TARBALL=$ICONV.tar.gz
    local PNG_TARBALL=$PNG.tar.gz

    if [ ! -f  "$SQLITE_ZIP" ]; then
      wget https://www.sqlite.org/2023/sqlite-amalgamation-3420000.zip -O $SQLITE_ZIP
    fi
    if [ ! -f "$PROJ_TARBALL" ]; then
      wget https://github.com/OSGeo/PROJ/releases/download/9.2.1/proj-9.2.1.tar.gz -O $PROJ_TARBALL
    fi
    if [ ! -f "$GDAL_TARBALL" ]; then
      wget https://github.com/OSGeo/gdal/releases/download/v3.5.0/gdal-3.5.0.tar.gz -O $GDAL_TARBALL
    fi
    if [ ! -f "$EXPAT_TARBALL" ]; then
      wget https://github.com/libexpat/libexpat/releases/download/R_2_5_0/expat-2.5.0.tar.gz -O $EXPAT_TARBALL
    fi
    if [ ! -f "$ICONV_TARBALL" ]; then
      wget https://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.17.tar.gz -O $ICONV_TARBALL
    fi
    if [ ! -f "$PNG_TARBALL" ]; then
      wget https://download.sourceforge.net/libpng/libpng-1.6.37.tar.gz -O $PNG_TARBALL
    fi

    local SQLITE_SOURCE_DIR=$SOURCE_DIR/$SQLITE
    local PROJ_SOURCE_DIR=$SOURCE_DIR/$PROJ
    local GDAL_SOURCE_DIR=$SOURCE_DIR/$GDAL
    local EXPAT_SOURCE_DIR=$SOURCE_DIR/$EXPAT
    local ICONV_SOURCE_DIR=$SOURCE_DIR/$ICONV
    local PNG_SOURCE_DIR=$SOURCE_DIR/$PNG

    rm -rf $SQLITE_SOURCE_DIR $PROJ_SOURCE_DIR $GDAL_SOURCE_DIR $EXPAT_SOURCE_DIR $ICONV_SOURCE_DIR $PNG_SOURCE_DIR

    unzip -q $SQLITE_ZIP
    tar -xzf $PROJ_TARBALL
    tar -xzf $GDAL_TARBALL
    tar -xzf $EXPAT_TARBALL
    tar -xzf $ICONV_TARBALL
    tar -xzf $PNG_TARBALL

    # GDALtest.java fails when building Android bindings
    rm -f $GDAL_SOURCE_DIR/swig/java/apps/GDALtest.java

    # Generate a CMakeLists.txt file for building sqlite
    cat > $SQLITE_SOURCE_DIR/CMakeLists.txt << EOL
cmake_minimum_required(VERSION 3.10)
project(sqlite3 C)

add_library(sqlite3 SHARED sqlite3.c)

target_compile_definitions(sqlite3 PRIVATE
    SQLITE_ENABLE_COLUMN_METADATA
    SQLITE_ENABLE_FTS5
    SQLITE_ENABLE_RTREE
    SQLITE_ENABLE_JSON1
)

install(TARGETS sqlite3
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
)
install(FILES sqlite3.h DESTINATION include)
EOL

    # prepare cross compile environment
    export AR=$TOOLCHAIN/bin/llvm-ar
    export CC=$TOOLCHAIN/bin/$TARGET$API-clang
    export AS=$CC
    export CXX=$TOOLCHAIN/bin/$TARGET$API-clang++
    export LD=$TOOLCHAIN/bin/ld
    export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
    export STRIP=$TOOLCHAIN/bin/llvm-strip
    export JAVA_HOME=$JAVA_HOME

    local BUILD_DIR=$SOURCE_DIR/.build/$TARGET
    local INSTALL_DIR=$SOURCE_DIR/.install/$TARGET

    rm -rf $BUILD_DIR $INSTALL_DIR
    mkdir -p $BUILD_DIR $INSTALL_DIR

    local ICONV_BUILD_DIR=$BUILD_DIR/iconv
    local ICONV_INSTALL_DIR=$INSTALL_DIR
    mkdir -p $ICONV_BUILD_DIR $ICONV_INSTALL_DIR
    cd $ICONV_SOURCE_DIR
    build_iconv $TARGET $ABI $API $ICONV_BUILD_DIR $ICONV_INSTALL_DIR $BUILD_THREADS

    local SQLITE_BUILD_DIR=$BUILD_DIR/sqlite
    local SQLITE_INSTALL_DIR=$INSTALL_DIR
    mkdir -p $SQLITE_BUILD_DIR $SQLITE_INSTALL_DIR
    cd $SQLITE_SOURCE_DIR
    build_sqlite $TARGET $ABI $API $SQLITE_BUILD_DIR $SQLITE_INSTALL_DIR $BUILD_THREADS

    local EXPAT_BUILD_DIR=$BUILD_DIR/expat
    local EXPAT_INSTALL_DIR=$INSTALL_DIR
    mkdir -p $EXPAT_BUILD_DIR $EXPAT_INSTALL_DIR
    cd $EXPAT_SOURCE_DIR
    build_expat $TARGET $ABI $API $EXPAT_BUILD_DIR $EXPAT_INSTALL_DIR $BUILD_THREADS

    local PNG_BUILD_DIR=$BUILD_DIR/png
    local PNG_INSTALL_DIR=$INSTALL_DIR
    mkdir -p $PNG_BUILD_DIR $PNG_INSTALL_DIR
    cd $PNG_SOURCE_DIR
    build_png $TARGET $ABI $API $PNG_BUILD_DIR $PNG_INSTALL_DIR $BUILD_THREADS

    local PROJ_BUILD_DIR=$BUILD_DIR/proj
    local PROJ_INSTALL_DIR=$INSTALL_DIR
    mkdir -p $PROJ_BUILD_DIR $PROJ_INSTALL_DIR
    cd $PROJ_SOURCE_DIR
    build_proj $TARGET $ABI $API $PROJ_BUILD_DIR $PROJ_INSTALL_DIR $BUILD_THREADS

    local GDAL_BUILD_DIR=$BUILD_DIR/gdal
    local GDAL_INSTALL_DIR=$INSTALL_DIR
    mkdir -p $GDAL_BUILD_DIR $GDAL_INSTALL_DIR
    cd $GDAL_SOURCE_DIR
    build_gdal $TARGET $ABI $API $GDAL_BUILD_DIR $GDAL_INSTALL_DIR $BUILD_THREADS

    # copy output files to destination directories
    local ABI_JNI_DIR=$SOURCE_DIR/../src/main/jniLibs/$ABI
    rm -rf $ABI_JNI_DIR
    mkdir -p $ABI_JNI_DIR
    cp $INSTALL_DIR/lib/*.so $ABI_JNI_DIR

    cp $INSTALL_DIR/share/java/*.so $ABI_JNI_DIR

    local LIBS_DIR=$SOURCE_DIR/../libs
    mkdir -p $LIBS_DIR
    rm -rf $LIBS_DIR/*
    cp $INSTALL_DIR/share/java/$GDAL.jar $LIBS_DIR
}

build_for_target "i686-linux-android" "x86" 21
build_for_target "x86_64-linux-android" "x86_64" 21
build_for_target "armv7a-linux-androideabi" "armeabi-v7a" 21
build_for_target "aarch64-linux-android" "arm64-v8a" 21
