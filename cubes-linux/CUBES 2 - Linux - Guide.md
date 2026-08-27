# 2- CUBES 2 Sujet 2 : Serveurs Linux

# Plan d’infra réseau

Pour notre infrastructure de projet, on aura plusieurs VM :

- Un serveur DHCP & DNS (`SRV-NET01` )
- Un serveur DNS secondaire (`SRV-NET02` )
- Un serveur WEB (apache) et de partage de fichiers (`SRV-WEB01` )
- Un OPNSense pour gérer le réseau interne
- Un client Debian avec interface graphique (Lxqt)
- Un client Windows 11 Pro N

Concernant les adresses IP, ont été retenues :

- `SRV-NET01` ⇒ 192.168.0.200
- `SRV-NET02` ⇒ 192.168.0.201
- `SRV-WEB` ⇒ 192.168.0.202
- `OPNSENSE` ⇒ 192.168.0.254

Pour faciliter l’administration (et l’accès en ssh), des règles de DNAT seront érigées sur l'OPNSense, avec les paramètres :

- port 2222 → `SRV-NET01:22`
- port 2223 → `SRV-NET02:22`
- port 2224 → `SRV-WEB01:22`

# MEP des VM

## A/ `SRV-NET01`

Pour notre serveur NET01 (DHCP + DNS), on commence par configurer de manière classique un Debian sans environnement de bureau.

On appelle notre machine `srv-net01` dans le domaine `isec.local` .

Concernant les partitions, on sépare sur le disque de 20Go :

- `/boot` : 1Go
- `/` : 8Go
- `/var` : 5Go
- `/var/log` : 5Go
- `swap` : 1Go

Ensuite, on met une ip fixe sur notre serveur dans `/etc/network/interfaces` , pour la suite on passera la VM en `vmnet2` avec notre OPNSense du cours Linux en RTR.

On peut aussi mettre notre dns externe pour l’instant avec `/etc/resolv.conf` 
Ce DNS doit être l'adresse IP de l'ordinateur portable dans le NAT VMWare

### 1. Serveur DHCP kea

On installe ensuite les paquets `kea` et `kea-doc` pour gérer notre DHCP. Le fichier de config a déjà été modifié pour les besoins du projet.

Pour télécharger le fichier de config kea depuis le github, taper sur le serveur depuis `~` :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net01/kea-dhcp4.conf
sudo cp kea-dhcp4.conf /etc/kea/ 
```

Editer le fichier pour vérifier que rien n'est à changer

### 2. Serveur DNS primaire

Une fois notre serveur DHCP installé, on passe au DNS. Pour cela, on installe les paquets nécessaires :

```bash
╰─➤  sudo apt update && sudo apt install bind9{,utils,-doc,-dnsutils}
```

**Zone de recherche DNS directe** 

On peut utiliser le fichier de configuration depuis qui contient également la zone inversée et les paramètres de renvoi vers le deuxième serveur à placer dans `/etc/bind/named.conf.local` :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net01/named.conf.local
sudo cp named.conf.local /etc/bind/ 
```

Editer le fichier pour vérifier que rien n'est à changer, il faut notamment changer le forwarder vers le forwarder sur le réseau NAT VMWare

Avant d'utiliser le fichier de configuration dispo en faisant :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net01/named.conf.options
sudo cp named.conf.options /etc/bind/ 
```

Editer le fichier pour vérifier que rien n'est à changer

On créée ensuite le fichier de zone directe dans `/etc/bind/db.isec.local` :

Ce fichier est dispo en faisant :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net01/db.isec.local
sudo cp db.isec.local /var/lib/bind/ 
```

Editer le fichier pour vérifier que rien n'est à changer

On a déjà rajouté nos enregistrements CNAME pour `intra.isec.local` et `glpi.isec.local`.

**Zone de recherche DNS inversée**

Une fois que notre de recherche directe est OK, on peut passer à notre zone de recherche inversée.
On a déjà ajouté dans le fichier `/etc/bind/named.conf.local` notre déclaration de zone, on peut donc directement passer à la création du fichier de zone dans `/var/lib/bind`.

