#include "TcpClient.h"

#include <QtNetwork/QTcpSocket>

TcpClient::TcpClient(QObject* parent)
    : QObject(parent)
      , _socket(new QTcpSocket(this))
{
    connect(_socket, &QTcpSocket::connected,
            this, &TcpClient::connected);

    connect(_socket, &QTcpSocket::disconnected,
            this, &TcpClient::disconnected);

    connect(_socket, &QTcpSocket::readyRead,
            this, &TcpClient::_readBytes);

    connect(_socket, &QTcpSocket::errorOccurred,
            this, [this](QAbstractSocket::SocketError) {
                emit errorOccurred(_socket->errorString());
            });
}

TcpClient::~TcpClient()
{
}

bool TcpClient::connectToServer(const QString& hostAddress, quint16 port)
{
    if (hostAddress.isEmpty()) {
        return false;
    }

    _socket->connectToHost(hostAddress, port);

    return true;
}

void TcpClient::disconnectFromServer()
{
    if (_socket) {
        _socket->disconnectFromHost();
    }
}

bool TcpClient::isConnected() const
{
    return _socket &&
           _socket->state() == QAbstractSocket::ConnectedState;
}

bool TcpClient::sendMessage(const QString& message)
{
    if (!_socket ||
        _socket->state() != QAbstractSocket::ConnectedState) {
        return false;
    }

    const QByteArray data = message.toUtf8();

    return _socket->write(data) == data.size();
}

void TcpClient::_readBytes()
{
    const QByteArray data = _socket->readAll();

    if (!data.isEmpty()) {
        emit messageReceived(QString::fromUtf8(data));
    }
}