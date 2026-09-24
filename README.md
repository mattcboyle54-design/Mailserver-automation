# Ubuntu Mail Server Hardening & Automation Lab

## Overview

This project documents the deployment and security hardening of a self-hosted mail server in an Ubuntu Server 24.04 virtual machine.

The environment was built in VirtualBox and configured with:

- Ubuntu Server 24.04
- OpenSSH
- Postfix
- Dovecot
- Apache
- Roundcube
- Ubuntu Security Guide (USG)
- CIS Level 1 Server security guidance
- Bash scripting for selected hardening controls

The goal was to build a working local mail environment first, establish a pre-hardening security baseline, selectively remediate CIS findings without breaking required services, and then perform regression testing and another security audit.

> This is a local lab environment and is not configured as a production Internet-facing mail server.

---

## Project Architecture

```text
Windows Host
    |
    | VirtualBox NAT
    |
    +-- SSH: 127.0.0.1:2222 -> Ubuntu VM:22
    |
    +-- HTTP: 127.0.0.1:8080 -> Ubuntu VM:80
                                  |
                                  +-- Apache
                                  |     |
                                  |     +-- Roundcube
                                  |
                                  +-- Postfix
                                  |
                                  +-- Dovecot
```
------------------------------------------------------------------

### 1. Ubuntu Server Installation: 
<img width="819" height="596" alt="image1" src="https://github.com/user-attachments/assets/4867f118-23f6-470f-9110-2ee6ec27c242" />

I created a new VirtualBox virtual machine and installed Ubuntu Server 24.04 from an ISO image

During installation:
  - Configured CPU, RAM, and storage for the VM. (2 cores, 4GB ram, 25GB storage)(would also be fine with 1 core, 2GB ram, 25GB storage)
  - Selected the OpenSSH Server option.
  - Did not install additional optional server packages.

After installation, I updated the system:
  sudo apt update
  sudo apt upgrade
------------------------------------------------------------------

### 2. SSH Access Through VirtualBox

Rather than performing the entire project through the VirtualBox console, I configured NAT port forwarding so I could administer the VM from the Windows host.
Not necessary just a preference 

```text
VirtualBox SSH Port Forward
Setting     Value
Name        SSH
Protocol    TCP
Host IP     127.0.0.1
Host Port   2222
Guest Port  22
```

SSH was verified and enabled
  sudo systemctl status ssh
  sudo systemctl enable --now ssh

From Windows, connect to the VM:
  ssh -p 2222 sysadmin@127.0.0.1

Using SSH made it easier to copy commands, edit configuration files, and transfer reports between the VM and the host machine.

### 3. Establishing a Pre-Hardening Security Baseline 

The original plan was to use CIS-CAT for the security assessment. During setup, I changed the approach and used Ubuntu Security Guide (USG) with the CIS Level 1 Server profile instead.

USG was enabled and installed
  sudo pro enable usg
  sudo apt install usg

Run audit: 
  sudo usg audit cis_level1_server

<img width="816" height="900" alt="usg_1" src="https://github.com/user-attachments/assets/6245e9f1-5b98-4180-8e5c-d4e113ff017a" />

The first audit produced a baseline score of approximately 71.2%, with:
  - 232 rules passing
  - 109 rules failing

This report was preserved so the state of the machine before hardening could later be compared with the hardened configuration.

#### Exporting the USG Report

The generated HTML report was copied to the home directory:

  sudo cp /var/lib/usg/REPORT_NAME.html /home/sysadmin/
  sudo chown sysadmin:sysadmin /home/sysadmin/REPORT_NAME.html

I then  transferred the report to the Windows host with SCP in another command prompt window:
  scp -P 2222 sysadmin@127.0.0.1:/home/sysadmin/REPORT_NAME.html <local-report-directory>

------------------------------------------------------------------

### 4. Postfix Mail Server

Install Postfix and command-line mail utilities 
  sudo apt update
  sudo apt install postfix mailutils

During Postfix configuration:
  Configuration type: Internet Site
  Local mail domain: mailserver-lab.local(name your server whatever you want) 


Postfix verified:
  sudo systemctl status postfix --no-pager

Test local mail accounts were created for the lab.
  - Credentials are intentionally not included in this repository.

Make email accounts 
  sudo adduser user1
  then
  (insert password here)
  
  Sudo adduser user2
  then
  (insert password here)

