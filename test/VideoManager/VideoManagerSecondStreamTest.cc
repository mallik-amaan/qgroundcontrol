#include "VideoManagerSecondStreamTest.h"

#include "SettingsManager.h"
#include "VideoManager.h"
#include "VideoReceiver.h"
#include "VideoSettings.h"

namespace {

// Minimal receiver so pure-layout logic can be exercised without a live backend.
class MockVideoReceiver : public VideoReceiver
{
public:
    MockVideoReceiver(const QString &name, QObject *parent = nullptr)
        : VideoReceiver(parent)
    {
        setName(name);
    }

    void start(uint32_t) override {}
    void stop() override {}
    void startDecoding(VideoSinkHandle) override {}
    void stopDecoding() override {}
    void startRecording(const QString &, FILE_FORMAT) override {}
    void stopRecording() override {}
    void takeScreenshot(const QString &) override {}
};

}  // namespace

void VideoManagerSecondStreamTest::init()
{
    UnitTest::init();
}

void VideoManagerSecondStreamTest::_testStreamConfigured2()
{
    VideoSettings *const settings = SettingsManager::instance()->videoSettings();
    QVERIFY(settings);

    QVERIFY(!settings->streamConfigured2());

    settings->videoSource2()->setRawValue(settings->udp264VideoSource());
    settings->udpUrl2()->setRawValue(QStringLiteral("0.0.0.0:5601"));
    QVERIFY(settings->streamConfigured2());

    settings->videoSource2()->setRawValue(settings->rtspVideoSource());
    settings->rtspUrl2()->setRawValue(QStringLiteral("rtsp://192.168.42.1:554/live2"));
    QVERIFY(settings->streamConfigured2());

    settings->videoSource2()->setRawValue(settings->tcpVideoSource());
    settings->tcpUrl2()->setRawValue(QStringLiteral("192.168.143.200:3002"));
    QVERIFY(settings->streamConfigured2());

    settings->videoSource2()->setRawValue(settings->disabledVideoSource());
    QVERIFY(!settings->streamConfigured2());
}

void VideoManagerSecondStreamTest::_testHasVideo2()
{
    VideoManager videoManager;
    VideoSettings *const settings = SettingsManager::instance()->videoSettings();
    QVERIFY(settings);

    QVERIFY(!videoManager.hasVideo2());

    settings->videoSource2()->setRawValue(settings->udp264VideoSource());
    settings->udpUrl2()->setRawValue(QStringLiteral("0.0.0.0:5601"));
    QVERIFY(videoManager.hasVideo2());

    settings->videoSource2()->setRawValue(settings->disabledVideoSource());
    QVERIFY(!videoManager.hasVideo2());
}

void VideoManagerSecondStreamTest::_testShouldStartReceiver()
{
    VideoManager videoManager;
    VideoSettings *const settings = SettingsManager::instance()->videoSettings();

    MockVideoReceiver primary(QStringLiteral("videoContent"));
    MockVideoReceiver second(QStringLiteral("secondContentVideo"));
    MockVideoReceiver thermal(QStringLiteral("thermalVideo"));

    // Primary and thermal are gated on the stream-1 configuration.
    settings->videoSource()->setRawValue(settings->disabledVideoSource());
    QVERIFY(!videoManager._shouldStartReceiver(&primary));
    QVERIFY(!videoManager._shouldStartReceiver(&thermal));

    // The second stream starts independently of stream 1.
    QVERIFY(!videoManager._shouldStartReceiver(&second));

    settings->videoSource2()->setRawValue(settings->udp264VideoSource());
    settings->udpUrl2()->setRawValue(QStringLiteral("0.0.0.0:5601"));
    QVERIFY(videoManager._shouldStartReceiver(&second));
    QVERIFY(!videoManager._shouldStartReceiver(&primary));
    QVERIFY(!videoManager._shouldStartReceiver(&thermal));
}

void VideoManagerSecondStreamTest::_testUpdateSettingsRouting()
{
    VideoManager videoManager;
    VideoSettings *const settings = SettingsManager::instance()->videoSettings();

    MockVideoReceiver second(QStringLiteral("secondContentVideo"));

    settings->videoSource2()->setRawValue(settings->udp264VideoSource());
    settings->udpUrl2()->setRawValue(QStringLiteral("0.0.0.0:5601"));
    QVERIFY(videoManager._updateSettings(&second));
    QCOMPARE(second.uri(), QStringLiteral("udp://0.0.0.0:5601"));

    settings->videoSource2()->setRawValue(settings->rtspVideoSource());
    settings->rtspUrl2()->setRawValue(QStringLiteral("rtsp://127.0.0.1:8554/live"));
    QVERIFY(videoManager._updateSettings(&second));
    QCOMPARE(second.uri(), QStringLiteral("rtsp://127.0.0.1:8554/live"));

    settings->videoSource2()->setRawValue(settings->disabledVideoSource());
    QVERIFY(videoManager._updateSettings(&second));
    QVERIFY(second.uri().isEmpty());
}

UT_REGISTER_TEST(VideoManagerSecondStreamTest, TestLabel::Unit)