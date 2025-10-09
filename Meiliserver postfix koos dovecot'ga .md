**Jah, Valdo — siin on samm-sammuline juhend, kuidas seadistada Debian serveril Postfix + Dovecot meiliserver domeenile `minumeil.ee`, koos SPF, DKIM, DMARC, IMAP/POP3 ja TLS-iga.** See juhend sobib hästi õpetamiseks ja dokumenteerimiseks, ning sisaldab ka DNS-kirjete näiteid.

---

## 🧱 1. Eeltingimused

- Debian 13 server (nt IP: `10.0.200.100`)
- Domeen: `minumeil.ee`
- Hostinimi: `mail.minumeil.ee`
- DNS haldusvõimalus (SPF, DKIM, DMARC kirjed)
- Portide avamine: TCP 25, 587, 993, 995

---

## 📦 2. Paigalda vajalikud paketid

```bash
sudo apt update
sudo apt install postfix dovecot-core dovecot-imapd dovecot-pop3d mailutils certbot python3-certbot-nginx opendkim opendkim-tools
```

Vali Postfixi installimisel *Internet Site* ja sisesta domeeniks `minumeil.ee`.

---

## 🔐 3. TLS sertifikaat (Let's Encrypt)

```bash
sudo certbot certonly --standalone -d mail.minumeil.ee
```

Sertifikaadid asuvad:  
- `/etc/letsencrypt/live/mail.minumeil.ee/fullchain.pem`
- `/etc/letsencrypt/live/mail.minumeil.ee/privkey.pem`

---

## 📬 4. Postfix konfiguratsioon

Muuda `/etc/postfix/main.cf`:

```conf
myhostname = mail.minumeil.ee
mydomain = minumeil.ee
myorigin = /etc/mailname
inet_interfaces = all
inet_protocols = ipv4
mydestination = $myhostname, localhost.$mydomain, localhost
home_mailbox = Maildir/
smtpd_tls_cert_file=/etc/letsencrypt/live/mail.minumeil.ee/fullchain.pem
smtpd_tls_key_file=/etc/letsencrypt/live/mail.minumeil.ee/privkey.pem
smtpd_use_tls=yes
smtpd_tls_auth_only = yes
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
```

---

## 📥 5. Dovecot konfiguratsioon

Muuda `/etc/dovecot/conf.d/10-mail.conf`:

```conf
mail_location = maildir:~/Maildir
```

Muuda `/etc/dovecot/conf.d/10-auth.conf`:

```conf
disable_plaintext_auth = yes
auth_mechanisms = plain login
```

Muuda `/etc/dovecot/conf.d/10-master.conf`:

```conf
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
```

Muuda `/etc/dovecot/conf.d/10-ssl.conf`:

```conf
ssl = required
ssl_cert = </etc/letsencrypt/live/mail.minumeil.ee/fullchain.pem
ssl_key = </etc/letsencrypt/live/mail.minumeil.ee/privkey.pem
```

---

## 🔏 6. DKIM seadistus

```bash
sudo mkdir -p /etc/opendkim/keys/minumeil.ee
cd /etc/opendkim/keys/minumeil.ee
sudo opendkim-genkey -s default -d minumeil.ee
```

Lisa `default._domainkey.minumeil.ee` DNS TXT kirje:

```
default._domainkey IN TXT "v=DKIM1; k=rsa; p=PUBLICKEY"
```

Muuda `/etc/opendkim.conf`:

```conf
Domain                  minumeil.ee
KeyFile                 /etc/opendkim/keys/minumeil.ee/default.private
Selector                default
Socket                  inet:12301@localhost
Canonicalization        relaxed/simple
Mode                    sv
Syslog                  yes
```

Muuda `/etc/default/opendkim`:

```conf
SOCKET="inet:12301@localhost"
```

Postfixi `main.cf` lisa:

```conf
milter_default_action = accept
milter_protocol = 2
smtpd_milters = inet:localhost:12301
non_smtpd_milters = inet:localhost:12301
```

---

## 🛡️ 7. SPF ja DMARC DNS kirjed

Lisa DNS halduses:

```
@ IN TXT "v=spf1 mx a -all"
_dmarc IN TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@minumeil.ee"
```

---

## 👤 8. Kasutaja ja testimine

```bash
sudo adduser valdo
```

Logi sisse ja testi:

```bash
echo "Tere!" | mail -s "Test" valdo@minumeil.ee
```

---

## ✅ Kokkuvõte

| Komponent | Seadistus |
|----------|-----------|
| Postfix | SMTP + TLS |
| Dovecot | IMAP + POP3 |
| SPF | `v=spf1 mx a -all` |
| DKIM | `default._domainkey` TXT |
| DMARC | `_dmarc` TXT |
| TLS | Let's Encrypt |
| Domeen | `minumeil.ee` |
| Hostinimi | `mail.minumeil.ee` |

Allikas: [GitHub Postfix+Dovecot+SPF+DKIM juhend](https://gist.github.com/howyay/57982e6ba9eedd3a5662c518f1b985c7), [TecAdmin DKIM seadistus](https://tecadmin.net/setup-dkim-with-postfix-on-ubuntu-debian/), [LinuxBabe SPF & DKIM juhend](https://www.linuxbabe.com/mail-server/spf-dkim-postfix-debian-server)

Kui soovid, võin koostada ka automaatse Bash installiskripti või lisada Roundcube veebiklienti. Kas soovid?