Send mail: 
  echo "Hi user2 you are pretty cool!" | sudo -u user1 mail -s "Postfix Test" user2@mailserver-lab.local 

<img width="1426" height="636" alt="postfix sent" src="https://github.com/user-attachments/assets/b8219bef-f10a-4ac9-926f-2c2796f5b1d8" />

------------------------------------------------------------------

### 5. Dovecot IMAP

Dovecot was installed to provide mailbox and IMAP functionality:
  sudo apt install dovecot-imapd

Check service: 
  sudo systemctl status dovecot --no-pager

Inspect mailbox status:
  sudo doveadm mailbox status -u <mail-user> messages INBOX

Verify that Dovecot was listening on the expected IMAP ports
  sudo ss -ltnp | grep -E ':(143|993)\b'

------------------------------------------------------------------

### 6. Roundcube Webmail

Install Roundcube and Apache:
  sudo apt install apache2 roundcube roundcube-sqlite3

During installation, the Roundcube database was configured using dbconfig-common.

Verify Apache: 
sudo systemctl status apache2 --no-pager

------------------------------------------------------------------

### 7. 7. Accessing Roundcube From the Host

A second VirtualBox NAT forwarding rule was created for HTTP.
```text
Setting     Value
Name        HTTP
Protocol    TCP
Host IP     127.0.0.1
Host Port   8080
Guest Port  80
```
Roundcube could then be accessed from the Windows host at http://127.0.0.1:8080/roundcube

Initially, Apache returned a 404 Not Found response.
This confirmed that the VirtualBox NAT rule and Apache connection were working, but Roundcube itself was not yet exposed at /roundcube.
Go into Apache config: 
  sudo nano /etc/roundcube/apache.conf

Make sure Alias /roundcube /var/lib/roundcube is not commented out #

Reload the config file: 
  sudo a2enconf roundcube 
  sudo systemctl reload apache2 

------------------------------------------------------------------

### 8. Fixing Roundcube SMTP
Since we're using a local server port 25 is acceptable to test functionality should change back to 587 later. 

Open the config: 
  sudo nano /etc/roundcube/config.inc.php

Look for 
  $config['smtp_host'] = 'localhost:587';

Update SMPT host, user, and pass: 
  $config['smtp_host'] = 'localhost:25';
  $config['smtp_user'] = '';
  $config['smtp_pass'] = '';

Reload Apache: 
  sudo systemctl reload apache2

<img width="1434" height="528" alt="{77B06D05-4CA4-4693-9989-2ED4FD93081D}" src="https://github.com/user-attachments/assets/03c077b4-2203-413f-ab3a-6601240d33a5" />

*IMPORTANT* make sure create a snapshot to preserve a known-good functional mail-server state before security hardening 

------------------------------------------------------------------

### 9.Security Hardening Strategy

Rather than attempting to automatically remediate every CIS failure, I used a selective approach.
The mail server depended on:
- SSH
- Postfix
- Dovecot
- Apache
- Roundcube
- Local Linux authentication

For that reason, controls that could interfere with those components were intentionally excluded from automated remediation.
The hardening process specifically avoided automatically modifying:
  - PAM authentication
  - pam_faillock
  - pam_pwquality
  - pam_pwhistory
  - sudoers
  - GRUB authentication
  - UFW/nftables firewall rules
  - Required Apache components
  - Required mail services

This allowed the server to be hardened without blindly applying CIS recommendations that could make the lab unusable.
Some CIS failures were therefore treated as documented exceptions rather than automatically remediated controls.


------------------------------------------------------------------

### 10.Bash Hardening Automation

A Bash hardening script was created for a selected group of relatively low-risk CIS controls.

The script was stored as:
  /home/sysadmin/cis-hardening.sh

Before execution, the script was made executable:
  chmod +x ~/cis-hardening.sh

Its Bash syntax was checked first:
  bash -n ~/cis-hardening.sh

After successful validation, it was executed with:
  sudo ~/cis-hardening.sh



The hardening script was designed to:
  - Back up configuration files before modifying them.
  - Avoid duplicate settings when run multiple times.
  - Make selected CIS-aligned configuration changes.
  - Avoid services considered high-risk to modify automatically.
  - Validate SSH configuration before applying SSH-related changes.
  - This allowed the script to act as a repeatable hardening tool rather than a collection of one-time shell commands.

