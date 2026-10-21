#!/usr/bin/env bash
# Upgrade Jetson AGX Thor from JetPack 7.0 (L4T r38.2) to 7.1 (r38.4).
# NVIDIA's supported APT path:
# https://docs.nvidia.com/jetson/agx-thor-devkit/user-guide/latest/setup_bsp.html#bsp-upgrade

set -euo pipefail
export LC_ALL=C

dry_run=0
reboot=1
usage() {
	cat <<'EOF'
Usage: sudo ./upgrade-jetpack.sh [--dry-run] [--no-reboot]

Upgrade JetPack 7.0 to 7.1 in place, keeping the existing installation.
JetPack 7.2.1 requires a different installation or image-based OTA workflow.

  --dry-run     Check target packages and simulate the upgrade using temporary
                APT metadata. Do not change repositories or installed packages.
  --no-reboot   Apply the upgrade but leave the required reboot to you.
  -h, --help    Show this help.

The upgrade backs up APT settings and the installed-package list under
/var/backups. Keep a separate backup of important data before upgrading.
EOF
}
die() {
	echo "ERROR: $*" >&2
	exit 1
}
for argument in "$@"; do
	case "$argument" in
		--dry-run) dry_run=1 ;;
		--no-reboot) reboot=0 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; die "Unknown option: $argument" ;;
	esac
done

if [ "$dry_run" -eq 0 ] && [ "$EUID" -ne 0 ]; then
	die "Run as root with sudo, or use --dry-run to preview."
fi
[[ "$(uname -m)" == aarch64 ]] || die "This upgrade is for ARM64 Jetson Thor."
[ -r /proc/device-tree/model ] || die "Cannot identify the Jetson board."
grep -aq 'Jetson AGX Thor' /proc/device-tree/model || die "Expected Jetson AGX Thor."
[ -r /etc/nv_tegra_release ] || die "Cannot read the installed L4T release."
release="$(head -n 1 /etc/nv_tegra_release)"
if [[ ! "$release" =~ ^#[[:space:]]R38[[:space:]].*REVISION:[[:space:]](2|4)\. ]]; then
	die "Supported releases are L4T r38.2.x and r38.4.x; found: $release"
fi
for command_name in apt-get apt-cache dpkg dpkg-query awk sed cp mktemp df tee flock; do
	command -v "$command_name" >/dev/null 2>&1 || die "Missing command: $command_name"
done
audit="$(dpkg --audit)"
[ -z "$audit" ] || die "Repair unfinished package operations first: $audit"
available="$(df --output=avail -B1 / | tail -n 1)"
[ "$available" -ge 16106127360 ] || die "At least 15 GiB of free space is required on /."

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/jetpack-upgrade.XXXXXX")"
backup_dir=""
repositories_changed=0
packages_started=0
source_files=()
cleanup() {
	local status=$?
	trap - EXIT
	if [ "$status" -ne 0 ] && [ -n "$backup_dir" ]; then
		if [ "$repositories_changed" -eq 1 ] && [ "$packages_started" -eq 0 ]; then
			echo "==> No package upgrade was started. Restoring repositories from $backup_dir/apt..." >&2
			for source_file in "${source_files[@]}"; do
				cp -a -- "$backup_dir/apt/sources.list.d/${source_file##*/}" "$source_file" || \
					echo "ERROR: Restore $source_file manually from the backup." >&2
			done
		fi
		echo "==> Upgrade failed. No reboot was requested. Backup and log: $backup_dir" >&2
	fi
	rm -rf -- "$work_dir"
	exit "$status"
}
trap cleanup EXIT

# Stage both traditional .list and Ubuntu's deb822 .sources formats.
mkdir -p "$work_dir/sources.list.d" "$work_dir/lists/partial" "$work_dir/archives/partial"
cp -a --no-preserve=ownership /etc/apt/sources.list.d/. "$work_dir/sources.list.d/"
if [ -f /etc/apt/sources.list ]; then
	cp -- /etc/apt/sources.list "$work_dir/sources.list"
else
	: > "$work_dir/sources.list"
fi
for source_file in /etc/apt/sources.list.d/nvidia-l4t-apt-source.{list,sources}; do
	[ -f "$source_file" ] || continue
	grep -q 'repo.download.nvidia.com/jetson/' "$source_file" || die "Unexpected NVIDIA repository file: $source_file"
	grep -Eq '(^|[[:space:]])r38\.(2|4)([[:space:]]|$)' "$source_file" || die "Unexpected repository release in $source_file"
	source_files+=("$source_file")
	sed 's/r38\.2/r38.4/g' "$source_file" > "$work_dir/sources.list.d/${source_file##*/}"
done
[ "${#source_files[@]}" -gt 0 ] || die "No NVIDIA L4T .list or .sources repository file found."

# APT update hooks can write outside its cache; disable them for the preview.
cat > "$work_dir/preview.conf" <<'EOF'
#clear APT::Update::Pre-Invoke;
#clear APT::Update::Post-Invoke;
#clear APT::Update::Post-Invoke-Success;
EOF
preview_args=(
	-c "$work_dir/preview.conf"
	-o "Dir::Etc::sourcelist=$work_dir/sources.list"
	-o "Dir::Etc::sourceparts=$work_dir/sources.list.d"
	-o "Dir::State::lists=$work_dir/lists"
	-o "Dir::Cache=$work_dir/cache"
	-o "Dir::Cache::archives=$work_dir/archives"
	-o "APT::Sandbox::User=$(id -un)"
	-o APT::Update::Error-Mode=any
)
echo "==> Checking JetPack 7.1 / L4T r38.4 package availability..."
apt-get "${preview_args[@]}" update
for package in nvidia-l4t-core nvidia-jetpack; do
	candidate="$(apt-cache "${preview_args[@]}" policy "$package" | awk '$1 == "Candidate:" { print $2 }')"
	case "$package:$candidate" in
		nvidia-l4t-core:38.4.*|nvidia-jetpack:7.1-*) ;;
		*) die "Unexpected target candidate for $package: $candidate" ;;
	esac
	echo "    $package: $candidate"
