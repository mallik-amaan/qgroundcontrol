# ============================================================================
# VideoManager Tests
# ============================================================================

add_subdirectory(GStreamer)

target_sources(${CMAKE_PROJECT_NAME}
    PRIVATE
        VideoManagerInitTest.cc
        VideoManagerInitTest.h
        VideoManagerSecondStreamTest.cc
        VideoManagerSecondStreamTest.h
)

add_qgc_test(VideoManagerInitTest LABELS Unit)
add_qgc_test(VideoManagerSecondStreamTest LABELS Unit)
