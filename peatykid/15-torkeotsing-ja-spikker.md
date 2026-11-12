## 15. Tõrkeotsing ja käskude spikker

### 15.1 Tõrkeotsingu meetod

Ära muuda seadistust huupi. Liigu kihtide kaupa alt üles ja kontrolli igal kihil üht asja:

| Kiht | Küsimus | Käsk |
| --- | --- | --- |
| 0. Aadress | Kas kliendil on õige aadress? (mitte `169.254.x.x`) | Windowsis `ipconfig /all` |
| 1. Võrk | Kas masin on kättesaadav? | `ping 192.168.XXX.20` |
| 2. DNS | Kas nimi lahendub õigeks IP-ks? | `dig +short mail.perenimi.local`, Windowsis `nslookup` |
| 3. Teenus | Kas teenus töötab? | `systemctl status <teenus>` |
| 4. Port | Kas teenus kuulab õigel pordil? | `sudo ss -tlnp` |
| 5. Tulemüür | Kas port on lubatud? | `sudo ufw status`; teisest masinast `nc -vz 192.168.XXX.20 587` |
| 6. Seadistus | Kas süntaks on õige? | `apache2ctl configtest`, `named-checkconf`, `postfix check`, `doveconf -n` |
| 7. Logi | Mida teenus ise ütleb? | `journalctl -u <teenus>`, `/var/log/mail.log`, Apache error-log |

> **Esimene samm on alati logi.** Logis on peaaegu alati kirjas täpne põhjus – sageli koos failinime ja reanumbriga.

### 15.2 Logid ühes kohas

| Teenus | Masin | Logi |
| --- | --- | --- |
| Kea DHCP | Debian | `sudo journalctl -u kea-dhcp4-server -n 50`, rendid `/var/lib/kea/kea-leases4.csv` |
| BIND9 | Debian | `sudo journalctl -u named -n 50` |
| Apache2 | Debian, Ubuntu | `/var/log/apache2/<sait>_error.log`, `/var/log/apache2/error.log` |
| MariaDB | Debian (wp), Ubuntu (blogi) | `sudo journalctl -u mariadb` |
| Postfix, Dovecot, OpenDKIM | Ubuntu | `/var/log/mail.log` |
| Roundcube | Ubuntu | `/var/log/roundcube/errors.log` |
| fail2ban | Ubuntu | `/var/log/fail2ban.log` |
| SSH | kõik | `sudo journalctl -u ssh` |

### 15.3 DNS

| Sümptom | Põhjus | Lahendus |
| --- | --- | --- |
| `dig` → `status: SERVFAIL` oma tsooni nimele | tsooni ei laetud | `sudo journalctl -u named` → otsi `zone perenimi.local/IN: not loaded due to errors`; `named-checkzone` |
| `status: REFUSED` | päring tuleb väljastpoolt ACL-i | `allow-query`/`allow-recursion` ACL (3.4) |
| muudatus ei paista | tsoon laadimata või kliendi vahemälu (TTL) | `rndc reload perenimi.local`, `dig @192.168.XXX.10 …` (küsi otse serverilt), Windowsis `ipconfig /flushdns` |
| logis `zone serial … unchanged` | seerianumber suurendamata | suurenda serial – muidu teisesed serverid ei uuenda |
| välisnimed ei lahendu, `broken trust chain` logis | DNSSEC ja edastaja | `dnssec-validation no;` (3.4) |
| nimi lahendub vale IP-ks Windowsis | `hosts` failis vana rida | kontrolli `C:\Windows\System32\drivers\etc\hosts` |
| Ubuntu: `resolvectl query` → „No appropriate name servers“ | `.local` läheb mDNS-i | netplanis `search: [perenimi.local]` (2.5) |
| tsoonifailis nimi kujul `mail.perenimi.local.perenimi.local` | FQDN-i lõpust puudub punkt | lisa punkt |

### 15.4 DHCP

