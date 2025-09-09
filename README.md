# GDAL4Android

This project builds GDAL into an [Android Archive(AAR)](https://developer.android.com/studio/projects/android-library) file. So you can use GDAL's functionality in your Android App.

### Build with Docker

This project provides a Dockerfile which you can build a docker image which is suitable to build GDAL4Android without environment problems.

```bash
# Note: don't forgot to install docker.

cd <your-workspace-path>
git clone https://github.com/trailbehind/GDAL4Android.git
cd GDAL4Android

# this step produces an image named gdal4android_builder_img
docker build -t gdal4android_builder_img - < docker/Dockerfile

# this step runs a container so you can build GDAL4Android within it.
docker run -it --name gdal4android_builder -v .:/root/GDAL4Android gdal4android_builder_img

# Note: You are now in the container environment, /root/GDAL4Android is the project root directory in the container.

# override the default FindJNI.cmake, 
cp /root/GDAL4Android/docker/cmake_modules/FindJNI.cmake /usr/share/cmake-3.22/Modules/FindJNI.cmake

# change working direction to the project root directory
cd /root/GDAL4Android

# clean project first
./gradlew gdal:clean
# build gdal aar, the output aar file is in: GDAL4Android/gdal/build/outputs/aar/gdal-release.aar
./gradlew gdal:assembleRelease
# build gdaltest apk, the output apk file is in: GDAL4Android/gdaltest/build/outputs/apk/debug/gdaltest-debug.apk
./gradlew gdaltest:assembleDebug
```

### Credit

https://github.com/kikitte/GDAL4Android
