# Forkop

[![Releases](https://img.shields.io/github/v/release/rock12/forkop?label=Release&color=blue)](https://github.com/rock12/forkop/releases)
[![OpenWrt](https://img.shields.io/badge/OpenWrt-24.10%20%7C%2025.x-blue?logo=openwrt&logoColor=white)](https://openwrt.org/)
[![License](https://img.shields.io/badge/License-GPL--2.0-green.svg)](LICENSE)

**Forkop** — универсальный комбайн маршрутизации и обхода сетевых блокировок для роутеров под управлением **OpenWrt** (24.10, 25.x и новее). Построен на базе ядра **sing-box**, модульной архитектуры **ucode** и современного реактивного веб-интерфейса **LuCI**.

---

## ✨ Ключевые возможности

### 🚀 Поддерживаемые протоколы и туннели
* **VLESS Reality & Vision:** современная маскировка трафика под легитимный TLS без собственного домена.
* **Hysteria 2:** скоростной UDP-протокол на базе модифицированного QUIC для сетей с высокими потерями.
* **xHTTP (sing-box extended):** потоковая передача через HTTP/2 и HTTP/3.
* **AmneziaWG (AWG):** обфусцированный WireGuard. Включает автоматическую генерацию Cloudflare WARP и поддержку кастомных префиксов рукопожатия (`WARP_QUIC_I1` и др.) для надёжного обхода фильтрации ТСПУ.
* **Mieru:** протокол с маскировкой под случайный трафик и защитой от активного зондирования.
* **UDPspeeder:** прямое дублирование пакетов (FEC) для стабилизации высоконагруженных UDP-соединений и игр на нестабильных каналах.
* **Shadowsocks, ShadowTLS, TUIC, стандартный WireGuard.**

### 🛡️ Интеграция локальных утилит обхода DPI
* **Zapret (nfqws)** и **Zapret2 (nfqws2):** гибкая фрагментация TCP-пакетов, fake-запросы и подмена TTL.
* **ByeDPI (ciadpi):** локальный SOCKS-прокси с расщеплением TCP-потоков.
* Поддержка одновременной гибридной работы (маршрутизация sing-box + DPI-утилиты для выбранных ресурсов).

### 📋 Менеджер подписок
* Поддержка подписок в форматах **Base64, Clash, sing-box JSON, V2Ray**.
* Встроенная поддержка привязки устройств **Remnawave X-HWID** (корректная работа с сервисами вроде Matryoshka VPN и др.).
* Автоматическое обновление по расписанию, проверка доступности и пинга, сортировка по задержке.

### 🌐 Современный веб-интерфейс LuCI
* Интерактивный **Dashboard** с измерением задержки серверов в реальном времени.
* Ручное переключение активных узлов прямо из веб-интерфейса через Clash API.
* Встроенная диагностика, журналы логов, проверка сетевых интерфейсов и правил NFTables.
* Полная локализация на русский и английский языки.

---

## 📥 Быстрая установка

Подключитесь к роутеру по SSH под пользователем `root` и выполните одну команду:

### Способ 1: Через `wget` (по умолчанию в OpenWrt)
```sh
sh <(wget -O - https://raw.githubusercontent.com/rock12/forkop/main/install.sh)
```

### Способ 2: Через `curl`
```sh
sh <(curl -fsSL https://raw.githubusercontent.com/rock12/forkop/main/install.sh)
```

Скрипт установки автоматически:
1. Определит архитектуру процессора и версию OpenWrt.
2. Обновит репозитории (`apk update` или `opkg update`).
3. Установит все необходимые системные зависимости и модули ядра.
4. Загрузит свежие пакеты `forkop`, `luci-app-forkop`, `luci-i18n-forkop-ru` из последнего релиза на GitHub.
5. Предложит установить подходящую сборку **sing-box** (`stable` из официального фида или `extended` для поддержки xHTTP).
6. Запустит службу и очистит кэш LuCI.

---

## 🔧 Установка только зависимостей

Если вы собираете пакеты вручную или хотите заранее подготовить систему роутера:
```sh
sh <(wget -O - https://raw.githubusercontent.com/rock12/forkop/main/install-deps.sh)
```

### Список устанавливаемых зависимостей:
* **Среда выполнения и утилиты:** `ucode`, `ucode-mod-fs`, `ucode-mod-uci`, `curl`, `ca-bundle`, `bind-dig`, `ip-full`, `coreutils-base64`, `nftables`.
* **Модули ядра Linux:** `kmod-tun`, `kmod-nft-tproxy`, `kmod-nft-nat`, `kmod-inet-diag`, `kmod-netlink-diag`.
* **Дополнительно для AmneziaWG:** `kmod-amneziawg`, `amneziawg-tools`.

---

## 📦 Ручная установка из GitHub Releases

Вы можете скачать готовые пакеты со страницы [Releases](https://github.com/rock12/forkop/releases):

### Для OpenWrt с пакетным менеджером `apk` (25.x / 24.10):
```sh
apk add --allow-untrusted forkop_<версия>.apk
apk add --allow-untrusted luci-app-forkop_<версия>.apk
apk add --allow-untrusted luci-i18n-forkop-ru_<версия>.apk
```

### Для OpenWrt с пакетным менеджером `opkg`:
```sh
opkg install --force-overwrite forkop_<версия>.ipk
opkg install --force-overwrite luci-app-forkop_<версия>.ipk
opkg install --force-overwrite luci-i18n-forkop-ru_<версия>.ipk
```

После установки обновите кэш LuCI и перезапустите rpcd:
```sh
rm -f /tmp/luci-indexcache* /var/luci-indexcache*
/etc/init.d/rpcd reload
```

---

## ⚙️ Системные требования

* **OpenWrt:** 24.10, 25.12 или новее.
* **Архитектура:** Любая поддерживаемая OpenWrt (`aarch64_cortex-a53`, `mips_24kc`, `x86_64`, `arm_cortex-a7` и др.).
* **Свободное место во flash-памяти:** не менее 15 МБ (рекомендуется роутер с 128+ МБ Flash или extroot).

---

## 📄 Лицензия

Распространяется под лицензией **GPL-2.0-or-later**.
