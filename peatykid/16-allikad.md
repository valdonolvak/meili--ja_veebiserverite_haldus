## 16. Allikad ja lisalugemine

### Ametlik dokumentatsioon

| Teema | Allikas |
| --- | --- |
| Kea DHCP | [Kea Administrator Reference Manual](https://kea.readthedocs.io/), `man kea-dhcp4` |
| ISC DHCP lõpp | [ISC DHCP Server has reached EOL](https://www.isc.org/blogs/isc-dhcp-eol/) |
| Proxmox SDN | [Proxmox VE: Software-Defined Network](https://pve.proxmox.com/wiki/Software-Defined_Network) |
| Apache2 virtuaalhostid | [Apache HTTP Server: Virtual Host documentation](https://httpd.apache.org/docs/2.4/vhosts/) |
| Apache2 SSL | [Apache: SSL/TLS Strong Encryption How-To](https://httpd.apache.org/docs/2.4/ssl/ssl_howto.html) |
| WordPress | [WordPress: How to install WordPress](https://developer.wordpress.org/advanced-administration/before-install/howto-install/), [Hosting handbook](https://make.wordpress.org/hosting/handbook/) |
| MariaDB | [MariaDB: Configuring for remote client access](https://mariadb.com/docs/server/mariadb-quickstart-guides/configuring-mariadb-for-remote-client-access-guide) |
| BIND9 | [BIND 9 Administrator Reference Manual](https://bind9.readthedocs.io/) |
| Postfix | [Postfix documentation](https://www.postfix.org/documentation.html): `BASIC_CONFIGURATION_README`, `SASL_README`, `TLS_README`, `SMTPD_ACCESS_README`, `STANDARD_CONFIGURATION_README` (relayhost), `postconf(5)` |
| Dovecot 2.3 | [Dovecot 2.3 documentation](https://doc.dovecot.org/2.3/) – **NB! uus doc.dovecot.org avaleht on 2.4 kohta** |
| OpenDKIM | `man opendkim.conf`, [opendkim.org](http://www.opendkim.org/) |
| Roundcube | [Roundcube wiki: Configuration](https://github.com/roundcube/roundcubemail/wiki/Configuration) |
| fail2ban | `man jail.conf`, [fail2ban wiki](https://github.com/fail2ban/fail2ban/wiki) |
| Ubuntu netplan | [netplan documentation](https://netplan.readthedocs.io/) |
| Ubuntu meiliserver | [Ubuntu Server: Mail services](https://documentation.ubuntu.com/server/how-to/mail-services/) |

### Standardid (RFC)

| RFC | Teema |
| --- | --- |
| RFC 2131 | DHCP |
| RFC 2132 | DHCP valikud (options) |
| RFC 5321 | SMTP protokoll |
| RFC 5322 | E-kirja vorming (päised) |
| RFC 6409 | Kirjade saatmine kliendilt (*submission*, port 587) |
| RFC 8314 | Implicit TLS e-postile (465, 993) |
| RFC 9051 | IMAP4rev2 |
| RFC 7208 | SPF |
| RFC 6376 | DKIM |
| RFC 7489 | DMARC |
| RFC 6762 | mDNS ja `.local` domeen |

### Repo varasemad juhendid

| Juhend | Seos peatükiga |
| --- | --- |
| [Veebiserveri Apache ja Wordpressi paigaldus](../Veebiserver/1.%20Veebiserveri%20Apache%20ja%20Wordpressi%20paigaldus.md) | 4, 5 |
| [Peamised vead ja nende lahendus](../1a.%20Veebiserveri%20ja%20Wordpressi%20paigalduse%20peamised%20vead%20ja%20nende%20lahendus.md) | 14 |
| [Kasutaja sudo gruppi lisamine](../Veebiserver/1b.%20Kasutaja%20sudo%20gruppi%20lisamine.md) | 2 |
| [Wordpressi paigaldus teisele serverile](../Veebiserver/Iseseisevt%C3%B6%C3%B6/Wordpressi%20paigaldus%20teisele%20serverile.md) | 6 |
| [Võrgu seadistamine Debianil](../V%C3%B5rgu%20seadistamine%20Debianil.md) | 2 |
| [Nimeserver Bind9 seadistamine](../Nimeserver%20Bind9%20seadistamine.md), [DNS-Bind9](../Epost_DNS/DNS-Bind9.md) | 3 |
| [DDNS-DHCP](../Epost_DNS/DDNS-DHCP.md) | 4 (lisateema) |
| [Apache2 ja Wordpressi turvalisuse tõstmine koos HTTPS seadistusega](../Turvalisus/Apache2%20ja%20Wordpressi%20turvalisuse%20t%C3%B5stmine%20koos%20HTTPS%20seadistusega.md) | 7 |
| [Ründed veebiserveritele](../Turvalisus/R%C3%BCnded%20veebiserveritele.md) | 7, 10 |
| [E-posti server Postfix ja Dovecot](../Epost_DNS/1.%20E-posti%20server%20Postfix%20ja%20Dovecot.md) | 9 |
| [Välise e-posti serveri seadistus koos SPF, DMARC'i ja DKIM'ga](../Epost_DNS/2.%20V%C3%A4lise%20e-posti%20serveri%20seadistus%20%28Postfix%20ja%20Dovecot%29%20koos%20SPF%2C%20DMARC'i%20ja%20DKIM'ga.md) | 10 |
| [Meiliserveri paigaldus (MySQL, Postfix, Dovecot)](../Postfix-Dovecot/Meiliserveri%20paigaldus%20%28MySQL%2CPostfix%2CDovecot%29.md) | 8 (virtuaalkasutajad, lisateema) |