Comme toujours, le fichier est dans :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net01/db.192.168.0
sudo cp db.192.168.0 /var/lib/bind/
```

Editer le fichier pour vérifier que rien n'est à changer

**Configuration du DDNS**

On commence par stopper les services DNS `sudo systemctl stop named bind9`.
On doit bien avoir nos fichiers de zone dans `/var/lib/bind`.

Ensuite on génère une clef `tsig` pour chiffrer le DDNS :
```bash
sudo tsig-keygen dhcp-ns >dhcp-ns.key #sur le serveur DHCP
```

Ensuite on la copie et sécurise :
``` bash
sudo cp dhcp-ns.key /etc/bind
sudo chown root:bind /etc/bind/dhcp-ns.key
sudo chmod 640 /etc/bind/dhcp-ns.key
```

Ensuite redémarrer les services `bind9` et `named`.

Après cela on installe le paquet `kea-dhcp-ddns-server` s'il n'a pas déjà été installé.
On lui donne la clef créée précédemment en faisant :

```bash
cp dhcp-ns.key tsig-keys.json
```

Et on la formate de cette manière :

```bash
"tsig-keys": [
        {
                "name": "dhcp-ns",
                "algorithm":  "hmac-sha256",
                "secret": "SECRET"
        }
],
```

La partie SECRET doit être le contenu de la clef créée à l'instant (visible en faisant `cat dhcp-ns.key`

**Attention :** vi peut cacher les guillemets en json, il faut peut-être les rajouter pour que le fichier fonctionne (visible si des mots sont surlignés en rouge = erreur).

Ensuite, on récupère le fichier de configuration ddns avec :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net01/kea-dhcp-ddns.conf
sudo cp tsig-keys.json kea-dhcp-ddns.conf /etc/kea
```

Puis, on change les autorisations pour éviter les problèmes :

```bash
sudo chown _kea:root /etc/kea/{tsig-keys.json,kea-dhcp-ddns.conf}
sudo chmod 640 /etc/kea/{tsig-keys.json,kea-dhcp-ddns.conf}
sudo -u _kea kea-dhcp-ddns -t /etc/kea/kea-dhcp-ddns.conf #Sensé renvoyer "Configuration check successful" à la fin
```

Enfin, on redémarre tous nos services :

```bash
sudo systemctl restart named bind9 kea-dhcp4-server kea-dhcp-ddns-server
```

**Configuration finale**

Une fois que cette config est prête, on peut changer notre NS dans `/etc/resolv.conf`  :

```bash
nameserver 127.0.0.1
nameserver 192.168.0.201
search isec.local
```

Ensuite, on fait ces commandes pour vérifier et activer la config :

```bash
sudo named-checkconf #Vérifie la configuration DNS et indique les erreurs
sudo named-checkzone isec.local /var/lib/bind/db.isec.local #Pareil pour la zone directe
sudo named-checkzone 0.168.192.in-addr.arpa /var/lib/bind/db.192.168.0 #Pareil pour la zone inversée
sudo systemctl restart bind9 #Toujours restart la config ensuite
```

Ensuite, on peut tester depuis le client pour voir si cela fonctionne avec `nslookup` .

## B/ `SRV-NET02`

On peut maintenant passer à notre serveur réseau secondaire `srv-net02` , on le configure avec les mêmes paramètres que le premier et avec comme adresse `192.168.0.201` .

### Serveur DNS secondaire

On installe les mêmes paquets que sur `srv-net01` :

```bash
sudo apt update && sudo apt install bind9{,utils,-doc,-dnsutils}
```

On déclare à nouveau nos zones dans `/etc/bind/named.conf.local` avec un fichier différent du DNS primaire. Ce fichier est disponible en faisant :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net02/named.conf.local
sudo cp named.conf.local /etc/bind/named.conf.local
```

Editer le fichier pour vérifier que rien n'est à changer

Mêmes options que sur le primaire, dans `/etc/bind/named.conf.options` :

```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-net02/named.conf.options
sudo cp named.conf.options /etc/bind/named.conf.options
```

Editer le fichier pour vérifier que rien n'est à changer. Modifier les forwarders comme pour le premier

Ici, les fichiers de zone ne seront pas nécessaires car seront transférés via `srv-net01`

On met à jour `/etc/resolv.conf` :

```bash
nameserver 127.0.0.1
nameserver 192.168.0.200
search isec.local
```

Activation et vérification du transfert :

```bash
sudo named-checkconf
sudo systemctl restart bind9
sudo systemctl enable bind9

