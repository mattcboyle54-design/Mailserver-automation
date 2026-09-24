#!/usr/bin/env bash
set -Eeuo pipefail

# CIS Level 1 selective hardening for this Ubuntu mail/webmail lab.
#
# Selected controls:
# - cron/at allow files
# - cron permissions
# - IPv4 martian packet logging
# - selected OpenSSH server hardening
# - OpenSSH configuration file permissions
#
# Intentionally NOT modified:
# - PAM/authentication stack
# - sudoers
# - UFW/nftables
# - GRUB
# - Postfix
# - Dovecot
# - Apache
# - Roundcube
# - SSH port
# - PasswordAuthentication policy
# - AllowUsers / AllowGroups access restrictions

STATE_DIR="/var/lib/cis-mail-hardening"
BACKUP_DIR="$STATE_DIR/backups"
CREATED_DIR="$STATE_DIR/created"

SYSCTL_FILE="/etc/sysctl.d/99-z-cis-mailserver-hardening.conf"
SSH_FILE="/etc/ssh/sshd_config.d/00-cis-mailserver-hardening.conf"

log() {
    printf '[cis-hardening] %s\n' "$*"
}

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Run this script with sudo: sudo ./cis-hardening.sh" >&2
    exit 1
fi

install -d -m 0700 "$STATE_DIR" "$BACKUP_DIR" "$CREATED_DIR"


# ============================================================
# Helper functions
# ============================================================

file_tag() {
    local path="$1"
    path="${path#/}"
    printf '%s' "${path//\//__}"
}


# Back up a pre-existing file/directory once.
backup_existing_once() {
    local path="$1"
    local tag backup

    tag="$(file_tag "$path")"
    backup="$BACKUP_DIR/$tag.original"

    if [[ -e "$path" && ! -e "$backup" ]]; then
        cp -a -- "$path" "$backup"
        log "Backed up $path to $backup"
    fi
}


# Prepare a file the script manages.
prepare_managed_file() {
    local file="$1"
    local tag marker backup parent

    tag="$(file_tag "$file")"
    marker="$CREATED_DIR/$tag"
    backup="$BACKUP_DIR/$tag.original"
    parent="$(dirname "$file")"

    if [[ -e "$file" ]]; then
        if [[ ! -e "$marker" && ! -e "$backup" ]]; then
            cp -a -- "$file" "$backup"
            log "Backed up $file to $backup"
        fi
    else
        if [[ ! -d "$parent" ]]; then
            install -d -m 0755 "$parent"
        fi

        : > "$file"
        : > "$marker"

        log "Created $file"
    fi
}


# Replace only the block owned by this script.
write_managed_block() {
    local file="$1"
    local begin_marker="$2"
    local end_marker="$3"
    local content="$4"
    local tmp

    tmp="$(mktemp)"

    awk -v begin="$begin_marker" -v end="$end_marker" '
        $0 == begin { skipping=1; next }
        $0 == end   { skipping=0; next }
        !skipping   { lines[++n]=$0 }

        END {
            while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
            for (i=1; i<=n; i++) print lines[i]
        }
    ' "$file" > "$tmp"

    if [[ -s "$tmp" ]]; then
        printf '\n' >> "$tmp"
    fi

    printf '%s\n%s\n%s\n' \
        "$begin_marker" \
        "$content" \
        "$end_marker" >> "$tmp"

    cat "$tmp" > "$file"
    rm -f "$tmp"
}


# ============================================================
# CIS 2.4.2.1
# Ensure that /etc/at.allow exists
# ============================================================

log "Applying CIS 2.4.2.1: /etc/at.allow"

prepare_managed_file /etc/at.allow

chown root:root /etc/at.allow
chmod 0640 /etc/at.allow

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    grep -qxF "$SUDO_USER" /etc/at.allow ||
        printf '%s\n' "$SUDO_USER" >> /etc/at.allow
fi


# ============================================================
# CIS 2.4.1.2
# Ensure that /etc/cron.allow exists
# ============================================================

log "Applying CIS 2.4.1.2: /etc/cron.allow"

prepare_managed_file /etc/cron.allow

chown root:root /etc/cron.allow
chmod 0600 /etc/cron.allow

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    grep -qxF "$SUDO_USER" /etc/cron.allow ||
        printf '%s\n' "$SUDO_USER" >> /etc/cron.allow
fi


# ============================================================
# CIS cron permissions
# ============================================================

log "Applying CIS cron permissions"

if [[ -d /etc/cron.d ]]; then
    backup_existing_once /etc/cron.d
    chmod 0700 /etc/cron.d
fi

if [[ -f /etc/crontab ]]; then
    backup_existing_once /etc/crontab
    chmod 0600 /etc/crontab
fi


# ============================================================
# CIS 3.3.9
# Log martian packets on all/default IPv4 interfaces
# ============================================================

log "Applying CIS 3.3.9: IPv4 martian packet logging"

prepare_managed_file "$SYSCTL_FILE"

SYSCTL_CONTENT='net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1'

write_managed_block \
    "$SYSCTL_FILE" \
    '# BEGIN CIS-MAILSERVER MANAGED SYSCTL' \
    '# END CIS-MAILSERVER MANAGED SYSCTL' \
    "$SYSCTL_CONTENT"

chown root:root "$SYSCTL_FILE"
chmod 0644 "$SYSCTL_FILE"

sysctl -q -w net.ipv4.conf.all.log_martians=1
sysctl -q -w net.ipv4.conf.default.log_martians=1

for key in \
    net.ipv4.conf.all.log_martians \
    net.ipv4.conf.default.log_martians
