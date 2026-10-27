#!/bin/bash
# Applies the X Mode changes to the CobaltX build tree (~/cobaltx).
# Run AFTER extracting the X Mode zip:  sudo bash ~/cobaltx/apply-xmode.sh
set -e
R="${COBALTX_DIR:-/home/${SUDO_USER:-$USER}/cobaltx}"
CFG="$R/airootfs/root/cobaltx-configs"
ok()   { echo -e "\e[32m✓\e[0m $*"; }
warn() { echo -e "\e[33m!\e[0m $*"; }

[ -f "$R/profiledef.sh" ] || { echo "Can't find $R/profiledef.sh"; exit 1; }

# 1) Installer sequence: X Mode page after Users, X Mode setup after the bootloader step
python3 - "$CFG/settings.conf" <<'PY'
import sys, shutil, yaml
path = sys.argv[1]
shutil.copy(path, path + ".bak")
data = yaml.safe_load(open(path))

inst = data.setdefault("instances", []) or []
data["instances"] = inst
for module, conf in (("packagechooser", "packagechooser-xmode.conf"),
                     ("contextualprocess", "contextualprocess-xmode.conf")):
    if not any(i.get("module") == module and i.get("id") == "xmode" for i in inst):
        inst.append({"id": "xmode", "module": module, "config": conf})

def name(x):
    return x if isinstance(x, str) else ""

shown = execd = False
for step in data["sequence"]:
    if "show" in step and "users" in step["show"] and not shown:
        lst = step["show"]
        if "packagechooser@xmode" not in lst:
            lst.insert(lst.index("users") + 1, "packagechooser@xmode")
        shown = True
    if "exec" in step and not execd:
        lst = step["exec"]
        if "contextualprocess@xmode" not in lst:
            shells = [i for i, x in enumerate(lst) if name(x).startswith("shellprocess")]
            if shells:
                pos = shells[-1] + 1
            elif "umount" in lst:
                pos = lst.index("umount")
            else:
                pos = len(lst)
            lst.insert(pos, "contextualprocess@xmode")
        execd = True
if not shown or not execd:
    sys.exit("settings.conf: could not find the 'users' page or the exec list - not changed")
yaml.safe_dump(data, open(path, "w"), sort_keys=False, default_flow_style=False)
for step in data["sequence"]:
    for k, v in step.items():
        print(f"   {k}: {', '.join(map(str, v))}")
PY
ok "Installer: X Mode page added after Users (backup: settings.conf.bak)"

# 2) Installer branding still said "CobaltX 0.1"
B="$CFG/branding/cobaltx/branding.desc"
if [ -f "$B" ]; then
    sed -i -E 's/^(\s*)(version|shortVersion):.*/\1\2: 0.3/; s/^(\s*)(versionedName|shortVersionedName):.*/\1\2: CobaltX 0.3/' "$B"
    ok "Installer branding: $(grep -E '^\s*shortVersionedName' "$B" | xargs)"
else
    warn "branding.desc not found at $B"
fi

# 3) Bootloader menu title
IB="$R/airootfs/usr/local/bin/install-bootloader.sh"
if [ -f "$IB" ]; then
    sed -i 's/^title CobaltX 0\.2 — Sparked$/title CobaltX 0.3/' "$IB"
    ok "Boot menu title: $(grep -E '^title ' "$IB")"
fi

# 4) Executable permissions for the new scripts
for f in /usr/local/bin/cobaltx-xmode /usr/local/bin/cobaltx-xmode-session \
         /usr/local/bin/cobaltx-session-select /usr/local/bin/cobaltx-xmode-installer-setup \
         /usr/local/lib/cobaltx/session-helper /usr/local/lib/cobaltx/xmode-session-apps \
         /usr/local/bin/cobaltx-keyboard /usr/local/lib/cobaltx/tdp-helper \
         /usr/local/lib/cobaltx/handheld-setup /root/cobaltx-build-hhd.sh; do
    grep -q "\"$f\"" "$R/profiledef.sh" || \
        sed -i "/^file_permissions=(/a\\  [\"$f\"]=\"0:0:755\"" "$R/profiledef.sh"
