#!/bin/sh
# shellcheck shell=dash
# Forkop - Dependency installer for OpenWrt (supports both opkg and apk)

set -e

msg() {
    printf '\033[32;1m%s\033[0m\n' "$1"
}

warn() {
    printf '\033[33;1m%s\033[0m\n' "$1"
}

fail() {
    printf '\033[31;1m%s\033[0m\n' "$1" >&2
    exit 1
}

[ "$(id -u 2>/dev/null)" = "0" ] || fail "Пожалуйста, запустите скрипт от пользователя root"
[ -f /etc/openwrt_release ] || fail "Этот скрипт предназначен только для OpenWrt"

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

msg "==> Обновление списков пакетов..."
if [ "$PKG_IS_APK" -eq 1 ]; then
    apk update </dev/null
else
    opkg update </dev/null
fi

pkg_is_installed() {
    pkg="$1"
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk info -e "$pkg" >/dev/null 2>&1
    else
        opkg list-installed 2>/dev/null | awk -v p="$pkg" '$1 == p { found = 1 } END { exit(found ? 0 : 1) }'
    fi
}

install_pkg() {
    pkg="$1"
    if pkg_is_installed "$pkg"; then
        return 0
    fi
    msg "Установка: $pkg"
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk add "$pkg" </dev/null || warn "Пакет $pkg не найден в репозитории или встроен в ядро"
    else
        opkg install "$pkg" </dev/null || warn "Пакет $pkg не найден в репозитории или встроен в ядро"
    fi
}

msg "==> Установка основных зависимостей и библиотек ucode..."
for pkg in ucode ucode-mod-fs ucode-mod-uci curl ca-bundle bind-dig ip-full coreutils-base64 nftables; do
    install_pkg "$pkg"
done

msg "==> Установка необходимых модулей ядра Linux..."
for mod in kmod-tun kmod-nft-tproxy kmod-nft-nat kmod-inet-diag kmod-netlink-diag; do
    install_pkg "$mod"
done

msg "==> Проверка и установка модулей AmneziaWG (для WARP и кастомных AWG туннелей)..."
for awg in kmod-amneziawg amneziawg-tools; do
    install_pkg "$awg"
done

msg "==> Все зависимости успешно проверены и установлены!"
