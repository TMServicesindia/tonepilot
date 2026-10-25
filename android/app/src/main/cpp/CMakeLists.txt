cmake_minimum_required(VERSION 3.22.1)
project(tonepilot_jni C)

# The Swift core, built by the Swift SDK for Android (see .github/workflows/android-build.yml)
# and copied into jniLibs/<abi>/ before Gradle runs.
add_library(TonePilotBridge SHARED IMPORTED)
set_target_properties(TonePilotBridge PROPERTIES
    IMPORTED_LOCATION ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libTonePilotBridge.so)

add_library(tonepilot_jni SHARED tonepilot_jni.c)
target_compile_options(tonepilot_jni PRIVATE -O2 -Wall)
target_link_libraries(tonepilot_jni TonePilotBridge aaudio log)
