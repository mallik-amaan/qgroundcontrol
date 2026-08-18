#include "TcpManager.h"
#include "TcpClient.h"
#include <QtNetwork/QTcpSocket>

TcpManager::TcpManager(QObject* parent)
    : QObject(parent)
      , _client(new TcpClient(this))
{
    connect(_client, &TcpClient::connected,
            this, [this]() {
                emit connected();
                emit connectedChanged();
            });

    connect(_client, &TcpClient::disconnected,
            this, [this]() {
                emit disconnected();
                emit connectedChanged();
            });


    connect(_client, &TcpClient::messageReceived,
            this, &TcpManager::messageReceived);

    connect(_client, &TcpClient::errorOccurred,
            this, &TcpManager::errorOccurred);
}

void TcpManager::connectToServer(const QString& host, quint16 port)
{
    _client->connectToServer(host, port);
}

void TcpManager::disconnectFromServer()
{
    _client->disconnectFromServer();
}

void TcpManager::sendMessage(const QString& message)
{
    _client->sendMessage(message);
}

bool TcpManager::isConnected() const
{
    return _client->isConnected();
}

