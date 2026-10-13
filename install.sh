#!/bin/bash
set -Eeuo pipefail

APT_FLAGS=(-y -qq)
MYSQL_AUTOCONFIG='true'
SKIP_UPGRADE='false'
INSTALL_TYPE='web'

if [[ ! -r /etc/os-release ]]; then
    echo "Não foi possível identificar o sistema operacional." >&2
    exit 1
fi
# shellcheck disable=SC1091
. /etc/os-release
OS="${ID:-}"
OS_VERSION="${VERSION_ID:-}"

version() {
    echo "Script de Instalação Básica V1.3 - Ecomp"
    echo "2020~2021 - Wendel Moro, Victor Alflen e Rogério Bayer"
}

help_msg() {
    version
    echo
    echo " Uso: sudo $0 <tipo de instalacao>"
    echo "	Tipo de instalação: um dentre [tudo, web, mobile]"
    echo
    echo " [Opções]:"
    echo "	-h --help: Exibe esta mensagem de ajuda"
    echo "	-v --version: Exibe a versão do script"
    echo "	--check-install: Testa se os programas estão instalados"
    echo "	--no-mysql-autoconfig: Não configura o MariaDB automaticamente"
    echo "	--no-upgrade: Não atualiza os pacotes atuais antes de começar"
}

info() {
    echo
    echo ">>> $1 ..."
    echo
}

check_install() {
    local programas=(php npm mysql java javac adb)
    local found=false
    local cmd

    for cmd in "${programas[@]}"; do
        if command -v "${cmd}" >/dev/null 2>&1; then
            echo ">> Instalação do ${cmd} detectada"
            "${cmd}" --version || true
            found=true
        else
            echo "!! Instalação do ${cmd} não detectada !!"
        fi
        echo
    done

    if [[ "${found}" == 'true' ]]; then
        echo "Há programas instalados. O script não os remove automaticamente."
    fi
}

for arg in "$@"; do
    case "${arg}" in
        tudo|web|mobile) INSTALL_TYPE="${arg}" ;;
        --no-upgrade) SKIP_UPGRADE='true' ;;
        --no-mysql-autoconfig) MYSQL_AUTOCONFIG='false' ;;
        -h|--help) help_msg; exit 0 ;;
        -v|--version) version; exit 0 ;;
        --check-install) check_install; exit 0 ;;
        *)
            echo "Opção inválida: ${arg}" >&2
            help_msg >&2
            exit 2
            ;;
    esac
done

if [[ "${OS,,}" != 'ubuntu' ]]; then
    echo "Seu sistema não é suportado por esse script" >&2
    exit 1
fi

if [[ "${INSTALL_TYPE}" == 'mobile' ]]; then
    echo "A instalação mobile ainda não está implementada." >&2
    exit 1
fi
[[ "${INSTALL_TYPE}" == 'tudo' ]] && INSTALL_TYPE='web'

if [[ "${EUID}" -ne 0 ]]; then
    echo "Por favor, execute como root." >&2
    exit 1
fi

version
echo
echo "Iniciando instalação"
echo "Isso VAI demorar um pouco..."
echo "Aproveite para tomar um café!"

if [[ "${SKIP_UPGRADE}" != 'true' ]]; then
    info "Atualizando o seu sistema"
    apt-get "${APT_FLAGS[@]}" update
    apt-get "${APT_FLAGS[@]}" upgrade
fi

info "Instalando pacotes básicos e dependencias"
apt-get install "${APT_FLAGS[@]}" software-properties-common git curl wget zip unzip gpg

if [[ "${INSTALL_TYPE}" == 'web' ]]; then
    tput setaf 2 2>/dev/null || true
    info "Instalação do Front"
    tput sgr0 2>/dev/null || true

    if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
        export NVM_DIR="${XDG_CONFIG_HOME}/nvm"
    else
        export NVM_DIR="${HOME}/.nvm"
    fi
    if [[ ! -s "${NVM_DIR}/nvm.sh" ]]; then
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
    fi
    # shellcheck disable=SC1090
    source "${NVM_DIR}/nvm.sh"
    nvm install --lts
    nvm alias default 'lts/*'
    nvm use --lts

    tput setaf 2 2>/dev/null || true
    info "Instalação do Back"
    tput sgr0 2>/dev/null || true
    info "Instalando repositório do php"
    add-apt-repository -y ppa:ondrej/php
    apt-get update

    info "Instalando php 8.3"
    apt-get install "${APT_FLAGS[@]}" php8.3
    apt-get install "${APT_FLAGS[@]}" php8.3-cli php8.3-{bz2,curl,mbstring,intl,common,pdo,fpm,mysql,opcache,bcmath,tokenizer,xml,zip,soap}

    info "Instalando composer"
    curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer

    info "Instalando Postman"
    postman_archive="$(mktemp --tmpdir postman.XXXXXX.tar.gz)"
    trap 'rm -f "${postman_archive:-}" "${sql_file:-}"' EXIT
    wget -q https://dl.pstmn.io/download/latest/linux64 -O "${postman_archive}"
    tar -xzf "${postman_archive}"
    rm -rf /opt/Postman
    mv Postman /opt
    ln -sfn /opt/Postman/Postman /usr/local/bin/postman
    cat > /usr/share/applications/postman.desktop <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Postman
Icon=/opt/Postman/app/resources/app/assets/icon.png
Exec="/opt/Postman/Postman"
Comment=Postman GUI
Categories=Development;Code;
DESKTOP

    info "Instalando Repositório do Mariadb"
    curl -fsSL https://r.mariadb.com/downloads/mariadb_repo_setup |
        bash -s -- --os-type=ubuntu --os-version="${OS_VERSION}"
    info "Instalando Mariadb mais recente"
    apt-get update
    apt-get install "${APT_FLAGS[@]}" mariadb-server mariadb-client
fi

if [[ "${MYSQL_AUTOCONFIG}" == 'true' ]]; then
    sql_file="$(mktemp)"
    trap 'rm -f "${postman_archive:-}" "${sql_file}"' EXIT
    cat > "${sql_file}" <<'SQL'
CREATE DATABASE IF NOT EXISTS nexus;
CREATE USER IF NOT EXISTS 'i9'@'localhost' IDENTIFIED BY 'nexusi9';
ALTER USER 'i9'@'localhost' IDENTIFIED BY 'nexusi9';
GRANT ALL PRIVILEGES ON nexus.* TO 'i9'@'localhost';
FLUSH PRIVILEGES;
SQL
    mariadb -u root < "${sql_file}"
    rm -f "${sql_file}"
    service mariadb restart

    echo "Foi criado um usuario inicial"
    echo "Seu usuário MYSQL: i9"
    echo "Sua senha MYSQL: nexusi9"
    echo "Voce pode criar mais usuarios"
fi
