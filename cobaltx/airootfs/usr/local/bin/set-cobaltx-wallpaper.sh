#!/usr/bin/env bash
# Wait for plasma to fully load
sleep 3

# Set the wallpaper using qdbus (Plasma 6 compatible)
qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript '
var allDesktops = desktops();
for (i=0; i<allDesktops.length; i++) {
    d = allDesktops[i];
    d.wallpaperPlugin = "org.kde.image";
    d.currentConfigGroup = Array("Wallpaper", "org.kde.image", "General");
    d.writeConfig("Image", "file:///usr/share/backgrounds/cobaltx/cobaltx-wallpaper.png");
}
'

# Disable this autostart so it only runs once per session
# (optional - remove if you want it every login)