ls -l /var/cache/bind/db.isec.local /var/cache/bind/db.192.168.0 #doivent exister une fois le transfert fait
```

Test depuis le client :

```bash
dig @192.168.0.201 intra.isec.local
dig -x 192.168.0.200 @192.168.0.201
```

**Attention** : le transfert de zone (AXFR) se fait en TCP sur le port 53, contrairement aux requêtes DNS classiques en UDP — si le transfert échoue silencieusement (fichiers absents de `/var/cache/bind/`), vérifier qu'un éventuel pare-feu sur `srv-net01` autorise bien le 53/TCP vers `.201`.

## C/ `SRV-WEB01`

Pour la configuration du serveur web, on installe Apache pour héberger nos deux sites statiques `intra.isec.local` et `glpi.isec.local`, puis on met en place l’accès aux dossiers web via trois protocoles : SMB, NFS et FTP.

### Apache — sites statiques

```bash
sudo apt update
sudo apt install apache2
sudo mkdir -p /var/www/intra.isec.local /var/www/glpi.isec.local
wget -P /var/www/intra.isec.local/ https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-web01/intra.isec.local/index.html
wget -P /var/www/glpi.isec.local/ https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-web01/glpi.isec.local/index.html
```

On déclare ensuite les deux vhosts dans `/etc/apache2/sites-available/` :

```bash
sudo wget -P /etc/apache2/sites-available/ https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-web01/{glpi,intra}.isec.local.conf
```

Normalement ces fichiers n'ont pas besoins d'être modifiés.

Ensuite on active nos sites et désactive le site par défaut d'Apache :

```bash
sudo a2ensite intra.isec.local glpi.isec.local
sudo a2dissite 000-default
sudo systemctl reload apache2
```

### Utilisateurs partagés

On réutilise le même jeu de comptes pour les 3 protocoles (SMB/NFS/FTP), dans le groupe `webdev`, avec les UID fixés selon le pattern défini plus bas (section NFS) :

```bash
sudo groupadd webdev
sudo useradd -M -d /var/www -s /usr/sbin/nologin -u 1010 -G webdev ulrichl
sudo useradd -M -d /var/www -s /usr/sbin/nologin -u 1011 -G webdev rosea
sudo useradd -M -d /var/www -s /usr/sbin/nologin -u 1012 -G webdev grohld

sudo chgrp -R webdev /var/www
sudo chmod -R 2775 /var/www #setgid, les nouveaux fichiers héritent du groupe webdev
```

### SMB (Samba)

```bash
sudo apt install samba smbclient #smbclient nécessaire côté client aussi
sudo smbpasswd -a ulrichl
sudo smbpasswd -a rosea
sudo smbpasswd -a grohld
```

Pour Samba, on utilise le fichier de configuration suivant :


```bash
wget https://raw.githubusercontent.com/luca-segatti/linux-scripts-tips/refs/heads/main/cubes-linux/srv-web01/smb.conf
sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.sav
sudo cp smb.conf /etc/samba/smb.conf
```


```bash
sudo testparm #vérifie la syntaxe avant de relancer
sudo systemctl restart smbd nmbd
```

Accès depuis un client : `\\isec.local\web` (Windows) ou `smbclient //isec.local/web -U ulrichl` (Linux).

### NFS

```bash
sudo apt install nfs-kernel-server
```

Dans `/etc/exports` :

```bash
/var/www   192.168.0.0/24(rw,sync,no_subtree_check)
```

```bash
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
```

**Attention** : NFSv3 ne fait pas d’authentification, seulement de l’autorisation basée sur l’UID envoyé par le client — n’importe quel utilisateur avec le même UID (sur n’importe quelle machine) obtient les mêmes droits, sans mot de passe demandé.

Pour NFS, les permissions par défaut se basent sur l’UID des utilisateurs, et non pas sur leurs identifiants.

