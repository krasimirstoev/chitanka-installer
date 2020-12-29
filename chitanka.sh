#!/usr/bin/env bash

installer_git=https://github.com/chitanka/chitanka-installer.git
installer_dir=${installer_dir:-/root/chitanka-installer}
install_log=`dirname $0`/install.log
chitanka_dir=/var/www/chitanka
chitanka_git='https://github.com/chitanka/chitanka-production.git'
chitanka_rsync_content='rsync.chitanka.info::content'
default_domain='chitanka.local'
debian_stable_version='buster'

## Database section
mysql_service_password='cH-00-service_paS$W'
mysql_ch_user='chitanka'
mysql_ch_password='chitanka'
mysql_ch_database='chitanka'
mysql_db_dump='http://download.chitanka.info/chitanka.sql.gz'
mysql_root="mysql -uroot -p${mysql_service_password}"
mysql_chitanka="mysql -u${mysql_ch_user} -p${mysql_ch_user_password} ${mysql_ch_database}"

install_pkg='apt install -y'

## colors
color_bold_red='\033[1;31m'
color_bold_green='\033[1;32m'
color_bold_yellow='\033[1;33m'
color_bold_white='\033[1;37m'
color_reset='\033[0m'

##################################

install() {
	# only root is allowed to execute the installer
	if [ "$(id -u)" != "0" ]; then
		color_echo $color_bold_red "Инсталаторът трябва да бъде стартиран с потребител ${color_bold_white}root${color_reset}. Следва изход." 1>&2
		exit 1
	fi

	if ! is_debian_based; then
		color_echo $color_bold_red "Използваната версия на Debian не е сред поддържаните. Следва изход."
		exit 1
	fi

	log "Начало на инсталацията"

	clear
	splash_screen

	color_echo $color_bold_green "Желаете ли процедурата по инсталация да започне? Изберете y (да) или n (не)."
	read yn
	yn=${yn:-y}
	if [ "$yn" != "y" ]; then
		color_echo $color_bold_red "Избрахте да прекратите процедурата по инсталация на огледалото. Следва изход."
		log "Инсталацията e прекратена по желание на потребителя."
		exit
	fi

	unset LANG
	export DEBIAN_FRONTEND=noninteractive

	clear
	update_system
	sleep 1

	clear
	install_basic_packages

	clear
	install_web_server

	clear
	set_domain
	sleep 3

	clear
	install_db_server

	clear
	create_chitanka_db

	clear
	install_chitanka_software
	get_chitanka_content

	echo_success
}

uninstall () {
	rm -rf $chitanka_dir
	rm -rf $installer_dir

	# drop database
	$mysql_root -e "DROP DATABASE ${mysql_ch_database}"

	color_echo $color_bold_red "Файловото съдържание и базата данни на Моята библиотека са премахнати от сървъра."
	echo && echo
	color_echo $color_bold_red "Запазена е единствено конфигурацията на уеб сървъра."
}

changedomain () {
	color_echo $color_bold_white "Моля, въведете желаното домейн име:"
	read own_domain_name
	color_echo $color_bold_red "Избрахте домейн името: $own_domain_name"

	set_domain_in_webhost $own_domain_name
	set_domain_in_localhost $own_domain_name
	restart_web_server
}

addcron () {
	crontab -l > chitanka_cron
	echo "0 0 * * * ${chitanka_dir}/bin/update" >> chitanka_cron
	crontab chitanka_cron
	rm -f chitanka_cron
}

show_help () {
	echo
	echo -e "Употреба на инсталатора:\n\n\t${color_bold_green}$0${color_reset} ${color_bold_white}команда${color_reset}"
	echo
	echo -e "Можете да използвате следните команди:"
	echo -e "${color_bold_white} install ${color_reset}      - автоматична инсталация и конфигурация на огледало на Моята библиотека"
	echo -e "${color_bold_white} getcontent ${color_reset}   - сваляне на съдържание за огледалото на Моята библиотека (може да бъде изпълнено и при командата ${color_bold_white}install${color_reset})"
	echo -e "${color_bold_white} changedomain ${color_reset} - можете да изберете нов домейн, който да бъде конфигуриран в уеб сървъра"
	echo -e "${color_bold_white} addcron ${color_reset}      - добавят се cron задачите, необходими за обновяването на огледалото"
	echo -e "${color_bold_white} uninstall ${color_reset}    - изтрива съдържанието на вече инсталирано огледало на Моята библиотека"
	echo
}

