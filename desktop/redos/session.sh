#!/bin/bash
# Сессия рабочего стола в контейнере от имени пользователя u.
# DE=mate|gnome|gnome-wayland|kde|kde-wayland|cinnamon, SCREENS=1|2 (два монитора RandR рядом).
# Wayland-сессии запускаются вложенными в Xvfb, чтобы снимать экран и слать ввод через xdotool.
DE=${DE:-mate}
# Системная шина нужна GNOME (accountsservice) и KDE.
mkdir -p /run/dbus && dbus-daemon --system --fork
mkdir -p /run/user/1000 && chown u: /run/user/1000 && chmod 700 /run/user/1000
# Xvfb от имени u: иначе Mesa во вложенном композиторе не подключает SHM-сегменты к серверу root.
if [ "${SCREENS:-1}" = 2 ]; then
  # Два монитора: Xvfb умеет только один RandR-выход, поэтому Xorg с драйвером dummy.
  Xorg :99 -config /redos/dummy.conf -noreset -nolisten tcp -logfile /tmp/xorg.log >/dev/null 2>&1 &
  until DISPLAY=:99 xdpyinfo >/dev/null 2>&1; do sleep 0.2; done
  export DISPLAY=:99
  xrandr --newmode 1280x800 83.50 1280 1352 1480 1680 800 803 809 831 -hsync +vsync
  xrandr --addmode DUMMY0 1280x800; xrandr --addmode DUMMY1 1280x800
  xrandr --output DUMMY0 --mode 1280x800 --pos 0x0 --primary --output DUMMY1 --mode 1280x800 --pos 1280x0
  chmod 666 /tmp/.X11-unix/X99
else
  su u -c "Xvfb :99 -screen 0 1280x800x24 -nolisten tcp" >/tmp/xvfb.log 2>&1 &
fi
sleep 1
# Как в настоящей сессии: тип и имя рабочего стола видны D-Bus-активации (по ним выбирается бэкенд портала).
case $DE in mate) CUR=MATE ;; gnome*) CUR=GNOME ;; kde*) CUR=KDE ;; cinnamon) CUR=X-Cinnamon ;; esac
case $DE in *wayland) TYPE=wayland ;; *) TYPE=x11 ;; esac
cat > /tmp/de.sh <<IN
export DISPLAY=:99 LANG=ru_RU.UTF-8 XDG_RUNTIME_DIR=/run/user/1000 XDG_CURRENT_DESKTOP=$CUR XDG_SESSION_TYPE=$TYPE
xdg-user-dirs-update
eval "\$(dbus-launch --sh-syntax)"
echo "export DBUS_SESSION_BUS_ADDRESS=\$DBUS_SESSION_BUS_ADDRESS DISPLAY=:99 LANG=ru_RU.UTF-8 XDG_RUNTIME_DIR=/run/user/1000 XDG_CURRENT_DESKTOP=$CUR XDG_SESSION_TYPE=$TYPE" > /tmp/env.sh
xsetroot -solid '#3a6ea5'
APPIND="['appindicatorsupport@rgcjonas.gmail.com']"
case $DE in
  mate)     XDG_CURRENT_DESKTOP=MATE XDG_SESSION_TYPE=x11 exec mate-session ;;
  gnome)    gsettings set org.gnome.shell enabled-extensions "\$APPIND"
            XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=x11 exec gnome-shell --x11 ;;
  gnome-wayland)
            gsettings set org.gnome.shell enabled-extensions "\$APPIND"
            echo "export WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland APP_DISPLAY=:0" >> /tmp/env.sh
            XDG_CURRENT_DESKTOP=GNOME XDG_SESSION_TYPE=wayland MUTTER_DEBUG_DUMMY_MODE_SPECS=1280x760 \
              exec gnome-shell --nested --wayland --wayland-display=wayland-0 ;;
  kde)      XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=x11 exec startplasma-x11 ;;
  kde-wayland)
            echo "export WAYLAND_DISPLAY=wayland-0 XDG_SESSION_TYPE=wayland APP_DISPLAY=:0" >> /tmp/env.sh
            XDG_CURRENT_DESKTOP=KDE XDG_SESSION_TYPE=wayland exec kwin_wayland --width 1280 --height 760 \
              --socket wayland-0 --xwayland plasmashell ;;
  cinnamon) XDG_CURRENT_DESKTOP=X-Cinnamon XDG_SESSION_TYPE=x11 exec cinnamon-session ;;
esac
IN
chmod 755 /tmp/de.sh
su - u -c 'bash /tmp/de.sh >/tmp/session.log 2>&1 &'
sleep infinity
