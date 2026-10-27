# shellcheck disable=SC2034

iso_name="cobaltx"
iso_label="COBALTX_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="CobaltX <https://github.com/yourname/cobaltx>"
iso_application="CobaltX Live/Install Media"
iso_version="0.3"
install_dir="cobaltx"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
file_permissions=(
  ["/root/cobaltx-build-hhd.sh"]="0:0:755"
  ["/usr/local/lib/cobaltx/handheld-setup"]="0:0:755"
  ["/usr/local/lib/cobaltx/tdp-helper"]="0:0:755"
  ["/usr/local/bin/cobaltx-keyboard"]="0:0:755"
  ["/usr/local/lib/cobaltx/xmode-session-apps"]="0:0:755"
  ["/usr/local/lib/cobaltx/session-helper"]="0:0:755"
  ["/usr/local/bin/cobaltx-xmode-installer-setup"]="0:0:755"
  ["/usr/local/bin/cobaltx-session-select"]="0:0:755"
  ["/usr/local/bin/cobaltx-xmode-session"]="0:0:755"
  ["/usr/local/bin/cobaltx-xmode"]="0:0:755"
  ["/home/cobalt/Desktop/install-cobaltx.desktop"]="0:0:755"
  ["/usr/local/bin/set-cobaltx-wallpaper.sh"]="0:0:755"
  ["/root/customize_airootfs.sh"]="0:0:755"
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/root/.gnupg"]="0:0:700"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/cobaltx-nvidia-install.sh"]="0:0:755"
  ["/usr/local/bin/cobaltx-welcome-app"]="0:0:755"
)