splash_screen () {
	echo
	echo -e "${color_bold_yellow}**************************************************${color_reset}"
	echo -e "${color_bold_yellow}*${color_reset} ${color_bold_white}       Читанка - автоматичен инсталатор       ${color_reset} ${color_bold_yellow}*${color_reset}"
	echo -e "${color_bold_yellow}**************************************************${color_reset}"
	color_echo $color_bold_white "След секунди ще започне инсталацията на необходимия софтуер за МОЯТА БИБЛИОТЕКА."
	echo
	color_echo $color_bold_white "За правилната работа на софтуера е необходимо:"
	color_echo $color_bold_white "1) Да разполагате с най-малко 20 гигабайта дисково пространство."
	color_echo $color_bold_white "2) Да не прекъсвате процеса по инсталация, докато не приключи."
	echo -e "${color_bold_yellow}**************************************************${color_reset}"
	echo
}

update_system () {
	color_echo $color_bold_green "Започва обновяване на операционната система."
	sleep 1
	apt update -y
	log "Операционната система беше обновена."
}

install_basic_packages () {
	color_echo $color_bold_green "Инсталация на системен софтуер."
	sleep 2
	$INSTALL_PKG git curl rsync
	log "Инсталиран е необходимият системен софтуер."
	if [ ! -d $INSTALLER_DIR ]; then
		git clone $INSTALLER_GIT $INSTALLER_DIR
	fi
}

install_web_server () {
	color_echo $color_bold_green "Започва инсталацията на уеб сървъра."
	sleep 2
	$INSTALL_PKG nginx php-fpm php-gd php-curl php-xsl php-intl php-zip
	cp $INSTALLER_DIR/nginx-vhost.conf /etc/nginx/sites-enabled/chitanka
}

restart_web_server () {
	service nginx restart
}

set_domain () {
	color_echo $color_bold_white "По подразбиране, в конфигурацията е заложен домейн ${DEFAULT_DOMAIN}. В случай че разполагате със собствен домейн, бихте могли да го използвате за конфигурацията на огледалото."
	echo
	color_echo $color_bold_white "Желаете ли да използвате свой домейн? Изберете (y) за да посочите свой домейн или (n) за да продължи инсталацията с домейна ${DEFAULT_DOMAIN}."

	read yn
	yn=${yn:-y}
	if [ "$yn" = "n" ]; then
		color_echo $color_bold_green "Избрахте да използвате служебното име ${DEFAULT_DOMAIN}. Инсталацията продължава."
		log "Избран домейн за инсталацията: служебно (${DEFAULT_DOMAIN})."
		set_domain_in_localhost $DEFAULT_DOMAIN
		log "Избран е заложеният по подразбиране домейн ${DEFAULT_DOMAIN}."
	else
		color_echo $color_bold_white "Моля, въведете желания домейн:"
		read own_domain_name
		color_echo $color_bold_red "Избрахте домейн: $own_domain_name"
		set_domain_in_webhost $own_domain_name
		set_domain_in_localhost $own_domain_name
		log "Избран е различен от заложения домейн: $own_domain_name и е добавен в конфигурационните файлове."
	fi
	restart_web_server
	log "Виртуалният хост беше създаден."
}

set_domain_in_webhost () {
	sed -i "s/${DEFAULT_DOMAIN}/$1/g" /etc/nginx/sites-enabled/chitanka
}

set_domain_in_localhost () {
	sed -i -e '1i\'"127.0.0.1	$1" /etc/hosts
}

install_db_server () {
	color_echo $color_bold_green "Инсталация на база от данни MariaDB."
	sleep 2
	debconf-set-selections <<< "mariadb-server mysql-server/root_password password $MYSQL_SERVICE_PASSWORD"
	debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password $MYSQL_SERVICE_PASSWORD"
	$INSTALL_PKG mariadb-server mariadb-client php-mysql
	log "Инсталирана е база от данни MariaDB със служебна парола: $MYSQL_SERVICE_PASSWORD"
}

