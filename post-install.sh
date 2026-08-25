####################################################################################################
#
#				     Script: post-install.sh
#	Usecase: Use this script to install some tools on a freshly-installed Linux system
#
####################################################################################################

set -euo pipefail

LOG_FILE="/var/log/postinstall.log"
exec > > (tee -a "$LOG_FILE") 2>&1

echo "Départ de la post-installation"

#Vérification des droits root
if [[ $UID -ne 0 ]]; then
	echo "Ce script doit être exécuté en root." >&2
	exit 1
fi

####################################################################################################
# Déclaration des paquets

INST_BAS="aptitude sysstat apt-transport-https lsb-release ca-certificates haveged chrony"
INST_OUT="vim htop nload tmux net-tools curl rsync"
INST_SEC="ipset ipset-persistent netfilter-persistent iptables-persistent fail2ban unattended-upgrades"
INST_SHL="zsh zsh-antigen"
INST_UTILS="sssd sssd-tools realmd adcli krb5-user libpam-sss libnss-sss oddjob oddjob-mkhomedir nfs-common cifs-utils smbclient"

####################################################################################################
# Installation des paquets

echo "Installation des mises à jour"
DEBIAN_FRONTEND=noninteractive apt update && apt upgrade -y

for packs in ${!INST_*};do
	echo "Installation du groupe ${packs}: ${!packs}"
	if ! DEBIAN_FRONTEND=noninteractive apt install -y ${!packs}; then
		echo "ERREUR: échec d'installation pour le groupe ${packs}" >&2
		exit 128
	fi
done

####################################################################################################
# Nettoyage post des installations

echo "Nettoyage apt"
apt autoremove -y
apt clean

####################################################################################################
# Activation et démarrage de services

echo "Activation des services"
systemctl enable --now chrony
systemctl enable --now fail2ban

####################################################################################################
# Config du shell et des plugins Vi par utilisateurs

MIN_UID=1000
MAX_UID=65532

configure_user() {
	local user="$1"
	local home
	home=$(getent passwd "$user" | cut -d: -f6)

	echo "Configuration utilisateur ${user}" >&2
	
	if ! usermod -s /bin/zsh "${user}"; then
		echo "ERREUR : usermod a échoué pour ${user}" >&2
		return 128
	fi

	if ! runuser -l "$user" -c '
		set -euo pipefail
		if [[ ! -d "$HOME/.vim/bundle/Vundle.vim" ]]; then
			git clone https://github.com/VundleVim/Vundle.vim.git "$HOME/.vim/bundle/Vundle.vim"
		else
			echo "Vundle déjà installé"
		fi

		curl -fsSL "https://tekatux.fr/configs/sh/sh-config.tar.gz" | tar -xz -C "$HOME"

		vim +PluginInstall +qall < /dev/null || true
	
		'; then
			echo "Erreur: config utilisateur échouée pour ${user}" >&2
			return 128
		fi
	}

echo "--- Détection des utilisateurs humains (UID ${MIN_UID}-${MAX_UID}, home sous /home) ---"

mapfile -t HUMAN_USERS < <(awk -F: -v min="$MIN_UID" -v max="$MAX_UID" \
	'($3 >= min && $3 <= max && $6 ~ /^\/home\//) {print $1}' /etc/passwd)
 
if [[ ${#HUMAN_USERS[@]} -eq 0 ]]; then
	echo "Aucun utilisateur humain trouvé, config shell/vim ignorée."

else
	for u in "${HUMAN_USERS[@]}"; do
        	configure_user "$u" || echo "Config ignorée pour ${u}, on continue avec les suivants."
    	done
fi
 
echo "=== Post-install terminé : $(date '+%Y-%m-%d %H:%M:%S') ==="

