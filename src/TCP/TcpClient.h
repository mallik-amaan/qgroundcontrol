#ifndef TCPCLIENT_H
#define TCPCLIENT_H


#pragma once

#include <QtCore/QObject>
#include <QtCore/QString>

class QTcpSocket;

class TcpClient : public QObject
{
  Q_OBJECT

public:
  explicit TcpClient(QObject* parent = nullptr);
    ~TcpClient() override;


    bool connectToServer(const QString& hostAddress, quint16 port);
    void disconnectFromServer();

    bool sendMessage(const QString& message);
    bool isConnected() const;

signals:
    void connected();
    void disconnected();
    void messageReceived(const QString& message);
    void errorOccurred(const QString& error);


private slots:
    void _readBytes();


private:

    QTcpSocket* _socket = nullptr;

};



#endif  // TCPCLIENT_H