create_chitanka_db () {
	color_echo $color_bold_green "Създаване на потребителско име и база от данни за огледалото."
	sleep 2
	$MYSQL_ROOT -e "CREATE USER '$MYSQL_CH_USER'@'localhost' IDENTIFIED BY '$MYSQL_CH_USER_PASSWORD'"
	$MYSQL_ROOT -e "GRANT ALL PRIVILEGES ON *.* TO '$MYSQL_CH_USER'@'localhost'"
	$MYSQL_ROOT -e "FLUSH PRIVILEGES"
	$MYSQL_ROOT -e "CREATE DATABASE $MYSQL_CH_DATABASE"
	log "Създаден е MySQL потребител със служебна парола: $MYSQL_CH_USER_PASSWORD"
	log "Създадена е MySQL база от данни: $MYSQL_CH_DATABASE"

	curl $MYSQL_DB_DUMP | gunzip | $MYSQL_CHITANKA
	log "Базата от данни за огледалото е внесена."
}

install_chitanka_software () {
	color_echo $color_bold_green "Вземане на кода от хранилището в GitHub."
	sleep 2

	rm -rf $CHITANKA_DIR
	git clone --depth 1 $CHITANKA_GIT $CHITANKA_DIR
	log "Програмният код е успешно клониран от хранилището в GitHub."

	cp $INSTALLER_DIR/parameters.yml $CHITANKA_DIR/app/config

	cd $CHITANKA_DIR
	chmod -R a+w var/cache var/log var/spool web/cache
	log "Правата за директориите cache, log и spool са променени."
}

get_chitanka_content () {
	color_echo $color_bold_green "Желаете ли да свалите текстовото съдържание? Изберете y (да) или n (не)."
	echo -e "Можете да го направите и по всяко друго време, като стартирате инсталатора с командата ${color_bold_green}getcontent${color_reset}."
	read yn
	yn=${yn:-y}
	if [ "$yn" == "y" ]; then
		clear
		rsync_content
	else
		echo -e "Избрахте да ${color_bold_red}НЕ${color_reset} сваляте съдържание."
		log "Избрана е опция да не бъде свалено съдържанието."
	fi
}

rsync_content () {
	color_echo $color_bold_green "Сваляне на съдържанието."
	sleep 2
	log "rsync процедурата е СТАРТИРАНА"
	rsync -avz --delete ${CHITANKA_RSYNC_CONTENT}/ $CHITANKA_DIR/web/content
	log "rsync процедурата ПРИКЛЮЧИ"
}

echo_success () {
	color_echo $color_bold_green "Огледалната версия на Моята библитека беше инсталирана."
	color_echo $color_bold_green "Ако огледалото ви е публично достъпно, можете да споделите адреса му във форума на Моята библиотека:"
	color_echo $color_bold_green "https://forum.chitanka.info"
}

color_echo () {
	echo -e $1$2$color_reset
}

log () {
	logfile=${2:-$INSTALL_LOG}
	echo "[`date +"%d.%m.%Y %T"`] $1" >> $logfile
}

is_debian_stable () {
	if [[ ! `grep 'VERSION=' /etc/os-release | grep $debian_stable_version` ]]; then return 1; fi
	
}
is_ubuntu () {
	if [[ ! `grep 'ID=' /etc/os-release | grep ubuntu` ]]; then return 1; fi
}
is_debian_based () {
	if [[ ! -e /etc/debian_version ]]; then return 1; fi
}
is_centos () {
	if [[ ! `grep 'ID=' /etc/os-release | grep centos` ]]; then return 1; fi
}

is_apache_installed () {
	if [[ ! `ps -A | grep 'apache\|httpd'` ]]; then return 1; fi
}

case "$1" in
	install)
		install
	;;
	getcontent)
		rsync_content
	;;
	uninstall)
		uninstall
	;;
	changedomain)
		changedomain
	;;
	addcron)
		addcron
	;;
	dev)
		is_ubuntu
	;;
	*)
		show_help
esac