Il faut donc que l’UID sur le serveur soit corrélé avec celui du client pour que le partage fonctionne.

On a donc créé nos utilisateurs dans un groupe `webdev` avec la commande `useradd` .

Si cela n’a pas été fait sur le coup, on modifie leurs UID pour aller selon ce pattern (qu’on respectera sur le client Linux) :

- `1000 : ls`
- `1010 : ulrichl` au lieu de 1001
- `1011 : rosea` au lieu de 1002
- `1012 : grohld` au lieu de 1003

On le modifie avec la commande :

```bash
sudo usermod -u 1010 ulrichl #par exemple
find / -user <ANCIEN_UID> -exec chown -h <USERNAME> {} \; 
#Permet de réattribuer les fichiers de l'ancien UID vers le nouveau
```

### FTP (vsftpd)

```bash
sudo apt install vsftpd
```

Dans `/etc/vsftpd.conf` :

```bash
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
local_umask=002
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
```

```bash
printf "ulrichl\nrosea\ngrohld\n" | sudo tee /etc/vsftpd.userlist
sudo systemctl restart vsftpd
```

`userlist_deny=NO` + le fichier = seuls ces 3 comptes peuvent se connecter (liste blanche), tous les autres comptes système sont bloqués.

**Points de blocage rencontrés (530 Login incorrect malgré bon mot de passe) :**

- PAM (`pam_shells.so`) exige que le shell du compte figure dans `/etc/shells`, sinon échec après saisie du mot de passe :

```bash
echo "/usr/sbin/nologin" | sudo tee -a /etc/shells
sudo systemctl restart vsftpd
```

## D/ Client de test

Côté client Debian (LXQt), plusieurs points bloquants rencontrés lors des tests SMB/NFS/FTP — à réappliquer si le même souci se reproduit.

### Outils clients manquants

Les paquets serveur n'installent pas les outils clients correspondants :

```bash
sudo apt install smbclient ftp
```

### Résolution DNS — `isec.local` ne se résout pas

Deux causes rencontrées, cumulatives :