done
ok "profiledef.sh: $(grep -c 'cobaltx-xmode\|session-select\|session-helper' "$R/profiledef.sh") X Mode permission lines"

# 5) Packages: gamescope for the session, libpulse (pacat) for sounds; Qt Multimedia no longer used
P="$R/packages.x86_64"
for p in gamescope libpulse sdl2-compat python-yaml qt6-declarative qt6-svg python-evdev; do
    grep -qx "$p" "$P" || echo "$p" >> "$P"
done
sed -i '/^qt6-multimedia$/d; /^qt6-multimedia-ffmpeg$/d' "$P"
sed -i '/^goverlay$/d' "$P"          # GOverlay 1.9.4 crashes on first start - removed until fixed upstream
ok "packages.x86_64 updated (+python-evdev for the keyboard, -goverlay)"

# 6) Handheld: services + Handheld Daemon built from the AUR during the ISO build
W="$R/airootfs/etc/systemd/system"
mkdir -p "$W/multi-user.target.wants"
ln -sf /etc/systemd/system/cobaltx-handheld.service "$W/multi-user.target.wants/cobaltx-handheld.service"
ln -sf /etc/systemd/system/cobaltx-tdp.service      "$W/multi-user.target.wants/cobaltx-tdp.service"
for t in suspend hibernate hybrid-sleep suspend-then-hibernate; do
    mkdir -p "$W/$t.target.wants"
    ln -sf /etc/systemd/system/cobaltx-tdp-resume.service "$W/$t.target.wants/cobaltx-tdp-resume.service"
done
CA="$R/airootfs/root/customize_airootfs.sh"
if [ -f "$CA" ] && ! grep -q "cobaltx-build-hhd.sh" "$CA"; then
    cat >> "$CA" <<'HHD'

# CobaltX: Handheld Daemon (AUR) for handheld controls - never fails the build
bash /root/cobaltx-build-hhd.sh
rm -f /root/cobaltx-build-hhd.sh
HHD
fi
ok "Handheld: services enabled, Handheld Daemon build added to customize_airootfs.sh"
rm -rf "$R/airootfs/etc/skel/.local/share/goverlay"
rm -f "$R/airootfs/usr/share/cobaltx-xmode/__pycache__" -r

# 7) Boot menus: "Arch Linux install medium" -> CobaltX (Grub2Win/ISO-file boot, USB UEFI + BIOS)
for f in "$R"/grub/*.cfg "$R"/syslinux/*.cfg "$R"/efiboot/loader/entries/*.conf; do
    [ -f "$f" ] || continue
    sed -i 's/Arch Linux install medium with speakup screen reader/CobaltX 0.3 Live (screen reader)/g;
            s/Arch Linux install medium/CobaltX 0.3 Live/g' "$f"
done
[ -f "$R/grub/loopback.cfg" ] && sed -i 's/^timeout=15$/timeout=5/' "$R/grub/loopback.cfg"
left=$(grep -l "Arch Linux install medium" "$R"/grub/*.cfg "$R"/syslinux/*.cfg "$R"/efiboot/loader/entries/*.conf 2>/dev/null | wc -l)
ok "Boot menus renamed to CobaltX 0.3 Live (files still saying Arch: $left)"

# 8) Live user: same RetroArch defaults as new users (if the live home is prebuilt)
if [ -d "$R/airootfs/home/cobalt" ]; then
    mkdir -p "$R/airootfs/home/cobalt/.config/retroarch"
    cp "$R/airootfs/etc/skel/.config/retroarch/retroarch.cfg" "$R/airootfs/home/cobalt/.config/retroarch/"
fi
ok "RetroArch: SDL controller support + touch in menus"

# 9) Leftovers from older X Mode builds
rm -f "$R/airootfs/usr/share/cobaltx-xmode/Sounds.qml"
chown -R "${SUDO_USER:-$USER}:" "$R/airootfs/usr/share/cobaltx-xmode" "$R/airootfs/usr/share/cobaltx-welcome" 2>/dev/null || true
ok "Done. Next: rebuild the ISO"
