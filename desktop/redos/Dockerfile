# Стенд RedOS 8 для живой проверки Tauri-версии в разных окружениях рабочего стола.
# Сборка: docker build --target <mate|gnome|kde|cinnamon> -t cat-redos8-<de> desktop/redos
FROM redos-ubi8-ubi:latest AS base
RUN dnf -y install --allowerasing --setopt=install_weak_deps=False \
      gcc gcc-c++ make pkgconf rust cargo rpm-build file \
      webkit2gtk4.1-devel gtk3-devel libappindicator-gtk3-devel librsvg2-devel \
      libXtst-devel libXi-devel libX11-devel libxdo-devel openssl-devel \
      xorg-x11-server-Xvfb xorg-x11-server-Xwayland xorg-x11-server-Xorg xorg-x11-drv-dummy xrandr mesa-dri-drivers dbus-x11 \
      xdotool xclip xprop xsetroot wmctrl xdg-user-dirs procps-ng \
      ImageMagick xwd dejavu-sans-fonts google-noto-emoji-fonts glibc-langpack-ru \
    && dnf clean all && useradd -m u
ENV CARGO_HOME=/cargo LANG=ru_RU.UTF-8
WORKDIR /src/desktop

FROM base AS mate
RUN dnf -y group install --allowerasing --skip-broken --setopt=install_weak_deps=False workstation-product-environment && dnf clean all

FROM base AS gnome
RUN dnf -y group install --allowerasing --skip-broken --setopt=install_weak_deps=False gnome-desktop-environment \
    && dnf -y install --allowerasing gnome-session-xsession gnome-shell-extension-appindicator eog nautilus && dnf clean all

FROM base AS kde
RUN dnf -y group install --allowerasing --skip-broken --setopt=install_weak_deps=False kde-desktop-environment \
    && dnf -y install --allowerasing plasma-workspace-x11 kwin-x11 kwin-wayland dolphin && dnf clean all

FROM base AS cinnamon
RUN dnf -y install --allowerasing cinnamon cinnamon-session nemo && dnf clean all