1. **Enregistrement manquant pour le nom nu du domaine.** `\\isec.local\web` demande de résoudre `isec.local` seul (l'apex de la zone), absent de `db.isec.local`. Ajouté :

```bash
@               IN      A       192.168.0.202
```

(ne pas oublier d'incrémenter le Serial du SOA à chaque modif de zone)

1. **`.local` est réservé pour mDNS (RFC 6762).** Sur le client, `/etc/nsswitch.conf` contenait :

```bash
hosts:          files mdns4_minimal [NOTFOUND=return] dns
```

Le `[NOTFOUND=return]` empêche NSS de retomber sur `dns` si Avahi (mDNS) ne trouve rien — ce qui est toujours le cas ici. `nslookup`/`dig` fonctionnent quand même car ils tapent le DNS directement, sans passer par NSS — d'où la confusion (ça marche en `nslookup`, pas dans les vraies applis). Corrigé en réordonnant :

```bash
hosts:          files dns mdns4_minimal [NOTFOUND=return]
```

Ce souci touchera **tout** client Linux avec Avahi installé (donc par défaut sur la plupart des postes desktop) — à mentionner dans le rapport comme limite connue de `.local` en interne, pas un choix remis en cause (imposé par le sujet).

### Montage NFS côté client

```bash
sudo mkdir -p /mnt/web
sudo mount -t nfs isec.local:/var/www /mnt/web
```

⚠️ NFS exporte un chemin filesystem (`/var/www`), pas un nom de partage type SMB — ne pas confondre avec `/web` (nom du partage Samba).

Pour que les droits soient corrects, créer les comptes utilisateurs sur le client avec **les mêmes UID que sur le serveur** :

```bash
sudo useradd -m -u 1010 ulrichl
sudo useradd -m -u 1011 rosea
sudo useradd -m -u 1012 grohld
```

(`-m` ici, contrairement au serveur en `-M` : ces comptes ouvrent une vraie session sur le client)

Vérifier les UID des deux côtés en cas de doute :

```bash
id ulrichl
grep ulrichl /etc/passwd
```

## E/ Durcissement SSH & OPNsense

### Génération et déploiement de la clé

```bash
ssh-keygen -t ed25519 -C "admin@isec.local"
```

`ed25519` plutôt que RSA : plus court, plus rapide, tout aussi sûr.

⚠️ Si le fichier de clé n'a pas un nom standard (`id_ed25519`...), `ssh-copy-id` ne le trouve pas tout seul ("No identities found") — préciser `-i` explicitement :

```bash
ssh-copy-id -i ~/.ssh/isec.pub -p 2222 ls@192.168.1.131   # SRV-NET01
ssh-copy-id -i ~/.ssh/isec.pub -p 2223 ls@192.168.1.131   # SRV-NET02
ssh-copy-id -i ~/.ssh/isec.pub -p 2224 ls@192.168.1.131   # SRV-WEB01
```

### Durcissement `/etc/ssh/sshd_config` (sur les 3 serveurs)

```bash
Protocol 2
PubkeyAuthentication yes
PasswordAuthentication no
PermitRootLogin no
```

**⚠️ Ne pas redémarrer `sshd` avant d'avoir testé la connexion par clé dans un second terminal** (garder la session actuelle ouverte comme filet de sécurité). Une fois confirmé :

```bash
sudo systemctl restart sshd
```

Note : `PasswordAuthentication no` ne s'applique qu'à `sshd` (connexions réseau). La console VMware (accès direct, hors SSH) reste utilisable avec le mot de passe du compte — c'est le filet de sécurité en cas de mauvaise manip sur le déploiement de clé.

### Config pratique côté client (`~/.ssh/config`)

```bash
Host srv-net01
    HostName 192.168.1.131
    Port 2222
    User ls
    IdentityFile ~/.ssh/isec

Host srv-net02
    HostName 192.168.1.131
    Port 2223
    User ls
    IdentityFile ~/.ssh/isec

Host srv-web01
    HostName 192.168.1.131
    Port 2224
    User ls
    IdentityFile ~/.ssh/isec
```

Permet ensuite `ssh srv-net01` sans répéter port/clé à chaque fois.

# Modifications

Dans l’aboslu, on oublie FTP et FTPS et on utilise SFTP

On va donc créer une configuration FTP mais ne pas la lancer au démarrage.

On mettra aussi SFTP (qui lui se lance au démarrage) car les clients sont tous compatibles et c’est le seul de tous qui est sécurisé.

Ensuite Samba + NFS

Encore une fois, les droits sur les fichiers sont ceux du FS, avec Samba c’est ceux des comptes Samba.

`TDBSAM` est le backend qui remplace `smbpasswd` depuis SMB4, et il s’utilise avec la commande `pdbedit` qui s’utilise de la même façon que `smbpasswd`

Pour rajouter une clef autorisée pour le ssh et concaténer dans .ssh/authorized_keys avec par exemple `tee -a` 

Pour ajouter nos vhosts dans le DNS, il faut freeze le DNS dynamique si présent.

Mettre en place un DDNS

## Désactivation de ftp et mise en place de sftp

### Le principe

On veut que `ulrichl`/`rosea`/`grohld` gardent un accès en lecture/écriture sur leurs dossiers, mais **uniquement via SFTP**, sans shell complet ni accès aux autres parties du serveur. OpenSSH gère ça nativement avec un `ChrootDirectory` + `ForceCommand internal-sftp`, réservé à ces comptes précis (l'admin `ls` garde son accès SSH normal, inchangé).

### 1. Désactiver vsftpd

bash

```bash
sudo systemctl disable --now vsftpd
sudo systemctl mask vsftpd   # empêche un démarrage accidentel (dépendance, reboot...)
```

### 2. Vérifier que le sous-système SFTP est bien déclaré

Normalement déjà présent par défaut sur Debian :

bash

```bash
grep -i subsystem /etc/ssh/sshd_config
```

Tu dois voir :

```
Subsystem sftp /usr/lib/openssh/sftp-server
```

Si absent, ajoute-le.

### 3. ⚠️ Corriger les permissions de `/var/www` — point bloquant sinon

OpenSSH exige que le dossier utilisé comme `ChrootDirectory` (et tous ses parents) appartienne à **root** et ne soit pas modifiable par le groupe/autres — sinon il refuse carrément la connexion (`fatal: bad ownership or modes`). Or on avait fait un `chmod -R 2775 /var/www` qui rend `/var/www` lui-même group-writable. Il faut corriger **juste ce dossier racine**, pas ses sous-dossiers :

bash

```bash
sudo chown root:root /var/wwwsudo chmod 755 /var/www
```

Les sous-dossiers `intra.isec.local` et `glpi.isec.local` gardent leurs droits `webdev`/`2775` actuels — c'est **à l'intérieur** du chroot que l'écriture doit rester possible, pas à sa racine.

### 4. Ajouter le bloc SFTP dans `sshd_config`

**Impérativement à la toute fin du fichier** (règle stricte d'OpenSSH : un bloc `Match` s'applique jusqu'au prochain `Match` ou la fin du fichier) :

bash

```bash
sudo tee -a /etc/ssh/sshd_config << 'EOF'Match Group webdev    ChrootDirectory /var/www    ForceCommand internal-sftp    AllowTcpForwarding no    X11Forwarding no    PasswordAuthentication yesEOF
```

Le `PasswordAuthentication yes` ici est **local à ce bloc** (grâce à `Match Group webdev`) — le reste du serveur (compte `ls`, admin) reste strictement en clé uniquement, rien ne change pour lui. Vu que tes 3 comptes n'ont jamais eu de clé SSH (ils n'utilisaient que Samba/FTP), c'est le choix le plus cohérent avec l'usage actuel — et même avec mot de passe, le SFTP chiffre tout le trafic (identifiants compris), contrairement au FTP en clair : l'objectif sécurité est déjà largement atteint par ce simple changement de protocole.

### 5. Tester avant de redémarrer

bash

```bash
sudo sshd -t
```

Aucune sortie = syntaxe correcte. Redémarre ensuite :

bash

```bash
sudo systemctl restart sshd
```

### 6. Tester la connexion

bash

```bash
sftp -P 2224 ulrichl@192.168.1.131
```

Une fois connecté, tu dois te retrouver directement à la racine du chroot (donc voir `intra.isec.local` et `glpi.isec.local`), sans pouvoir remonter au-dessus (`cd ..` restera bloqué à cette racine).

Côté client graphique pour les utilisateurs finaux, WinSCP ou FileZilla supportent le SFTP nativement — juste changer le protocole de "FTP" à "SFTP" dans leur config existante, le port passe de 21 à 22 (ou 2224 depuis l'extérieur du NAT)

1. Démasquer et redémarrer vsftpd

systemctl mask va plus loin qu'un simple disable (il bloque même un démarrage manuel), donc il faut d'abord lever ce verrou avant de pouvoir le relancer :

bash
sudo systemctl unmask vsftpd
sudo systemctl enable --now vsftpd
sudo systemctl status vsftpd
2. Vérifier que la config vsftpd est toujours intacte

Rien n'a été touché dans /etc/vsftpd.conf ni /etc/vsftpd.userlist pendant qu'on a mis en place le SFTP — ça devrait donc fonctionner immédiatement, exactement comme avant :

bash
sudo systemctl restart vsftpd
ftp 192.168.0.202   # test rapide depuis le serveur lui-même, ou depuis un client

## Réactiver FTP

### 1. Démasquer et redémarrer vsftpd

`systemctl mask` va plus loin qu'un simple `disable` (il bloque même un démarrage manuel), donc il faut d'abord lever ce verrou avant de pouvoir le relancer :

bash

```bash
sudo systemctl unmask vsftpdsudo systemctl enable --now vsftpdsudo systemctl status vsftpd
```

### 2. Vérifier que la config vsftpd est toujours intacte

Rien n'a été touché dans `/etc/vsftpd.conf` ni `/etc/vsftpd.userlist` pendant qu'on a mis en place le SFTP — ça devrait donc fonctionner immédiatement, exactement comme avant :

bash

```bash
sudo systemctl restart vsftpd
ftp 192.168.0.202   # test rapide depuis le serveur lui-même, ou depuis un client
```