| Sümptom | Põhjus | Lahendus |
| --- | --- | --- |
| Windowsi aadress `169.254.x.x` | DHCP-server ei vastanud | `systemctl status kea-dhcp4-server`; liides `interfaces`-is; VM õiges vnetis |
| `kea-dhcp4 -t`: `syntax error … line N` | JSON viga: koma, jutumärk, sulg | paranda näidatud rida |
| `interface 'ens18' doesn't exist in the system` | vale liidese nimi | `ip -br link` |
| *DHCP Server* ei ole `192.168.XXX.10` | teine DHCP-server (Proxmox SDN) | SDN subnet → DHCP Ranges tühjaks (4.4) |
| Aadress on, nimed ei lahendu | `domain-name-servers` puudub | `ipconfig /all` → *DNS Servers* |
| Aadress on, internet ei tööta | `routers` puudub | `ipconfig /all` → *Default Gateway* |
| `DHCP4_ALLOC_ENGINE_V4_ALLOC_FAIL` | vahemik otsas | suurenda `pools` |
| `DHCP4_DECLINE_LEASE` | klient leidis, et aadress on juba kasutusel | vahemik kattub staatiliste aadressidega |
| `ipconfig /renew`: *unable to contact your DHCP server* | Kea maas; vana rent kehtib edasi | käivita Kea; `ipconfig /release` + `/renew` |

