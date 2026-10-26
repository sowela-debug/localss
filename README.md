# LocalSS

LocalSS is a local network communication and file-sharing
application for Windows and Android.

## Components

1. LocalSS Server
2. LocalSS Windows
3. LocalSS Android

## Features

- Local network communication
- Username/password authentication
- Private messaging
- Chat history
- Online/offline status
- Administrator management

## Technology

Server:
- Python
- FastAPI
- SQLite

Clients:
- Flutter
- Windows
- Android

## Network

LocalSS is designed to operate on a LAN without
requiring an internet connection during normal use.

## Server

Default port: 8000

The server requires the environment variable:

LOCALSS_ADMIN_PASSWORD

Set it to a strong password before starting the server.

Optionally configure:

LOCALSS_ADMIN_USERNAME

The default administrator username is admin.

## Development Status

Phase 1: Initial backend implementation.