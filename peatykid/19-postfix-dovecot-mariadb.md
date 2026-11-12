## 19. Postfix ja Dovecot loevad andmebaasi (Ubuntu)

Peatükis 18 tegime andmebaasi valmis. Nüüd lülitame Postfixi ja Dovecoti selle peale ümber. Pärast seda peatükki:

- `perenimi.local` ja `pood.perenimi.local` postkastid on andmebaasis, kirjad kaustas `/var/vmail/`;
- uus postkast PostfixAdminis on **kohe** kasutatav (testitud: kasutaja `kati` loodi veebiliidesest, logis kohe Roundcube'i sisse ja saatis kirja, ühtegi teenust taaskäivitamata);
- kõik peatükkide 10–13 turvaseaded (TLS, SASL, relee keeld, DKIM, fail2ban, relay) jäävad kehtima.

> **Tee enne alustamist Ubuntust hetktõmmis** (`enne-sql`). Selles peatükis muudad töötava serveri sisemust; kui midagi läheb valesti, on tagasitee 10 sekundit.

Peatüki sammud:

| Samm | Mida teeme | Vahekontroll |
| --- | --- | --- |
| 19.1 | Paigaldame MySQL-i toe Postfixile ja Dovecotile | paketid olemas |
| 19.2 | Loome postkastide omaniku `vmail` | `id vmail` |
| 19.3 | Loome andmebaasi lugemiskasutaja | `SHOW GRANTS` |
| 19.4 | Kirjutame Postfixile 4 SQL-päringut | `postmap -q` iga päringu kohta |
| 19.5 | Lülitame Postfixi virtuaalpostkastidele | `postfix check`, `postconf -n` |
| 19.6 | Lülitame Dovecoti andmebaasile | `doveadm auth test`, `doveadm user` |
| 19.7 | Testime 8 olukorda | testide vastused |
| 19.8 | Kolime vanad kirjad | `doveadm search` |

### 19.1 Paigaldus

**Ubuntu:**

```bash
sudo apt install -y postfix-mysql dovecot-mysql
postconf -m | grep mysql          # mysql – Postfix oskab nüüd mysql:-tabeleid
```

Postfix ja Dovecot on moodulipõhised: andmebaasitugi on eraldi paketis, et ilma andmebaasita serverisse seda ei paigaldataks.

### 19.2 Postkastide omanik vmail

**Ubuntu:**

```bash
sudo groupadd -g 5000 vmail
sudo useradd -u 5000 -g vmail -s /usr/sbin/nologin -d /var/vmail -m vmail
sudo chmod 770 /var/vmail
ls -ld /var/vmail            # drwxrwx--- vmail vmail
```

| Valik | Miks |
| --- | --- |
| `-u 5000 -g 5000` | kindel number, mida kasutame ka Dovecoti seadistuses; kõrge number ei kattu tavakasutajatega (1000+) |
| `-s /usr/sbin/nologin` | sellena ei saa sisse logida |
| `-d /var/vmail -m` | kodukaust = kõigi postkastide juurkaust |
| `chmod 770` | teised kasutajad ei näe kirju |

### 19.3 Andmebaasi lugemiskasutaja

Postfix ja Dovecot vajavad andmebaasist ainult lugemisõigust (17.7).

**Ubuntu:**

```bash
sudo mariadb
```

```sql
CREATE USER 'mail_lugeja'@'localhost' IDENTIFIED BY 'Lugeja.Parool.2026';
GRANT SELECT ON postfixadmin.* TO 'mail_lugeja'@'localhost';
FLUSH PRIVILEGES;
SHOW GRANTS FOR 'mail_lugeja'@'localhost';
EXIT;
```

Kontroll: `mariadb -u mail_lugeja -p postfixadmin -e "SELECT username FROM mailbox;"` näitab postkaste; `… -e "DELETE FROM mailbox;"` annab vea `DELETE command denied` – nii peabki.

### 19.4 Postfixi SQL-päringud

Iga Postfixi otsingutabel (17.3) saab oma faili. Failis on andmebaasi ühenduse andmed ja üks päring. Postfix asendab `%s` küsitava väärtusega (aadress või domeen) ja võtab vastuseks päringu **esimese veeru**. Kui päring ei leia ridu, tähendab see „ei ole olemas“.

**Ubuntu:**

```bash
sudo mkdir -p /etc/postfix/sql
sudo nano /etc/postfix/sql/domeenid.cf
```

```text
# Kas domeen on meie hallata? (tabel domain)
user     = mail_lugeja
password = Lugeja.Parool.2026
hosts    = localhost
dbname   = postfixadmin
query    = SELECT domain FROM domain WHERE domain='%s' AND active = '1'
```

```bash
sudo nano /etc/postfix/sql/postkastid.cf
```

```text
# Kas sellele aadressile on postkast? (tabel mailbox)
user     = mail_lugeja
password = Lugeja.Parool.2026
hosts    = localhost
dbname   = postfixadmin
query    = SELECT maildir FROM mailbox WHERE username='%s' AND active = '1'
```

```bash
sudo nano /etc/postfix/sql/aliased.cf
```

```text
# Kuhu see aadress edasi suunatakse? (tabel alias)
user     = mail_lugeja
password = Lugeja.Parool.2026
hosts    = localhost
dbname   = postfixadmin
query    = SELECT goto FROM alias WHERE address='%s' AND active = '1'
```

```bash
sudo nano /etc/postfix/sql/saatjad.cf
```

```text
# Kes (SASL kasutaja) tohib seda saatja aadressi kasutada? Vastus: ainult postkasti omanik ise.
user     = mail_lugeja
password = Lugeja.Parool.2026
hosts    = localhost
dbname   = postfixadmin
query    = SELECT username FROM mailbox WHERE username='%s' AND active = '1'
```

Failides on andmebaasi parool, seega:

```bash
sudo chown root:postfix /etc/postfix/sql/*.cf
sudo chmod 640 /etc/postfix/sql/*.cf
```

| Fail | Postfixi seade | Küsitakse | Vastus (näide) |
| --- | --- | --- | --- |
| `domeenid.cf` | `virtual_mailbox_domains` | domeen | `perenimi.local` (vastuse sisu pole oluline, oluline on, et rida leiti) |
| `postkastid.cf` | `virtual_mailbox_maps` | aadress | `perenimi.local/mari/` |
| `aliased.cf` | `virtual_alias_maps` | aadress | `mari@perenimi.local,jaan@perenimi.local` |
| `saatjad.cf` | `smtpd_sender_login_maps` | saatja aadress | sisselogija, kellel on õigus: `mari@perenimi.local` |

`smtpd_sender_login_maps` päring tähendab: aadressilt `mari@perenimi.local` tohib saata ainult kasutaja, kes logis sisse nimega `mari@perenimi.local`. Aliaste (`info@`) nimel saata ei saa – see on teadlik valik.

**Vahekontroll** – küsi igalt tabelilt otse, enne kui Postfix neid kasutab:

```bash
sudo postmap -q perenimi.local       mysql:/etc/postfix/sql/domeenid.cf     # perenimi.local
sudo postmap -q pood.perenimi.local  mysql:/etc/postfix/sql/domeenid.cf     # pood.perenimi.local
sudo postmap -q mari@perenimi.local  mysql:/etc/postfix/sql/postkastid.cf   # perenimi.local/mari/
sudo postmap -q info@perenimi.local  mysql:/etc/postfix/sql/aliased.cf      # mari@perenimi.local,jaan@perenimi.local
sudo postmap -q mari@perenimi.local  mysql:/etc/postfix/sql/saatjad.cf      # mari@perenimi.local
sudo postmap -q olematu@perenimi.local mysql:/etc/postfix/sql/postkastid.cf; echo $?   # tühi, 1
```

Kui siin tuleb viga (`Access denied`, `Unknown column`), paranda enne edasi minemist – Postfixis näeksid sama viga ainult logis.

### 19.5 Postfix virtuaalpostkastidele

**Ubuntu:**

```bash
sudo cp /etc/postfix/main.cf /etc/postfix/main.cf.enne-sql

sudo postconf -e \
  'mydestination = $myhostname, localhost.$mydomain, localhost' \
  'virtual_mailbox_domains = proxy:mysql:/etc/postfix/sql/domeenid.cf' \
  'virtual_mailbox_maps = proxy:mysql:/etc/postfix/sql/postkastid.cf' \
  'virtual_alias_maps = proxy:mysql:/etc/postfix/sql/aliased.cf' \
  'virtual_transport = lmtp:unix:private/dovecot-lmtp' \
  'smtpd_sender_login_maps = proxy:mysql:/etc/postfix/sql/saatjad.cf'

sudo postconf -X mailbox_transport home_mailbox
sudo postfix check
```

| Seade | Miks |
| --- | --- |
| `mydestination` | **`$mydomain` eemaldatakse** – `perenimi.local` liigub virtual-klassi (17.2). Alles jääb `$myhostname` (`mail.perenimi.local`): serveri enda kirjad (`root@mail.perenimi.local`) toimetatakse kohalikult ja `/etc/aliases` suunab need edasi. Kui ka `$myhostname` eemaldada, saadetakse need relay'le! |
| `virtual_mailbox_domains` | millised domeenid on virtuaalpostkastidega – küsitakse andmebaasist |
| `virtual_mailbox_maps` | millised postkastid on olemas; tundmatu saaja lükatakse tagasi kohe |
| `virtual_alias_maps` | suunamised; kehtivad nii virtuaal- kui ka kohalikele domeenidele |
| `virtual_transport` | kõik virtuaalpostkastide kirjad Dovecotile LMTP-ga. (Varem tegi seda `mailbox_transport` ainult local-klassi jaoks.) |
| `smtpd_sender_login_maps` | asendab peatüki 10 regexp-faili |
| `postconf -X` | kustutab seaded, mis kehtisid ainult Linuxi kasutajatele |
| `proxy:` | Postfixil on palju protsesse; ilma `proxy:`-ta avaks igaüks oma andmebaasiühenduse. `proxymap` jagab ühendusi kõigi vahel. |

Serveri enda kirjad (cron, logiteated) suuname keskse halduri postkasti:

```bash
sudo nano /etc/aliases
```

```text
postmaster:    root
abuse:         root
root:          admin@perenimi.local
```

```bash
sudo newaliases
sudo systemctl reload postfix
```

> Ära veel teste tee – Dovecot otsib kasutajaid alles Linuxist. Kiri `mari@perenimi.local`-ile võetaks Postfixis vastu, kuid Dovecot ei leiaks postkasti.

### 19.6 Dovecot andmebaasile

Dovecotis tuleb vahetada **passdb** ja **userdb** (10.7): seni PAM ja `/etc/passwd`, nüüd SQL.

**1. Lülita autentimisallikas ümber.** Failis `conf.d/10-auth.conf` on read, mis valivad, kust kasutajad tulevad:

**Ubuntu:**

```bash
sudo cp /etc/dovecot/conf.d/10-auth.conf /etc/dovecot/conf.d/10-auth.conf.orig
sudo sed -i 's/^!include auth-system.conf.ext/#!include auth-system.conf.ext/; s/^#!include auth-sql.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf
grep -E '^#?!include auth-(system|sql)' /etc/dovecot/conf.d/10-auth.conf
# #!include auth-system.conf.ext
# !include auth-sql.conf.ext
```

`auth-sql.conf.ext` (paketi fail) ütleb: passdb ja userdb on SQL, seadistus failis `/etc/dovecot/dovecot-sql.conf.ext`.

**2. SQL-päringud:**

```bash
sudo nano /etc/dovecot/dovecot-sql.conf.ext
```

```text
# /etc/dovecot/dovecot-sql.conf.ext – Dovecot loeb kasutajad PostfixAdmini andmebaasist
driver = mysql
connect = host=localhost dbname=postfixadmin user=mail_lugeja password=Lugeja.Parool.2026

# PostfixAdmin salvestab paroolid kujul {SHA512-CRYPT}$6$...
default_pass_scheme = SHA512-CRYPT

# Sisselogimine: kas parool on õige?
password_query = SELECT username AS user, password FROM mailbox WHERE username = '%u' AND active = '1'

# Kus on postkast ja kelle õigustes sinna kirjutada?
user_query = SELECT CONCAT('/var/vmail/', maildir) AS home, 5000 AS uid, 5000 AS gid FROM mailbox WHERE username = '%u' AND active = '1'

# Kõigi kasutajate loend (doveadm ... -A)
iterate_query = SELECT username AS user FROM mailbox WHERE active = '1'
```

```bash
sudo chown root:dovecot /etc/dovecot/dovecot-sql.conf.ext
sudo chmod 640 /etc/dovecot/dovecot-sql.conf.ext
```

| Rida | Selgitus |
| --- | --- |
| `connect` | andmebaasi ühendus (sama lugemiskasutaja nagu Postfixil) |
| `default_pass_scheme` | kui räsil eesliidet pole, eelda SHA512-CRYPT-i. Meie räsidel on eesliide `{SHA512-CRYPT}`, seega on see varuvariant |
| `%u` | sisselogimisnimi (pärast `auth_username_format` teisendust) |
| `password_query` | tagastab veerud `user` ja `password`; Dovecot räsib sisestatud parooli ja võrdleb |
| `user_query` | tagastab `home` (postkasti kaust), `uid` ja `gid` (kelle õigustes kirjutada = `vmail`) |
| `iterate_query` | loend kõigist kasutajatest, nt `doveadm user '*'` (näitab kõiki kasutajaid) jaoks |

**3. Kolm muudatust failis `local.conf`:**

```bash
sudo cp /etc/dovecot/local.conf /etc/dovecot/local.conf.enne-sql
sudo nano /etc/dovecot/local.conf
```

| Oli | Muuda | Miks |
| --- | --- | --- |
| `mail_location = maildir:~/Maildir` | `mail_location = maildir:~/` | `home` on nüüd juba postkasti kaust `/var/vmail/perenimi.local/mari/` |
| `auth_username_format = %Ln` | `auth_username_format = %Lu` | `%Ln` lõikaks domeeni ära (`mari`), aga andmebaasis on `mari@perenimi.local`. `%Lu` = terve aadress väiketähtedega. **Kui see unustada, ebaõnnestub iga sisselogimine** (`auth failed`). |
| `mail_privileged_group = mail` | asenda kahe reaga: `first_valid_uid = 5000` ja `last_valid_uid = 5000` | Dovecot keeldub kirjutamast UID-dega, mis pole selles vahemikus – keegi ei saa andmebaasi kaudu panna Dovecotit root'i (UID 0) nimel faile kirjutama |

Ülejäänud `local.conf` (TLS, soklid Postfixile, kaustad) jääb samaks.

```bash
sudo doveconf -n > /dev/null && echo "seadistus OK"
sudo systemctl restart dovecot
```

**Vahekontroll:**

```bash
sudo doveadm auth test mari@perenimi.local          # küsib parooli → passdb: mari@perenimi.local auth succeeded
sudo doveadm user mari@perenimi.local
# uid 5000  gid 5000  home /var/vmail/perenimi.local/mari/  mail maildir:~/
sudo doveadm auth test mari                        # ilma domeenita → auth failed (andmebaasis on täisaadress)
```

### 19.7 Testimine

Logi teises aknas: `sudo tail -f /var/log/mail.log`. Testid on tehtud ja tulemused kontrollitud laboriga sama tarkvaraversiooniga.

```bash
# 1. Kiri postkasti (port 25, nagu teine server)
swaks --server 192.168.XXX.20 --helo test.perenimi.local --from x@perenimi.local --to mari@perenimi.local
#    <-  250 2.0.0 Ok: queued as …

# 2. Olematu saaja – tagasi kohe, SMTP ajal
swaks --server 192.168.XXX.20 --helo test.perenimi.local --from x@perenimi.local --to olematu@perenimi.local
#    <** 550 5.1.1 <olematu@perenimi.local>: Recipient address rejected: User unknown in virtual mailbox table

# 3. Alias kahele
swaks --server 192.168.XXX.20 --helo test.perenimi.local --from x@perenimi.local --to info@perenimi.local

# 4. Teine domeen
swaks --server 192.168.XXX.20 --helo test.perenimi.local --from x@perenimi.local --to myyk@pood.perenimi.local

# 5. Saatmine parooliga (kasutajanimi = täisaadress!)
swaks --server mail.perenimi.local -p 587 -tls --auth LOGIN \
      --auth-user mari@perenimi.local --auth-password 'mari-parool' \
      --from mari@perenimi.local --to jaan@perenimi.local
#    <~  235 2.7.0 Authentication successful   <~  250 2.0.0 Ok: queued

# 6. Võõra nimega (PEAB ebaõnnestuma)
swaks --server mail.perenimi.local -p 587 -tls --auth LOGIN \
      --auth-user jaan@perenimi.local --auth-password 'jaani-parool' \
      --from mari@perenimi.local --to jaan@perenimi.local
#    <~* 553 5.7.1 <mari@perenimi.local>: Sender address rejected: not owned by user jaan@perenimi.local

# 7. Teise domeeni postmaster → keskne admin
swaks --server 192.168.XXX.20 --helo test.perenimi.local --from x@perenimi.local --to postmaster@pood.perenimi.local

# 8. Relee keeld kehtib endiselt (PEAB ebaõnnestuma)
swaks --server 192.168.XXX.20 --helo test.example.org --from x@perenimi.local --to keegi@example.com
#    <** 554 5.7.1 <keegi@example.com>: Relay access denied
```

Kus kirjad on:

```bash
sudo find /var/vmail -path '*/new/*' -type f | sed 's|/new/.*||' | sort | uniq -c
#   1 /var/vmail/pood.perenimi.local/myyk
#   1 /var/vmail/perenimi.local/admin
#   2 /var/vmail/perenimi.local/jaan
#   2 /var/vmail/perenimi.local/mari
```

Logis näeb aliase lahendamist väljal `orig_to`:

```text
postfix/lmtp[…]: …: to=<admin@perenimi.local>, orig_to=<postmaster@pood.perenimi.local>, relay=mail.perenimi.local[private/dovecot-lmtp], … status=sent
```

**Roundcube:** sisselogimine `mari` (Roundcube lisab `@perenimi.local`, `username_domain`, 12.3) või täisaadressiga. Teise domeeni kasutaja logib sisse **täisaadressiga** `myyk@pood.perenimi.local`. Roundcube'i seadistust muuta ei ole vaja – Roundcube ainult edastab nime ja parooli Dovecotile.

**Thunderbird:** kasutajanimi peab nüüd olema **täisaadress**.

**Uus kasutaja ilma taaskäivituseta:** lisa PostfixAdminis postkast `kati@perenimi.local` ja logi kohe Roundcube'i sisse – töötab, sest iga sisselogimine ja iga kiri teeb värske SQL-päringu.

### 19.8 Vanade kirjade kolimine

Linuxi kasutajate kirjad on alles kaustas `/home/<kasutaja>/Maildir`. Kuna mõlemad on Maildir-vormingus, piisab kopeerimisest ja omaniku muutmisest.

**Ubuntu:**

```bash
# vajadusel loo kaust (kui postkastile pole veel kirju tulnud)
sudo install -d -o vmail -g vmail -m 700 /var/vmail/perenimi.local/mari
sudo cp -a /home/mari/Maildir/. /var/vmail/perenimi.local/mari/
sudo chown -R vmail:vmail /var/vmail/perenimi.local/mari
sudo doveadm search -u mari@perenimi.local mailbox INBOX ALL | wc -l      # kirjade arv
```

Testis kasvas Mari postkasti kirjade arv pärast kopeerimist 5-lt 11-le ja kõik kaustad (Sent, Trash …) jäid alles. Tee sama Jaani jaoks. Kui kõik töötab, võib Linuxi kasutajad eemaldada: `sudo deluser --remove-home mari` (alles pärast kontrolli!).

### 19.9 Mis muutus – kokkuvõte

`postconf -n` uued/muutunud read:

```text
mydestination = $myhostname, localhost.$mydomain, localhost
smtpd_sender_login_maps = proxy:mysql:/etc/postfix/sql/saatjad.cf
virtual_alias_maps = proxy:mysql:/etc/postfix/sql/aliased.cf
virtual_mailbox_domains = proxy:mysql:/etc/postfix/sql/domeenid.cf
virtual_mailbox_maps = proxy:mysql:/etc/postfix/sql/postkastid.cf
virtual_transport = lmtp:unix:private/dovecot-lmtp
```

Eemaldatud: `home_mailbox`, `mailbox_transport`. Fail `/etc/postfix/login_maps.regexp` pole enam kasutusel.

| Fail | Muutus |
| --- | --- |
| `/etc/postfix/main.cf` | virtual_* seaded, `mydestination` |
| `/etc/postfix/sql/*.cf` | uued: 4 SQL-päringut |
| `/etc/aliases` | `root` → `admin@perenimi.local` |
| `/etc/dovecot/conf.d/10-auth.conf` | `auth-system` → `auth-sql` |
| `/etc/dovecot/dovecot-sql.conf.ext` | uus: ühendus ja päringud |
| `/etc/dovecot/local.conf` | `mail_location`, `auth_username_format`, `first/last_valid_uid` |
| `/var/vmail/` | uus: kõik postkastid |
