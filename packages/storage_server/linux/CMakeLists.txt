# Linux platform configuration for storage_server
# No special permissions are required on Linux — network socket binding and
# filesystem access are controlled by standard POSIX user permissions.
# The app binds to port 8765 (HTTP) and 8766 (UDP broadcast) on all interfaces.
# Ensure the running user has read/write access to the configured storage path.

cmake_minimum_required(VERSION 3.13)

# Note: This file is a placeholder for Linux build configuration.
# The actual Flutter Linux build is managed by the Flutter toolchain.
# Run: flutter build linux
# from the storage_server package directory.
