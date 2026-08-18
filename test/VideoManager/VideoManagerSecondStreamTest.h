#pragma once

#include "UnitTest.h"

class VideoManagerSecondStreamTest : public UnitTest
{
    Q_OBJECT

private slots:
    void init() override;

    void _testStreamConfigured2();
    void _testHasVideo2();
    void _testShouldStartReceiver();
    void _testUpdateSettingsRouting();
};