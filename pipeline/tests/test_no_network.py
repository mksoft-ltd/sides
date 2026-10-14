"""Proof that the socket guard is active for the whole suite."""

import socket

import pytest
import pytest_socket

from sides_pipeline.fetch import http_fetch


def test_any_socket_is_blocked():
    with pytest.raises(pytest_socket.SocketBlockedError):
        socket.socket(socket.AF_INET, socket.SOCK_STREAM)


def test_real_fetcher_cannot_reach_the_network():
    with pytest.raises(pytest_socket.SocketBlockedError):
        http_fetch("https://feeds.bbci.co.uk/news/world/rss.xml")