This allowed the script to act as a repeatable hardening tool rather than a collection of one-time shell commands.

The first run-through was intentionally designed to run through a few failures and designed more as a framework that would receive more modular installations for each CIS section 
------------------------------------------------------------------

### 11. SSH Hardening Validation

SSH idle-session settings were included in the hardening work.
The resulting configuration was checked with:
  sudo sshd -T | grep -E 'clientaliveinterval|clientalivecountmax'

Expected values were:
  clientaliveinterval 300
  clientalivecountmax 3

Before SSH configuration changes were reloaded, syntax validation was performed with:
  sudo sshd -t

This reduced the risk of accidentally applying a configuration that would prevent future SSH access.

------------------------------------------------------------------

### 12. Kernel Network Hardening
Selected network kernel parameters were also hardened.

For example, logging of suspicious network packets was verified using:
  sysctl net.ipv4.conf.all.log_martians
  sysctl net.ipv4.conf.default.log_martians

The expected value was:
  1
  
------------------------------------------------------------------

### 13. AIDE File Integrity Monitoring

AIDE was installed as another CIS remediation:
  sudo apt install aide
  sudo aideinit

AIDE provides a baseline that can later be used to detect unexpected modifications to files on the system.

------------------------------------------------------------------


### 14. Regression Testing

Hardening is only useful if the required server functionality continues to work.
After applying changes, I checked the main services:
  sudo systemctl status ssh postfix dovecot apache2 --no-pager


I also re-tested:
  - SSH connectivity from the Windows host
  - Postfix mail delivery
  - Dovecot mailbox access
  - Roundcube login
  - Roundcube sending and receiving
  - Apache web access
  - SSH configuration
  - Selected kernel parameters
  - 
The services continued operating after the selected hardening changes.

------------------------------------------------------------------

### 15. Post-Hardening Audit
  
Ubuntu Security Guide was run again after remediation:
  sudo usg audit cis_level1_server
  
The new report was compared with the original baseline.

During iterative hardening, the number of medium-severity findings dropped from approximately:
87 -> 75 -> 73

The project intentionally did not aim for a perfect CIS score.
Instead, the objective was to improve the system's security posture while preserving all required mail-server functionality.

------------------------------------------------------------------

### 16. Documented Exceptions
Not every CIS recommendation is appropriate for every environment.
  ####GRUB Password
    GRUB password protection was intentionally excluded.
    For a local VirtualBox lab, adding a separate bootloader password would complicate VM recovery while providing relatively little practical benefit for the scope of this project.

  ####PAM Authentication
    PAM hardening controls were excluded from automated remediation because local Linux accounts were being used by SSH and Dovecot.
    Changing the PAM stack without sufficient testing could have prevented legitimate authentication.

  ####Firewall Rules
    Firewall rules were also kept outside the automated script.
    Incorrect firewall configuration could have blocked:
      - SSH
      - SMTP
      - IMAP
      - HTTP

A future version of the project could implement and separately test a least-privilege firewall policy.

------------------------------------------------------------------

### 17. Project Results
This project demonstrated the complete process of:
- Deploying an Ubuntu Server VM.
- Configuring remote SSH administration.
- Establishing a CIS-aligned security baseline.
- Installing and configuring Postfix.
- Installing and configuring Dovecot.
- Deploying Roundcube through Apache.
- Troubleshooting Apache and SMTP configuration.
- Building repeatable Bash hardening automation.
- Performing targeted manual remediation.
- Validating services after configuration changes.
- Re-running the security audit to measure improvement.
- Documenting accepted security exceptions instead of blindly chasing a perfect benchmark score.

The final environment remained functional while reducing the number of CIS security findings.

------------------------------------------------------------------

#### Repository Structure
.
├── README.md
├── scripts/
│   └── cis-hardening.sh
├── reports/
│   ├── pre-hardening/
│   └── post-hardening/
└── docs/
    └── screenshots/
    
Sensitive information, things like credentials, VM state files, and Ubuntu Pro tokens are not included in the repository.

------------------------------------------------------------------
#### Future Improvements
- Possible future improvements include:
- Further modularizing the hardening script.
- Adding automated regression tests.
- Implementing a carefully tested UFW ruleset.
- Adding TLS to the mail and web services.
- Expanding AIDE monitoring.
- Continuing to remediate low-risk CIS findings.
- Comparing pre- and post-hardening audit results automatically.








