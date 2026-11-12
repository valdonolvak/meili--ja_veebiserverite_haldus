## 20. Osa III: haldus, laborid ja tõrkeotsing

### 20.1 Igapäevased haldustööd

| Tegevus | Kus | Mis tegelikult juhtub |
| --- | --- | --- |
| Uus töötaja | PostfixAdmin → *Lisa postkast* | rida tabelisse `mailbox` + alias iseendale; postkasti kaust tekib esimese kirjaga |
| Töötaja lahkub, kirjad jäävad | PostfixAdmin → postkast → *Aktiivne* maha | `active = 0` mõlemas tabelis; sisse logida ja kirju saada ei saa, kirjad jäävad kettale |
| Kirjad kolleegile | postkasti *Alias* → lisa sihtaadress | `alias.goto` = `jaan@…,kolleeg@…` |
| Ühisaadress (`info@`, `tugi@`) | *Lisa alias* | rida tabelisse `alias` |
| Parool ununes | haldur: postkast → *Redigeeri* → uus parool; kasutaja ise: `/postfixadmin/users/` | uus räsi veergu `mailbox.password` |
| Uus domeen | 1) DNS: MX, SPF, DMARC (18.2) 2) PostfixAdmin → *Uus domeen* 3) DKIM (20.2) | rida tabelisse `domain` + vaikealiased |
| Domeenile oma haldur | *Haldajad → Lisa haldaja*, vali domeenid | rida tabelitesse `admin` ja `domain_admins` |
| Kes mida muutis? | *Vaata logi* | tabel `log` |

Ükski neist ei vaja Postfixi ega Dovecoti taaskäivitust.

### 20.2 DKIM teisele domeenile

OpenDKIM allkirjastab praegu ainult `*@perenimi.local` (peatükk 11.3). Kiri aadressilt `myyk@pood.perenimi.local` läheb välja allkirjata. Teise domeeni jaoks võib kasutada **sama võtit**, kuid `d=` peab olema selle domeeni nimi ja avalik võti peab olema selle domeeni DNS-is.

**Ubuntu:**

```bash
echo "s1._domainkey.pood.perenimi.local  pood.perenimi.local:s1:/etc/opendkim/keys/perenimi.local/s1.private" \
  | sudo tee -a /etc/opendkim/key.table
echo "*@pood.perenimi.local  s1._domainkey.pood.perenimi.local" \
  | sudo tee -a /etc/opendkim/signing.table
sudo systemctl restart opendkim
```

**Debian** – lisa tsooni sama avalik võti nimega `s1._domainkey.pood` (kopeeri `s1.txt` sisu ja muuda esimene sõna):

```text
s1._domainkey.pood  IN  TXT  ( "v=DKIM1; h=sha256; k=rsa; "
          "p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA…" )
```

Suurenda seerianumbrit, `named-checkzone`, `rndc reload`.

**Kontroll (Ubuntu):**

```bash
sudo opendkim-testkey -x /etc/opendkim.conf -d pood.perenimi.local -s s1 -vvv     # key OK
```

Saada kiri `myyk@pood.perenimi.local` nimel (Roundcube või swaks pordil 587) ja kontrolli saaja juures: `DKIM-Signature: … d=pood.perenimi.local; s=s1` ning `opendkim-testmsg` → allkiri kehtib. Testitud.

> Tootmises tehakse igale domeenile **oma võti** (`opendkim-genkey -d pood.perenimi.local …`), et ühe domeeni võtme lekkimine ei mõjutaks teisi.

### 20.3 Varundus

Andmebaasipõhisel serveril on kaks asja, mida varundada – kumbki ilma teiseta on kasutu:

| Mida | Kus | Käsk |
| --- | --- | --- |
| kasutajad, paroolid, aliased | MariaDB `postfixadmin` | `sudo mariadb-dump --single-transaction postfixadmin > postfixadmin-$(date +%F).sql` |
| kirjad | `/var/vmail` | `sudo tar -czf vmail-$(date +%F).tar.gz -C /var vmail` |
| seadistus | `/etc/postfix`, `/etc/dovecot`, `/etc/opendkim`, `/etc/postfixadmin` | `sudo tar -czf meil-etc-$(date +%F).tar.gz /etc/postfix /etc/dovecot /etc/opendkim /etc/postfixadmin` |