done
apt-get "${preview_args[@]}" --simulate --no-remove --with-new-pkgs upgrade
apt-get "${preview_args[@]}" --simulate --no-remove install nvidia-jetpack
if [ "$dry_run" -eq 1 ]; then
	echo "==> Preview complete. System repositories and installed packages were not changed."
	exit 0
fi

exec 9>/var/lock/upgrade-jetpack.lock
flock -n 9 || die "Another JetPack upgrade is already running."
backup_dir="$(mktemp -d /var/backups/jetpack-upgrade-7.1.XXXXXX)"
cp -a /etc/apt "$backup_dir/apt"
cp /etc/nv_tegra_release "$backup_dir/nv_tegra_release"
dpkg-query -W > "$backup_dir/packages.tsv"
exec > >(tee -a "$backup_dir/upgrade.log") 2>&1
echo "==> Configuration backup and upgrade log: $backup_dir"

if [ -x "$SCRIPT_DIR/stop.sh" ] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
	"$SCRIPT_DIR/stop.sh"
fi
repositories_changed=1
for source_file in "${source_files[@]}"; do
	# Keep the original ownership and permissions.
	cat "$work_dir/sources.list.d/${source_file##*/}" > "$source_file"
done
apt-get -o APT::Update::Error-Mode=any update
export DEBIAN_FRONTEND=noninteractive
apt_options=(-y --no-remove -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
packages_started=1
apt-get "${apt_options[@]}" --with-new-pkgs upgrade
apt-get "${apt_options[@]}" install nvidia-jetpack
[[ "$(dpkg-query -W -f='${Version}' nvidia-l4t-core)" == 38.4.* ]] || die "L4T did not reach r38.4."
[[ "$(dpkg-query -W -f='${Version}' nvidia-jetpack)" == 7.1-* ]] || die "JetPack did not reach 7.1."
echo "==> JetPack 7.1 packages installed. A reboot is required to load the updated kernel and drivers."
if [ "$reboot" -eq 1 ]; then
	sync
	systemctl reboot
else
	echo "==> Reboot when ready: sudo reboot"
fi
