#pragma once

#include <atomic>
#include <chrono>

#include <QtCore/QFuture>
#include <QtCore/QMutex>
#include <QtCore/QPromise>
#include <QtCore/QObject>
#include <QtCore/QSize>
#include <QtQmlIntegration/QtQmlIntegration>

#ifdef QGC_UNITTEST_BUILD
#include <functional>
#endif

class QQuickWindow;
class SubtitleWriter;
class Vehicle;
class VideoReceiver;
class VideoSettings;

class VideoManager : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("")
    Q_MOC_INCLUDE("Vehicle.h")

    Q_PROPERTY(bool     autoStreamConfigured    READ autoStreamConfigured                       NOTIFY autoStreamConfiguredChanged)
    Q_PROPERTY(bool     decoding                READ decoding                                   NOTIFY decodingChanged)
    Q_PROPERTY(bool     fullScreen              READ fullScreen             WRITE setfullScreen NOTIFY fullScreenChanged)
    Q_PROPERTY(bool     hasThermal              READ hasThermal                                 NOTIFY decodingChanged)
    Q_PROPERTY(bool     hasVideo                READ hasVideo                                   NOTIFY hasVideoChanged)
    Q_PROPERTY(bool     hasVideo2               READ hasVideo2                                  NOTIFY hasVideo2Changed)
    Q_PROPERTY(bool     isStreamSource          READ isStreamSource                             NOTIFY isStreamSourceChanged)
    Q_PROPERTY(bool     isUvc                   READ isUvc                                      NOTIFY isUvcChanged)
    Q_PROPERTY(bool     isUvc2                  READ isUvc2                                     NOTIFY isUvc2Changed)
    Q_PROPERTY(bool     recording               READ recording                                  NOTIFY recordingChanged)
    Q_PROPERTY(bool     streaming               READ streaming                                  NOTIFY streamingChanged)
    Q_PROPERTY(bool     secondStreamDecoding    READ secondStreamDecoding                        NOTIFY secondStreamDecodingChanged)
    Q_PROPERTY(double   aspectRatio             READ aspectRatio                                NOTIFY aspectRatioChanged)
    Q_PROPERTY(double   hfov                    READ hfov                                       NOTIFY aspectRatioChanged)
    Q_PROPERTY(double   thermalAspectRatio      READ thermalAspectRatio                         NOTIFY aspectRatioChanged)
    Q_PROPERTY(double   thermalHfov             READ thermalHfov                                NOTIFY aspectRatioChanged)
    Q_PROPERTY(QSize    videoSize               READ videoSize                                  NOTIFY videoSizeChanged)
    Q_PROPERTY(QString  imageFile               READ imageFile                                  NOTIFY imageFileChanged)
    Q_PROPERTY(QString  uvcVideoSourceID        READ uvcVideoSourceID                           NOTIFY uvcVideoSourceIDChanged)
    Q_PROPERTY(QString  uvcVideoSourceID2       READ uvcVideoSourceID2                          NOTIFY uvcVideoSourceID2Changed)

    friend class VideoManagerInitTest;
    friend class VideoManagerSecondStreamTest;

public:
    explicit VideoManager(QObject *parent = nullptr);
    ~VideoManager();

    static VideoManager *instance();

    Q_INVOKABLE void grabImage(const QString &imageFile = QString());
    Q_INVOKABLE void startRecording(const QString &videoFile = QString());
    Q_INVOKABLE void startVideo();
    Q_INVOKABLE void stopRecording();
    Q_INVOKABLE void stopVideo();

    void init(QQuickWindow *mainWindow);
    void startVideoBackendInit();
    bool waitForVideoBackendReady(std::chrono::milliseconds timeout = std::chrono::minutes(1));
    void cleanup();
    bool autoStreamConfigured() const;
    bool decoding() const { return _decoding; }
    bool fullScreen() const { return _fullScreen; }
    bool hasThermal() const;
    bool hasVideo() const;
    bool hasVideo2() const;
    bool isStreamSource() const;
    bool isUvc() const;
    bool isUvc2() const;
    bool recording() const { return _recording; }
    bool streaming() const { return _streaming; }
    bool secondStreamDecoding() const { return _secondStreamDecoding; }
    double aspectRatio() const;
    double hfov() const;
    double thermalAspectRatio() const;
    double thermalHfov() const;
    QSize videoSize() const { return _videoSize; }
    QString imageFile() const { return _imageFile; }
    QString uvcVideoSourceID() const { return _uvcVideoSourceID; }
    QString uvcVideoSourceID2() const { return _uvcVideoSourceID2; }
    void setfullScreen(bool on);

