#pragma once

#ifndef TCPMANAGER_H
#define TCPMANAGER_H

#include <QtCore/QObject>

class TcpClient;

class TcpManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ isConnected NOTIFY connectedChanged)

public:
    explicit TcpManager(QObject* parent = nullptr);

    Q_INVOKABLE void connectToServer(const QString& host, quint16 port);
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void sendMessage(const QString& message);


    bool isConnected() const;

signals:
    void connected();
    void disconnected();
    void messageReceived(const QString& message);
    void errorOccurred(const QString& error);
    void connectedChanged();

private:
    TcpClient* _client = nullptr;

};



#endif  // TCPMANAGER_H