do
    if [[ "$(sysctl -n "$key")" != "1" ]]; then
        echo "ERROR: $key did not apply as expected." >&2
        exit 1
    fi
done


# ============================================================
# CIS 5.1.x
# Selected OpenSSH server hardening
# ============================================================

log "Applying selected CIS OpenSSH server hardening"

if [[ ! -x /usr/sbin/sshd ]]; then
    echo "ERROR: /usr/sbin/sshd was not found." >&2
    exit 1
fi

# Banner is one of the settings managed below.
if [[ ! -f /etc/issue.net ]]; then
    echo "ERROR: /etc/issue.net does not exist." >&2
    echo "SSH hardening will not be applied because Banner references this file." >&2
    exit 1
fi

if [[ ! -d /etc/ssh/sshd_config.d ]]; then
    install -d -m 0755 /etc/ssh/sshd_config.d
fi


# Temporary same-run copy for rollback if validation fails.
ssh_existed_before=false
ssh_run_backup="$(mktemp)"

if [[ -e "$SSH_FILE" ]]; then
    cp -a -- "$SSH_FILE" "$ssh_run_backup"
    ssh_existed_before=true
fi

prepare_managed_file "$SSH_FILE"


SSH_CONTENT='ClientAliveInterval 300
ClientAliveCountMax 3
HostbasedAuthentication no
PermitEmptyPasswords no
IgnoreRhosts yes
PermitRootLogin no
PermitUserEnvironment no
Banner /etc/issue.net
LoginGraceTime 60
LogLevel INFO
MaxAuthTries 4
MaxSessions 10
MaxStartups 10:30:60
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
KexAlgorithms sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256'


write_managed_block \
    "$SSH_FILE" \
    '# BEGIN CIS-MAILSERVER MANAGED SSH' \
    '# END CIS-MAILSERVER MANAGED SSH' \
    "$SSH_CONTENT"

chown root:root "$SSH_FILE"
chmod 0600 "$SSH_FILE"


restore_ssh_file() {
    if [[ "$ssh_existed_before" == true ]]; then
        cp -a -- "$ssh_run_backup" "$SSH_FILE"
    else
        rm -f -- "$SSH_FILE"
    fi
}


fail_ssh_hardening() {
    local message="$1"

    echo "ERROR: $message" >&2
    echo "Restoring the previous script-managed SSH configuration." >&2
    echo "SSH will NOT be reloaded." >&2

    restore_ssh_file
    rm -f "$ssh_run_backup"

    exit 1
}


# ------------------------------------------------------------
# SSH syntax validation
# ------------------------------------------------------------

log "Validating OpenSSH configuration"

if ! /usr/sbin/sshd -t; then
    fail_ssh_hardening "sshd configuration validation failed."
fi


# ------------------------------------------------------------
# Effective-value verification
# ------------------------------------------------------------

effective_ssh="$(/usr/sbin/sshd -T 2>/dev/null)"

verify_ssh_setting() {
    local key="$1"
    local expected="$2"
    local actual

    actual="$(
        awk -v wanted="$key" '
            tolower($1) == tolower(wanted) {
                $1=""
                sub(/^[[:space:]]+/, "")
                print
                exit
            }
        ' <<< "$effective_ssh"
    )"

    if [[ "${actual,,}" != "${expected,,}" ]]; then
        echo "ERROR: SSH setting did not become effective:" >&2
        echo "  $key" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   ${actual:-<not found>}" >&2

        fail_ssh_hardening \
            "Another SSH configuration may be overriding the script-managed value."
    fi

    log "Verified $key = $expected"
}


verify_ssh_setting ClientAliveInterval "300"
verify_ssh_setting ClientAliveCountMax "3"
verify_ssh_setting HostbasedAuthentication "no"
verify_ssh_setting PermitEmptyPasswords "no"
verify_ssh_setting IgnoreRhosts "yes"
verify_ssh_setting PermitRootLogin "no"
verify_ssh_setting PermitUserEnvironment "no"
verify_ssh_setting Banner "/etc/issue.net"
verify_ssh_setting LoginGraceTime "60"
verify_ssh_setting LogLevel "INFO"
verify_ssh_setting MaxAuthTries "4"
verify_ssh_setting MaxSessions "10"
verify_ssh_setting MaxStartups "10:30:60"

verify_ssh_setting Ciphers \
"chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"

verify_ssh_setting KexAlgorithms \
"sntrup761x25519-sha512@openssh.com,curve25519-sha256,curve25519-sha256@libssh.org,ecdh-sha2-nistp256,ecdh-sha2-nistp384,ecdh-sha2-nistp521,diffie-hellman-group-exchange-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,diffie-hellman-group14-sha256"

verify_ssh_setting MACs \
"hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"


# ============================================================
# CIS OpenSSH configuration file permissions
# ============================================================

log "Restricting OpenSSH configuration file permissions"

backup_existing_once /etc/ssh/sshd_config

chown root:root /etc/ssh/sshd_config
chmod 0600 /etc/ssh/sshd_config

find /etc/ssh/sshd_config.d \
    -maxdepth 1 \
    -type f \
    -exec chown root:root {} \; \
    -exec chmod 0600 {} \;


# Final syntax check after all SSH-related changes.
if ! /usr/sbin/sshd -t; then
    fail_ssh_hardening "Final sshd validation failed."
fi


# Everything validated successfully.
systemctl reload ssh
rm -f "$ssh_run_backup"

log "SSH configuration validated and reloaded successfully."
log "OpenSSH configuration files restricted to root ownership and 0600 permissions."


# ============================================================
# Finished
# ============================================================

log "Selected CIS hardening completed."
log "Next: test SSH, Postfix, Dovecot, Apache/Roundcube, then re-run USG."