signals:
    void aspectRatioChanged();
    void autoStreamConfiguredChanged();
    void decodingChanged();
    void fullScreenChanged();
    void hasVideoChanged();
    void hasVideo2Changed();
    void imageFileChanged(const QString &filename);
    void isAutoStreamChanged();
    void isStreamSourceChanged();
    void isUvcChanged();
    void isUvc2Changed();
    void recordingChanged(bool recording);
    void recordingStarted(const QString &filename);
    void secondStreamDecodingChanged();
    void streamingChanged();
    void uvcVideoSourceIDChanged();
    void uvcVideoSourceID2Changed();
    void videoSizeChanged();

private slots:
    void _communicationLostChanged(bool communicationLost);
    void _setActiveVehicle(Vehicle *vehicle);
    void _videoSourceChanged();

private:
    enum class InitState : uint8_t {
        NotStarted,
        Pending,
        BackendReady,
        QmlReady,
        Running,
        Failed
    };

    void _initAfterQmlIsReady();
    void _onBackendInitComplete(bool success);
    void _createVideoReceivers();
    void _initVideoReceiver(VideoReceiver *receiver, QQuickWindow *window);
    bool _updateAutoStream(VideoReceiver *receiver);
    bool _updateUVC(VideoReceiver *receiver);
    bool _updateUVC2(VideoReceiver *receiver);
    bool _updateSettings(VideoReceiver *receiver);
    bool _updateVideoUri(VideoReceiver *receiver, const QString &uri);
    bool _shouldStartReceiver(VideoReceiver *receiver) const;
    void _restartAllVideos();
    void _restartVideo(VideoReceiver *receiver);
    void _startReceiver(VideoReceiver *receiver);
    void _stopReceiver(VideoReceiver *receiver);
    static void _cleanupOldVideos();

    static bool _isPrimaryStream(const VideoReceiver *receiver);
    static bool _isSecondStream(const VideoReceiver *receiver);
    static bool _isNetworkStreamSource(const QString &videoSource);

    QList<VideoReceiver*> _videoReceivers;
    SubtitleWriter *_subtitleWriter = nullptr;
    VideoSettings *_videoSettings = nullptr;
    QQuickWindow *_mainWindow = nullptr;
    Vehicle *_activeVehicle = nullptr;

    std::atomic<InitState> _initState = InitState::NotStarted;
    // Orders _backendInitFuture publication against cross-thread waiters.
    QMutex _initFutureMutex;
    QFuture<bool> _backendInitFuture;
    bool _initialized = false;
    bool _backendDisabledForTests = false;
    bool _fullScreen = false;
    // Last notified state for change-emission and start/stop decisions in _videoSourceChanged.
    bool _lastHasVideo = true;
    bool _lastHasVideo2 = true;

    QAtomicInteger<bool> _decoding = false;
    QAtomicInteger<bool> _recording = false;
    QAtomicInteger<bool> _streaming = false;
    QAtomicInteger<bool> _secondStreamDecoding = false;
    QSize _videoSize;
    QString _imageFile;
    QString _uvcVideoSourceID;
    QString _uvcVideoSourceID2;

#ifdef QGC_UNITTEST_BUILD
    std::function<void()> _createVideoReceiversForTest;
#endif
};
