#!/bin/bash
BRANCH="${BRANCH:-master}"
#DBG=x

set -e$DBG

TMPDIR="$(mktemp -d /tmp/nextcloudpi.XXXXXX || (echo "Failed to create temp dir. Exiting" >&2 ; exit 1) )"
trap "rm -rf \"${TMPDIR}\"" 0 1 2 3 15

[[ ${EUID} -ne 0 ]] && {
  printf "Must be run as root. Try 'sudo $0'\n"
  exit 1
}

export PATH="/usr/local/sbin:/usr/sbin:/sbin:${PATH}"

# check installed software
type mysqld &>/dev/null && echo ">>> WARNING: existing mysqld configuration will be changed <<<"
type mysqld &>/dev/null && mysql -e 'use nextcloud' &>/dev/null && { echo "The 'nextcloud' database already exists. Aborting"; exit 1; }

# get dependencies
apt-get update
apt-get install --no-install-recommends -y git ca-certificates sudo lsb-release wget

# get install code
if [[ "${CODE_DIR}" == "" ]]; then
  echo "Getting build code..."
  CODE_DIR="${TMPDIR}"/nextcloudpi
  git clone -b "${BRANCH}" https://github.com/nextcloud/nextcloudpi.git "${CODE_DIR}"
fi
cd "${CODE_DIR}"

# install NCP
echo -e "\nInstalling NextCloudPi..."
source etc/library.sh

# check distro
check_distro etc/ncp.cfg || {
  echo "ERROR: distro not supported:";
  cat /etc/issue
  exit 1;
}

# indicate that this will be an image build
touch /.ncp-image

mkdir -p /usr/local/etc/ncp-config.d/
cp etc/ncp-config.d/nc-nextcloud.cfg /usr/local/etc/ncp-config.d/
cp etc/library.sh /usr/local/etc/
cp etc/ncp.cfg /usr/local/etc/

cp -r etc/ncp-templates /usr/local/etc/
install_app    lamp.sh
install_app    bin/ncp/CONFIG/nc-nextcloud.sh
run_app_unsafe bin/ncp/CONFIG/nc-nextcloud.sh
rm /usr/local/etc/ncp-config.d/nc-nextcloud.cfg    # armbian overlay is ro
systemctl restart mysqld # TODO this shouldn't be necessary, but somehow it's needed in Debian 9.6. Fixme
install_app    ncp.sh
run_app_unsafe bin/ncp/CONFIG/nc-init.sh
echo 'Moving data directory to a more sensible location'
df -h
mkdir -p /opt/ncdata
[[ -f "/usr/local/etc/ncp-config.d/nc-datadir.cfg" ]] || {
  should_rm_datadir_cfg=true
  cp etc/ncp-config.d/nc-datadir.cfg /usr/local/etc/ncp-config.d/nc-datadir.cfg
}
DISABLE_FS_CHECK=1 NCPCFG="/usr/local/etc/ncp.cfg" run_app_unsafe bin/ncp/CONFIG/nc-datadir.sh
[[ -z "$should_rm_datadir_cfg" ]] || rm /usr/local/etc/ncp-config.d/nc-datadir.cfg
rm /.ncp-image

# skip on Armbian / Vagrant / LXD ...
[[ "${CODE_DIR}" != "" ]] || bash /usr/local/bin/ncp-provisioning.sh

cd -
rm -rf "${TMPDIR}"

IP="$(get_ip)"

echo "Done.

First: Visit https://$IP/  https://nextcloudpi.local/ (also https://nextcloudpi.lan/ or https://nextcloudpi/ on windows and mac)
to activate your instance of NC, and save the auto generated passwords. You may review or reset them
anytime by using nc-admin and nc-passwd.
Second: Type 'sudo ncp-config' to further configure NCP, or access ncp-web on https://$IP:4443/
Note: You will have to add an exception, to bypass your browser warning when you
first load the activation and :4443 pages. You can run letsencrypt to get rid of
the warning if you have a (sub)domain available.
"