#!/bin/bash

#KlipperScreen

XSERVER="xserver-xorg xinput xserver-xorg-input-evdev xserver-xorg-input-libinput xserver-xorg-xwayland xserver-xorg-video-fbdev"
CAGE="cage seatd xserver-xorg-xwayland"
PYGOBJECT="gobject-introspection cairo pkgconfig python3 gtk+3"
MISC="librsvg openjpeg dbus-glib autoconf python3"
OPTIONAL="mpv fonts-nanum fonts-ipafont"

export XSERVER CAGE PYGOBJECT MISC OPTIONAL

$HOME/kiauh/kiauh.sh