Taastamine: `sudo mariadb postfixadmin < postfixadmin-….sql` ja `sudo tar -xzf vmail-….tar.gz -C /var` (omanik jääb `vmail`, sest `tar` säilitab selle root'ina).

### 20.4 Laboritööd

| Labor | Teema | Peatükk | Aeg (ak h) |
| --- | --- | --- | --- |
| 13 | PostfixAdmin ja meiliandmebaas | 17–18 | 3 |
| 14 | Postfix ja Dovecot andmebaasi peale | 19 | 4 |
| 15 | Haldus, teine domeen, DKIM ja tõrkeotsing | 20 | 3 |

---

#### Labor 13. PostfixAdmin ja meiliandmebaas

**Eesmärk:** andmebaasis on kaks domeeni, neli postkasti ja aliased; neid hallatakse veebiliidesest. Meiliserver töötab veel vanamoodi.

**Sammud:**

1. Kontrolli, et peatüki 10 testid läbivad. Tee Ubuntust hetktõmmis `enne-osa-3`.
2. Lisa DNS-i domeen `pood.perenimi.local` (18.2).
3. Paigalda PostfixAdmin (18.3), vaata, mida dbconfig lõi.
4. Loo setup-parooli räsi ja `config.local.php` (18.4).
5. Lisa Apache vhosti `/postfixadmin` alias koos IP-piiranguga (18.5).
6. `setup.php`: keskkonnakontroll, tabelite loomine, superadministraator (18.6).
7. Loo domeenid `perenimi.local`, `pood.perenimi.local` (18.8).
8. Loo postkastid `admin`, `mari`, `jaan` (`perenimi.local`) ja `myyk` (`pood.perenimi.local`) (18.9).
9. Loo aliased `info@` (Mari + Jaan) ja `root@` (admin) (18.10).
10. Vaata andmebaasist kõiki kolme tabelit (18.11).
11. **Katse:** proovi lisada domeen `olematu.perenimi.local`. Mis viga ja miks?
12. **Katse:** ava `https://mail.perenimi.local/postfixadmin/` Ubuntust endast (`curl -s -o /dev/null -w "%{http_code}" …`) ja mõnelt IP-lt väljaspool `Require ip` loendit. Mis vahe?

**Kontrollpunkt:** veebiliides töötab; `SELECT username, maildir FROM mailbox` näitab nelja postkasti; paroolid algavad `{SHA512-CRYPT}$6$`.

**Küsimused:**

1. Mis vahe on PostfixAdmini superadministraatoril ja postkastil `admin@perenimi.local`?
2. Miks tuleb domeen enne DNS-i lisada?
3. Miks kirjutame seaded faili `config.local.php`, mitte `config.inc.php`?
4. Mis on parooliräsi kolm osa ja milleks on sool?
5. Miks loob PostfixAdmin iga postkasti kohta ka aliase iseendale?

---

#### Labor 14. Postfix ja Dovecot andmebaasi peale

**Eesmärk:** Postfix ja Dovecot loevad domeene, postkaste, aliasi ja paroole andmebaasist; kirjad on kaustas `/var/vmail`.

**Sammud:**

1. Tee hetktõmmis `enne-sql`.
2. Paigalda `postfix-mysql`, `dovecot-mysql` (19.1).
3. Loo `vmail` (19.2) ja `mail_lugeja` (19.3). Kontrolli, et `mail_lugeja` ei saa kustutada.
4. Loo 4 SQL-faili ja testi igaüks `postmap -q`-ga (19.4).
5. Muuda Postfixi seaded ja `/etc/aliases` (19.5).
6. Muuda Dovecoti `10-auth.conf`, loo `dovecot-sql.conf.ext`, muuda `local.conf` (19.6). Kontrolli `doveadm auth test` ja `doveadm user`.
7. Tee kõik 8 testi (19.7) ja kopeeri tulemused laboripäevikusse.
8. Logi Roundcube'i sisse kasutajatena `mari` ja `myyk@pood.perenimi.local`, saada kirju ristiti ja aliasele `info@`.
9. Kolige Mari ja Jaani vanad kirjad (19.8).
10. Lisa PostfixAdminis postkast `kati@perenimi.local` ja logi **kohe** Roundcube'i sisse. Kas pidid midagi taaskäivitama?

**Kontrollpunkt:** `sudo find /var/vmail -path '*/new/*' -type f | wc -l` > 0; test 2 annab `User unknown in virtual mailbox table`; test 6 annab `not owned by user`; test 8 annab `Relay access denied`.

**Küsimused:**

1. Mis vahe on Postfixi local- ja virtual mailbox-klassil? Miks ei tohi domeen olla mõlemas?
2. Miks jäeti `$myhostname` `mydestination`-isse?
3. Mis järjekorras teeb Postfix SQL-päringud, kui kiri tuleb aadressile `info@perenimi.local`?
4. Miks muudeti `auth_username_format` väärtuseks `%Lu`? Mis juhtub `%Ln`-iga?
5. Miks on Postfixil ja Dovecotil eraldi andmebaasikasutaja ainult SELECT-õigusega?
6. Miks ei olnud uue postkasti puhul taaskäivitust vaja?

---

#### Labor 15. Haldus, teine domeen, DKIM ja tõrkeotsing

**Eesmärk:** igapäevaste haldustööde tegemine, DKIM teisele domeenile, varundus ja vigade leidmine.

**Sammud:**

1. Lülita PostfixAdminis Jaani postkast välja. Saada talle kiri (swaks pordile 25). Mis vastus? Kas Jaan saab Roundcube'i sisse? Lülita tagasi.
2. **Võrdluskatse:** lülita Jaan välja **otse SQL-iga** ainult tabelis `mailbox` (`UPDATE mailbox SET active=0 WHERE username='jaan@perenimi.local';`). Saada uuesti kiri. Mis on vahe? Vaata logist `status=bounced`. Taasta mõlemad tabelid (18.11).
3. Tee Jaanile suunamine: tema kirjad lähevad nii talle kui ka Marile.
4. Lisa `pood.perenimi.local`-ile DKIM (20.2), kontrolli `opendkim-testkey` ja allkirja kirjas.
5. Loo haldur `pood-admin@perenimi.local`, kes haldab ainult `pood.perenimi.local`-i. Logi tema nimel sisse – mida ta näeb?
6. Kasutaja Mari vahetab ise parooli kasutaja portaalis (18.12); kontrolli, et Roundcube'i sisselogimine töötab uue parooliga kohe.
7. Tee varundus (20.3) ja kontrolli, et failid on olemas ja pole tühjad.
8. **Tõrkeotsing paaris:** kaaslane teeb ühe rikke tabelist 20.5, sina leiad selle logist.

**Küsimused:**

1. Miks on DKIM-i `d=` väärtus teisel domeenil teine, kuigi võti on sama? Miks tootmises tehakse eraldi võti?
2. Mis on *backscatter* ja kuidas see sammus 2 tekkis?
3. Mida pead varundama, et server pärast ketta riket taastada?

### 20.5 Tõrkeotsing

| Sümptom / logis | Põhjus | Lahendus |
| --- | --- | --- |
| PostfixAdmin: *Invalid domain …, and/or not discoverable in DNS* | domeenil pole DNS-is kirjeid | lisa MX (18.2), `dig MX domeen` |
| PostfixAdmin: valge leht / *500* | PHP viga `config.local.php`-s | `sudo php -l /etc/postfixadmin/config.local.php`; `/var/log/apache2/mail.perenimi.local_error.log` |
| PostfixAdmin: *403 Forbidden* | IP pole `Require ip` loendis | 18.5 |
| `setup.php`: *Password hashing … FAIL* | vale `encrypt` väärtus | 18.4 |
| `warning: do not list domain perenimi.local in BOTH mydestination and virtual_mailbox_domains` | `$mydomain` jäi `mydestination`-isse | 19.5 |
| `warning: connect to mysql server localhost: Access denied for user 'mail_lugeja'` | vale parool `.cf` failis või kasutajat pole | `mariadb -u mail_lugeja -p`; 19.3 |
| `warning: proxy:mysql:/etc/postfix/sql/…cf … table lookup problem` / `fatal: … Permission denied` | `.cf` fail pole Postfixile loetav | `chown root:postfix`, `chmod 640` |
| `550 5.1.1 … User unknown in virtual mailbox table` | postkasti pole või `active = 0` | PostfixAdmin; `postmap -q aadress mysql:…/postkastid.cf` |
| Kiri võeti vastu, siis `status=bounced (… User doesn't exist)` (LMTP) | `alias` aktiivne, `mailbox` mitte (SQL-iga muudetud) või Dovecoti `user_query` viga | 18.11; `doveadm user aadress` |
| `doveadm auth test` → `auth failed`, logis `unknown user` | `auth_username_format = %Ln` | `%Lu` (19.6) |
| Dovecot: `Error: … dovecot-sql.conf.ext: Permission denied` | faili õigused | `chown root:dovecot`, `chmod 640` |
| Dovecot: `Unknown scheme` / `Password mismatch` | räsi skeem ei sobi | `encrypt = php_crypt:SHA512::{SHA512-CRYPT}`; vaata `mailbox.password` algust |
| Dovecot: `Mail access for users with UID 1000 not permitted` | `user_query` tagastab vale UID või `first_valid_uid` | `5000 AS uid`; `first_valid_uid = 5000` |
| Dovecot: `mkdir(/var/vmail/…) failed: Permission denied` | `/var/vmail` omanik pole `vmail` | `chown vmail:vmail /var/vmail`, `chmod 770` |
| Roundcube: sisselogimine ebaõnnestub teise domeeni kasutajal | kasutaja sisestas ainult `myyk` → Roundcube lisas `@perenimi.local` | sisesta täisaadress |
| Cron/`root` kirjad lähevad relay'le | `$myhostname` eemaldati `mydestination`-ist | 19.5 |
| `553 … not owned by user` kuigi saadab oma aadressilt | Thunderbirdis kasutajanimi ilma domeenita | kasutajanimi = täisaadress |

Kasulikud käsud:

```bash
postmap -q mari@perenimi.local proxy:mysql:/etc/postfix/sql/postkastid.cf
sudo doveadm auth test mari@perenimi.local
sudo doveadm user mari@perenimi.local
sudo doveadm user '*'                                  # kõik kasutajad andmebaasist
sudo mariadb postfixadmin -e "SELECT username, active FROM mailbox; SELECT address, goto, active FROM alias;"
sudo grep -E "mysql|proxymap" /var/log/mail.log | tail
sudo grep -E "auth|sql" /var/log/mail.log | tail
```

### 20.6 Enesekontrolli küsimused

1. Too kolm põhjust, miks suured meiliteenused hoiavad kasutajaid andmebaasis, mitte operatsioonisüsteemis.
2. Mis on Postfixi aadressiklass ja millisesse klassi kuulub laboris `perenimi.local` enne ja pärast Osa III?
3. Kirjelda, mis juhtub (millised päringud, millised protsessid), kui väline server saadab kirja `postmaster@pood.perenimi.local`-ile.
4. Mis vahe on Dovecoti passdb-l ja userdb-l? Mida tagastab kumbki päring?
5. Miks kuuluvad kõik postkastid kasutajale `vmail`? Mis kaitseb selle eest, et keegi saaks Dovecotit root'ina kirjutama panna?
6. Miks ei tohi paroole hoida MD5 räsina ega avatekstina?
7. Miks on andmebaasis kaks kasutajat erinevate õigustega?
8. Miks tuleks muudatused teha veebiliidesest, mitte otse SQL-iga?