> Andmebaasipõhise meiliserveri (Osa III) tõrkeotsing on peatükis [20.5](20-osa3-haldus-laborid-torkeotsing.md#205-tõrkeotsing).

### 15.5 Apache ja WordPress

| Sümptom | Põhjus | Lahendus |
| --- | --- | --- |
| Näed „Apache2 Debian Default Page“ | `000-default` lubatud või sait lubamata | `a2dissite 000-default`, `a2ensite …`, `apache2ctl -S` |
| Vale sait avaneb | `ServerName` kirjaviga, DNS osutab valesse masinasse | `apache2ctl -S`, `curl -H "Host: …"` |
| 403 Forbidden | puudub `Require all granted` või õigused | vhost `<Directory>`, `namei -l /var/www/…/index.php` |
| PHP kood kuvatakse tekstina / laaditakse alla | `libapache2-mod-php` puudub | paigalda, `systemctl restart apache2` |
| „Error establishing a database connection“ | `wp-config.php` andmed, MariaDB maas, kaug-DB lukk kinni | käsurea test `mariadb -h … -u … -p` (7.6) |
| Postitused annavad 404 | `rewrite` moodul või `AllowOverride All` puudub | `a2enmod rewrite`, vhost |
| WordPress küsib FTP andmeid | `www-data` ei saa kirjutada | `chown -R www-data:www-data`, `FS_METHOD` |
| HTTPS-il suunamiste ring / stiilid puuduvad | `siteurl` on `http://` | 8.12 |
| `AH00526: Syntax error … Invalid command 'SSLEngine'` | `ssl` moodul puudub | `a2enmod ssl` |
| `Invalid command 'Header'` | `headers` moodul puudub | `a2enmod headers` |
| `configtest` viga rea lõpus oleva `#` tõttu | Apache ei luba rea-lõpu kommentaare | tõsta kommentaar eraldi reale |

### 15.6 Postfix

| Logis / vastuses | Põhjus | Lahendus |
| --- | --- | --- |
| `warning: SASL: Connect to private/auth failed: No such file or directory` | Dovecoti auth sokkel puudub | `local.conf` `service auth`, `systemctl restart dovecot`, `ls /var/spool/postfix/private/` |
| `status=deferred (connect to …[private/dovecot-lmtp]: No such file or directory)` | Dovecot LMTP maas / sokkel puudub | `dovecot-lmtpd` paigaldatud? `protocols = imap lmtp` |
| `lmtp … 550 5.1.1 User doesn't exist` | Linuxi kasutajat pole või `auth_username_format` puudub | `id mari`, `doveadm user mari` |
| `554 5.7.1 Relay access denied` saatmisel kliendist | klient pole autenditud (kasutab porti 25) | kasuta porti 587 koos AUTH-iga |
| `504 5.5.2 … Helo command rejected: need fully-qualified hostname` | HELO piirang kehtib ka autenditud kliendile | `smtpd_helo_restrictions` algus `permit_mynetworks, permit_sasl_authenticated` (10.5) |
| `553 5.7.1 Sender address rejected: not owned by user` | saatja ≠ sisseloginud kasutaja | õige saatja; `login_maps.regexp` |
| `450 4.1.8 Sender address rejected: Domain not found` | saatja domeen ei lahendu | DNS (`dig MX`), Ubuntu nimeserver |
| `warning: connect to Milter service inet:127.0.0.1:8891: Connection refused` | OpenDKIM maas | `systemctl status opendkim` |
| `fatal: /etc/postfix/master.cf: line N: bad field count` | `-o` rida ei alga tühikuga või puudub veerg | 10.6 |
| `warning: … hash:/etc/postfix/… is unavailable` | `postmap` tegemata | `sudo postmap /etc/postfix/<fail>` |
| `status=bounced (SMTPUTF8 is required, but was not offered by host …[private/dovecot-lmtp])` | täpitähtedega pealkiri, Dovecot 2.3 LMTP ei toeta SMTPUTF8-t | `postconf -e 'smtputf8_enable = no'` (10.3) |
| `SASL authentication failure: No worthy mechs found` (relay) | `libsasl2-modules` puudub | 13.4 |

Kasulikud käsud:

```bash
sudo postfix check                  # seadistuse kontroll
postconf -n                         # kõik vaikeväärtusest erinevad seaded
postconf mynetworks                 # ühe seade väärtus
mailq                               # järjekord
sudo postqueue -f                   # proovi järjekorras olevad kohe uuesti
sudo postcat -q 7DC7EC4886          # näita järjekorras oleva kirja sisu
sudo postsuper -d 7DC7EC4886        # kustuta üks kiri järjekorrast
sudo postsuper -d ALL deferred      # kustuta kõik edasilükatud
sudo grep 7DC7EC4886 /var/log/mail.log
```

### 15.7 Dovecot

| Logis / sümptom | Põhjus | Lahendus |
| --- | --- | --- |
| `doveconf: Fatal: Error in configuration file … line N` | süntaksiviga | rea number on kirjas |
| `ssl_cert: Can't open file … ` / `doesn't have SSL certificate` | tee vale või `<` puudub | `ssl_cert = </etc/ssl/certs/…` |
| `auth failed … (password mismatch)` | vale parool | `doveadm auth test mari` |
| `Disconnected (no auth attempts)` + klient: „Plaintext authentication disallowed“ | klient proovis ilma TLS-ita | klient: port 993 SSL/TLS |
| Roundcube: „Ühendus IMAP-serveriga ebaõnnestus“ | port 143 suletud, vale `imap_host`, sert | 12.3, `errors.log` |
| `Error: … Permission denied` Maildiris | kaust kuulub teisele kasutajale | `sudo chown -R mari:mari /home/mari/Maildir` |

```bash
sudo doveconf -n                    # efektiivne seadistus
sudo doveadm auth test mari
sudo doveadm user mari
sudo doveadm mailbox list -u mari
sudo doveadm who                    # kes on IMAP-is sees
sudo doveadm log errors             # viimased vead
```

### 15.8 OpenDKIM

| Sümptom | Põhjus | Lahendus |
| --- | --- | --- |
| `opendkim-testkey: … unexpected reply class/type (-1/-1)` | OpenDKIM ei leia DNS-ist võtit (libunbound) | `Nameservers 192.168.XXX.10` (11.4), `opendkim-testkey -x /etc/opendkim.conf …` |
| `key not secure` | tsoon pole DNSSEC-iga allkirjastatud | laboris normaalne, mitte viga |
| kirjal puudub `DKIM-Signature` | saatja domeen pole `signing.table`-is või IP pole `trusted.hosts`-is; milter pole ühendatud | `postconf smtpd_milters`, `grep opendkim /var/log/mail.log` |
| `can't load key from …: Permission denied` | võtme omanik vale | `chown -R opendkim:opendkim /etc/opendkim` |
| `opendkim-testmsg` ebaõnnestub | DNS-is vana võti või kirja on muudetud | võrdle `dig TXT s1._domainkey.perenimi.local` ja `s1.txt` |

### 15.9 TLS ja serdid

```bash
# Kes on serdi väljastaja, millised nimed, kehtivus
openssl s_client -connect mail.perenimi.local:993 -servername mail.perenimi.local </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates -ext subjectAltName

# STARTTLS pordil 587
openssl s_client -starttls smtp -connect mail.perenimi.local:587 </dev/null 2>/dev/null | grep "Verify return code"

# Kas sert ja võti kuuluvad kokku? (mõlemad räsid peavad ühtima)
openssl x509 -noout -modulus -in /etc/ssl/certs/mail.perenimi.local.crt | sha256sum
sudo openssl rsa -noout -modulus -in /etc/ssl/private/mail.perenimi.local.key | sha256sum
```

| `Verify return code` | Tähendus |
| --- | --- |
| `0 (ok)` | korras |
| `19 (self-signed certificate in certificate chain)` / `20 (unable to get local issuer certificate)` | CA pole selles masinas usaldatud → `update-ca-certificates` |
| `10 (certificate has expired)` | sert aegunud või masina kell vale (`timedatectl`) |

### 15.10 Käskude spikker

| Valdkond | Käsk | Mida teeb |
| --- | --- | --- |
| Võrk | `ip -br addr` / `ip route` | aadressid / marsruudid |
| DHCP | `sudo kea-dhcp4 -t /etc/kea/kea-dhcp4.conf` | seadistuse kontroll |
| | `sudo cat /var/lib/kea/kea-leases4.csv` | antud rendid |
| | Windowsis `ipconfig /release`, `/renew`, `/all` | loobu / küsi / vaata |
| | `sudo ss -tlnp` | kuulavad TCP pordid |
| | `nc -vz host port` | kas port on teisest masinast avatud |
| DNS | `dig +short nimi [tüüp]` | lühike vastus |
| | `dig @192.168.XXX.10 nimi` | küsi konkreetselt serverilt |
| | `dig -x IP` | pöördpäring |
| | `sudo rndc reload tsoon` | lae tsoon uuesti |
| Apache | `sudo apache2ctl configtest` | süntaksi kontroll |
| | `sudo apache2ctl -S` | vhostid ja vaikehost |
| | `sudo a2ensite / a2dissite / a2enmod` | luba / keela |
| | `curl -sI -H "Host: nimi" http://IP/` | päised konkreetsele vhostile |
| MariaDB | `sudo mariadb` | sisene root'ina |
| | `mariadb -h IP -u kasutaja -p andmebaas` | kaugühendus |
| | `SELECT user,host FROM mysql.user;` | kasutajad |
| Postfix | `sudo postconf -e 'seade = väärtus'` | muuda `main.cf` |
| | `postconf -n` | erinevad seaded |
| | `sudo postmap fail` | tee otsingutabel |
| | `mailq` / `sudo postqueue -f` | järjekord / saada uuesti |
| Dovecot | `sudo doveconf -n` | seadistus |
| | `sudo doveadm auth test kasutaja` | parooli test |
| SMTP test | `swaks --server … -p 587 -tls --auth-user … --from … --to …` | saada testkiri |
| | `openssl s_client -starttls smtp -connect host:587 -crlf` | käsitsi SMTP |
| IMAP test | `curl --url imaps://host/INBOX -u kasutaja -X "SEARCH ALL"` | IMAPS test |
| DKIM | `sudo opendkim-testkey -x /etc/opendkim.conf -d domeen -s s1 -vvv` | võtme kontroll |
| fail2ban | `sudo fail2ban-client status [vangla]` | blokeeritud IP-d |
| | `sudo fail2ban-client set vangla unbanip IP` | vabasta |
| Tulemüür | `sudo ufw status numbered` / `sudo ufw delete N` | reeglid / kustuta |

### 15.11 Enesekontrolli küsimused

1. Nimeta DHCP DORA neli sõnumit ja selgita, mida klient pärast neid teab.
2. Kirjelda e-kirja teekonda, kui Mari saadab Roundcube'ist kirja Jaanile. Nimeta iga lüli, protokoll ja port.
3. Mis vahe on MTA-l ja MDA-l? Mis programmid täidavad neid rolle laboris?
4. Mis on avatud relee? Kuidas testid, et sinu server seda pole?
5. Mis on DNS-is MX-kirje? Mis juhtub, kui seda pole?
6. Selgita SPF, DKIM ja DMARC erinevust ühe lausega igaühe kohta.
7. Miks sertifikaat kehtib nimele, mitte IP-aadressile? Mis juhtub, kui avad saidi IP-ga?
8. Mis vahe on STARTTLS-il ja implicit TLS-il? Too mõlema kohta port.
9. Miks peab andmebaasi kasutaja olema seotud konkreetse IP-ga?
10. Mida teeb `reject_sender_login_mismatch`?
11. Kirjelda, kuidas leiad `mail.log`-ist ühe kirja kogu teekonna.
12. Miks ei saa `.local` domeeniga meiliserver otse internetti kirju saata?
13. Mida tähendavad SMTP vastuskoodid 250, 354, 450, 554?

> Varasem tõrkeotsingu juhend: [Veebiserveri ja Wordpressi paigalduse peamised vead](../1a.%20Veebiserveri%20ja%20Wordpressi%20paigalduse%20peamised%20vead%20ja%20nende%20lahendus.md). Veebiserverite ründed: [Ründed veebiserveritele](../Turvalisus/R%C3%BCnded%20veebiserveritele.md).
