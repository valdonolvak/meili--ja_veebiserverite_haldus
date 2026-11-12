## 10. Postfix ja Dovecot (Ubuntu)

Selles peatükis ehitame Ubuntu masinasse töötava meiliserveri: **Postfix** võtab kirju vastu ja saadab, **Dovecot** hoiab postkaste, kontrollib paroole ja annab kirjad IMAP-iga klientidele. Kõik ühendused on TLS-iga ja saata saab ainult sisseloginud kasutaja.

![Ubuntu meiliserveri sisemus](joonised/09-postfix-dovecot.png)

*Joonis 10.1: Postfixi ja Dovecoti koostöö*

> **Eeldused:** Ubuntu hostinimi on `mail`, `hostname -f` annab `mail.perenimi.local` (2.6); DNS-is on `mail` A-, MX- ja PTR-kirje (3.6–3.7); serdid on paigaldatud (8.8). Kontrolli: `dig +short perenimi.local MX` → `10 mail.perenimi.local.`

### Mida selles peatükis ehitame

Meiliserveril on kolm eri ülesannet, ja iga ülesande jaoks on eraldi „uks“ (port):

| Ülesanne | Kes tuleb | Port | Kes teenindab | Mida server kontrollib |
| --- | --- | --- | --- | --- |
| **Kirjade vastuvõtmine** teistelt serveritelt | võõras meiliserver (nt Gmail), kes toob kirja aadressile `mari@perenimi.local` | 25 | Postfix `smtpd` | kas saaja on **meie** domeenis; parooli ei küsita |
| **Kirjade saatmine** oma kasutajatelt | Roundcube, Thunderbird, Outlook | 587 (või 465) | Postfix `smtpd` (*submission*) | **TLS + parool** ja kas kasutaja saadab oma nime all |
| **Kirjade lugemine** | Roundcube, Thunderbird | 993 | Dovecot IMAP | TLS + parool |

Kõigi kolme ukse taga on üks ühine osa: **postkast** kettal (`/home/mari/Maildir/`). Postfix **kirjutab** sinna (Dovecoti LMTP kaudu), Dovecot **loeb** sealt kliendile ette.

Kaks näidet, mida peatüki lõpuks oskab server teha:

1. **Jaan saadab Marile.** Thunderbird ühendub pordile 587 → STARTTLS → Jaan logib sisse → Postfix küsib Dovecotilt „kas parool on õige?“ → Postfix kontrollib, et Jaan saadab aadressilt `jaan@perenimi.local` → saaja on meie domeenis → Postfix annab kirja LMTP-ga Dovecotile → Dovecot kirjutab faili `/home/mari/Maildir/new/` → Mari näeb kirja IMAP-iga.
2. **Võõras server proovib meie serverit spämmimiseks kasutada.** Ühendub pordile 25, ütleb `RCPT TO:<keegi@gmail.com>` → Postfix vastab `554 Relay access denied`, sest saaja pole meie domeenis ja saatja pole sisse loginud.

Peatüki sammud ja see, mida iga samm tõestab:

| Samm | Mida teeme | Kuidas kontrollime |
| --- | --- | --- |
| 10.2 | Paigaldame Postfixi ja Dovecoti | `systemctl status postfix dovecot`, port 25 kuulab |
| 10.3 | Ütleme Postfixile, kes ta on ja milliste domeenide post talle kuulub | `postconf -n` |
| 10.4 | Lülitame sisse krüpteerimise | `openssl s_client -starttls smtp` näitab serti |
| 10.5 | Määrame, kes tohib mida saata | `postmap -q` vastab õigesti |
| 10.6 | Avame klientidele pordid 587 ja 465 | `postfix check`, pordid kuulavad |
| 10.7 | Seadistame Dovecoti: postkastid, paroolid, soklid Postfixile | `doveconf -n`, soklid olemas |
| 10.8 | Loome kasutajad | `doveadm auth test` |
| 10.9 | Avame tulemüüri | `ufw status` |
| 10.10 | Teeme 8 testi – 5 peavad õnnestuma, 3 **peavad** ebaõnnestuma | testide vastused |

> **Kuidas seda peatükki lugeda.** Iga sammu juures on kõigepealt selgitus, siis käsud ja lõpus **vahekontroll**. Ära mine järgmise sammu juurde enne, kui vahekontroll annab oodatud tulemuse – nii leiad vea kohe, mitte alles lõpus kaheksa sammu tagant.

### 10.1 Mõisted

| Termin | Selgitus |
| --- | --- |
| `main.cf` | Postfixi üldseaded (`nimi = väärtus`). Muudame käsuga `postconf -e`, mis asendab olemasoleva rea, mitte ei lisa duplikaati. |
| `master.cf` | Postfixi teenused (protsessid) ja nende pordid; `-o` read kirjutavad `main.cf` seadeid ühe teenuse jaoks üle. |
| `mydestination` | Domeenid, mille kirjad toimetatakse **selles serveris** kohale. |
| `mynetworks` | Võrgud, mida Postfix usaldab ilma paroolita. **Ainult `127.0.0.0/8`** – muidu oleks labori võrk avatud relee. |
| SASL | *Simple Authentication and Security Layer* – kuidas klient tõestab, kes ta on. Postfix küsib parooli kontrolli Dovecotilt. |
| LMTP | *Local Mail Transfer Protocol* – SMTP lihtsustatud variant, millega Postfix annab kirja Dovecotile kohaletoimetamiseks. |
| Järjekord (*queue*) | Kirjad, mida pole veel ära saadetud. `mailq` näitab. |
| `smtpd` / `smtp` | Postfixi **server**pool (võtab vastu) / **klient**pool (saadab teistesse serveritesse). Seepärast on seadetel eesliited `smtpd_` ja `smtp_`. |
| Piirangud (*restrictions*) | Reeglite loend, mida kontrollitakse vasakult paremale; esimene `permit` või `reject` otsustab. |

#### Kuidas Postfix seest töötab

Postfix ei ole üks suur programm, vaid **hulk väikesi protsesse**, millest igaüks teeb ühte asja. Neid juhib peaprotsess `master`, kes käivitab vajaduse korral teisi. Nii on Postfix turvaline: kirja vastuvõttev protsess ei saa näiteks kettale postkasti kirjutada ja vastupidi.

| Protsess | Ülesanne | Logis |
| --- | --- | --- |
| `master` | peaprotsess; kuulab porte ja käivitab teisi protsesse (seadistus: `master.cf`) | `postfix/master` |
| `smtpd` | **võtab kirja vastu** võrgust (pordid 25, 587, 465); kontrollib piiranguid | `postfix/smtpd`, `postfix/submission/smtpd` |
| `pickup` | võtab vastu kohalikult (`mail`, `sendmail`) saadetud kirjad | `postfix/pickup` |
| `cleanup` | korrastab kirja: lisab puuduvad päised (`Date`, `Message-ID`), küsib **milteritelt** (OpenDKIM) | `postfix/cleanup` |
| `qmgr` | **järjekorra haldur** – otsustab, kuhu ja millal kiri saata | `postfix/qmgr` |
| `local` | kohalike (`mydestination`) kasutajate kirjad: aliased, `.forward` | `postfix/local` |
| `lmtp` | annab kirja LMTP-ga edasi (meil Dovecotile) | `postfix/lmtp` |
| `smtp` | **saadab kirja teise serverisse** (klientpool) | `postfix/smtp` |
| `bounce` | koostab saatjale tagastusteate, kui kirja ei saa kohale toimetada | `postfix/bounce` |

**Järjekord.** Iga kiri saab vastuvõtmisel unikaalse **järjekorra-ID** (nt `7DC7EC4886`) ja liigub kaustade vahel `/var/spool/postfix/` all: `incoming` → `active` → kohale toimetatud (kustutatakse) või `deferred` (ajutine viga, proovitakse hiljem uuesti). Sellepärast ei kao kiri, kui Dovecot on hetkeks maas – see ootab järjekorras.

**Seadistus.** Kaks faili:

- `main.cf` – **mida** Postfix teeb (domeenid, piirangud, TLS). Muudame käsuga `postconf -e 'nimi = väärtus'`: see leiab olemasoleva rea ja asendab selle. Faili käsitsi muutes juhtub sageli, et sama seade on failis kaks korda – siis kehtib **viimane** ja Postfix hoiatab logis `overriding earlier entry`.
- `master.cf` – **millised protsessid ja pordid** töötavad.

Pärast muudatust: `sudo postfix check` (süntaks) ja `sudo systemctl reload postfix` (rakendab ilma ühendusi katkestamata).

**Otsingutabelid (*lookup tables*).** Paljud Postfixi seaded ei ole üks väärtus, vaid **tabel**: „võti → väärtus“. Tabeli tüüp kirjutatakse ette: `hash:/etc/postfix/fail` (tekstifail, millest `postmap` teeb kiire andmebaasi), `regexp:/etc/postfix/fail` (regulaaravaldised), `mysql:/etc/postfix/fail.cf` (päring andmebaasist, Osa III). Tabelit saab käsurealt küsida: `postmap -q võti tüüp:fail`.

### 10.2 Paigaldus

**Ubuntu:**

```bash
sudo apt install -y postfix dovecot-imapd dovecot-lmtpd swaks mailutils
```

Postfixi paigaldusdialoog:

| Küsimus | Vastus |
| --- | --- |
| General mail configuration type | **Internet Site** |
| System mail name | **perenimi.local** |

Dialoogi saab hiljem uuesti käivitada: `sudo dpkg-reconfigure postfix`. `swaks` on SMTP testimise tööriist, `mailutils` annab käsu `mail`.

| Pakett | Milleks |
| --- | --- |
| `postfix` | MTA – võtab vastu ja saadab kirju |
| `dovecot-imapd` | Dovecoti põhiosa + IMAP-server (pakett tõmbab kaasa `dovecot-core`) |
| `dovecot-lmtpd` | LMTP-server, millega Postfix annab kirjad Dovecotile |
| `swaks` | „SMTP Šveitsi armee nuga“ – testkirjade saatmine koos kogu SMTP-vestluse näitamisega |
| `mailutils` | käsk `mail` kirjade saatmiseks käsurealt |

**Internet Site** tähendab: server saadab ja võtab kirju vastu otse SMTP-ga (mitte ainult ei edasta teise serverisse). **System mail name** läheb faili `/etc/mailname` – see on domeen, mille nimel kohalikud kirjad saadetakse.

**Vahekontroll:**

```bash
systemctl status postfix dovecot --no-pager | grep Active     # mõlemad active
sudo ss -tlnp | grep ':25 '                                     # master kuulab porti 25
cat /etc/mailname                                               # perenimi.local
```

### 10.3 Postfix: põhiseaded

**Ubuntu:**

```bash
sudo cp /etc/postfix/main.cf /etc/postfix/main.cf.orig

sudo postconf -e \
  'myhostname = mail.perenimi.local' \
  'mydomain = perenimi.local' \
  'myorigin = $mydomain' \
  'mydestination = $myhostname, $mydomain, localhost.$mydomain, localhost' \
  'inet_interfaces = all' \
  'inet_protocols = ipv4' \
  'mynetworks = 127.0.0.0/8' \
  'home_mailbox = Maildir/' \
  'mailbox_transport = lmtp:unix:private/dovecot-lmtp' \
  'smtpd_banner = $myhostname ESMTP' \
  'disable_vrfy_command = yes' \
  'smtpd_helo_required = yes' \
  'message_size_limit = 26214400' \
  'smtputf8_enable = no'
```

**Mida need read teevad – rühmade kaupa:**

*Serveri identiteet.* `myhostname` on serveri täisnimi – see kõlab tervitusreal (`220 mail.perenimi.local ESMTP`) ja HELO-s, kui meie server teisele serverile kirja viib. Peab ühtima DNS-i A- ja PTR-kirjega. `mydomain` on domeen; `$mydomain` kujul saab seda teistes seadetes kasutada.

*Kelle post on minu oma?* `mydestination` loetleb domeenid, mille **lõppsihtkoht** on see server. Kui kiri tuleb aadressile `mari@perenimi.local` ja `perenimi.local` on selles loendis, ei saada Postfix kirja kuhugi edasi, vaid otsib kohaliku kasutaja `mari` ja toimetab kirja tema postkasti. Kui domeen **pole** loendis, peab Postfix kirja edasi saatma (MX-i järgi või relay'le) – ja seda lubab ta ainult usaldusväärsetele saatjatele (10.5).

*Keda usaldatakse?* `mynetworks` on IP-vahemik, kust tulevad kirjad lastakse läbi **ilma paroolita** ükskõik kuhu. Sinna kuulub ainult server ise (`127.0.0.0/8`), et serveri enda programmid (nt cron, Roundcube vanemas seadistuses) saaksid saata. Kui sinna kirjutada kogu labori võrk, saab iga labori masin – ka nakatunud – saata spämmi sinu serveri nimel.

*Kuhu kirjad lähevad?* `home_mailbox = Maildir/` ütleb, et postkast on kasutaja kodukaustas Maildir-vormingus (lõpus olev `/` tähendab just Maildiri, ilma selleta oleks see mbox-fail). `mailbox_transport` ütleb, et kohaletoimetamist ei tee Postfix ise, vaid annab kirja **Dovecotile** LMTP-sokli kaudu. Nii on postkasti kirjutaja ja lugeja sama programm, mis hoiab ka indekseid ja kaustu korras.

*Võrk.* `inet_interfaces = all` – kuula kõigil liidestel (vaikimisi ainult `loopback-only` mõnel süsteemil). `inet_protocols = ipv4` – laboris pole IPv6-t; muidu proovib Postfix AAAA-kirjeid ja logis on asjatuid vigu.

*Karmistamine.* Ülejäänud read peidavad infot ja seavad piire – vt tabel.

| Seade | Selgitus |
| --- | --- |
| `myorigin = $mydomain` | kohalikult saadetud kirjad saavad aadressi `@perenimi.local` (mitte `@mail.perenimi.local`) |
| `mailbox_transport` | kohalike kasutajate kirjad antakse Dovecotile (LMTP sokkel) |
| `smtpd_banner` | ära ütle tervituses tarkvara nime ja versiooni |
| `disable_vrfy_command` | `VRFY mari` käsuga ei saa enam uurida, millised kasutajad on olemas |
| `message_size_limit` | kirja maksimumsuurus 25 MB |
| `smtputf8_enable = no` | Dovecot 2.3 LMTP ei toeta SMTPUTF8 laiendust. Ilma selle reata **lükatakse tagasi** kohalikud kirjad, mille pealkirjas on täpitähed ja mis on saadetud käsuga `mail`/`sendmail` (`status=bounced (SMTPUTF8 is required, but was not offered…)`). Roundcube ja Thunderbird kodeerivad pealkirja ise ega ole mõjutatud. |
| `smtpd_helo_required` | klient peab end enne `MAIL FROM`-i tutvustama (`HELO`/`EHLO`); paljud spämmiprogrammid ei tee seda |

**Vahekontroll:**

```bash
sudo postfix check                     # tühi väljund = süntaks korras
postconf -n | grep -E '^(myhostname|mydomain|mydestination|mynetworks|home_mailbox|mailbox_transport) '
```

### 10.4 Postfix: TLS

Ilma TLS-ita liigub SMTP võrgus avatekstina: igaüks, kes näeb võrguliiklust, loeb kirju ja – mis veel hullem – kasutajate paroole. TLS-i jaoks on Postfixil vaja sama serti, mis Apache'il ja Dovecotil (peatükk 8.8).

Postfixis on TLS-i jaoks **kaks seadete komplekti**:

- `smtpd_tls_*` – kui **meie** oleme server ja keegi ühendub meiega (kirja vastuvõtmine);
- `smtp_tls_*` – kui **meie** oleme klient ja viime kirja teise serverisse (relay, peatükk 13).

```bash
sudo postconf -e \
  'smtpd_tls_cert_file = /etc/ssl/certs/mail.perenimi.local.crt' \
  'smtpd_tls_key_file = /etc/ssl/private/mail.perenimi.local.key' \
  'smtpd_tls_security_level = may' \
  'smtpd_tls_auth_only = yes' \
  'smtpd_tls_protocols = >=TLSv1.2' \
  'smtpd_tls_mandatory_protocols = >=TLSv1.2' \
  'smtpd_tls_loglevel = 1' \
  'smtp_tls_security_level = may' \
  'smtp_tls_CApath = /etc/ssl/certs'
```

- `smtpd_tls_security_level = may` – pordil 25 pakutakse STARTTLS-i, kuid ei nõuta (internetis ei toeta kõik serverid TLS-i). Pordil 587 teeme selle kohustuslikuks (10.6).
- `smtpd_tls_auth_only = yes` – parooliga sisselogimist pakutakse **alles pärast TLS-i**.
- `smtpd_tls_protocols` / `smtpd_tls_mandatory_protocols = >=TLSv1.2` – vanad, nõrgad TLS 1.0 ja 1.1 on keelatud.
- `smtpd_tls_loglevel = 1` – logisse kirjutatakse iga TLS-ühenduse kokkuvõte (`TLS connection established … TLSv1.3`), mis aitab tõrkeotsingul.
- `smtp_tls_security_level = may` – kui meie viime kirja teise serverisse ja see pakub TLS-i, kasutame seda. `smtp_tls_CApath` on koht, kust leida usaldatud juursertid.

Privaatvõti (`.key`) peab olema loetav ainult root'ile ja rühmale `ssl-cert` (`chmod 640`). Postfixi peaprotsess loeb võtme root'ina enne õiguste loovutamist, seega ei pea Postfix ise rühmas olema.

**Vahekontroll** (pärast `sudo systemctl reload postfix`):

```bash
openssl s_client -starttls smtp -connect mail.perenimi.local:25 </dev/null 2>/dev/null \
  | grep -E "subject=|issuer=|Verify return code"
# subject=… CN = mail.perenimi.local   issuer=… Perenimi Labori CA   Verify return code: 0 (ok)
```

### 10.5 Postfix: autentimine ja piirangud

See on peatüki kõige olulisem osa: siin otsustatakse, **kes tohib meie serverit kasutada**. Valesti seadistatud piirangud tähendavad kas seda, et keegi ei saa saata, või seda, et kõik saavad (avatud relee).

**Kus parooli kontrollitakse?** Postfixil endal paroolifaili pole. Ta küsib Dovecotilt: `smtpd_sasl_type = dovecot` ja `smtpd_sasl_path = private/auth` tähendab „ühendu soklile `/var/spool/postfix/private/auth`, seal vastab Dovecot“. Dovecot kontrollib parooli sama mehhanismiga nagu IMAP-i sisselogimisel. Nii on kasutajatel **üks parool** nii lugemiseks kui ka saatmiseks.

**Millal piiranguid kontrollitakse?** SMTP-vestlus käib sammhaaval ja igas etapis on oma piirangute loend:

| SMTP etapp | Piirangute loend | Mida tavaliselt kontrollitakse |
| --- | --- | --- |
| ühenduse loomine | `smtpd_client_restrictions` | kliendi IP (mustad nimekirjad) |
| `HELO`/`EHLO` | `smtpd_helo_restrictions` | kas tutvustus on korrektne FQDN |
| `MAIL FROM` | `smtpd_sender_restrictions` | saatja aadress |
| `RCPT TO` | `smtpd_relay_restrictions`, siis `smtpd_recipient_restrictions` | **kas tohib sellele saajale saata** |

Postfix kogub vaikimisi (`smtpd_delay_reject = yes`) kõik otsused kokku ja annab keeldumise alles `RCPT TO` ajal. Seepärast saab ka HELO-piirangus kasutada `permit_sasl_authenticated` – selleks ajaks on klient juba sisse loginud.

**Kuidas loendit loetakse?** Vasakult paremale. Iga element kas **lubab** (`permit_…`), **keelab** (`reject_…`) või ei ütle midagi (siis vaadatakse järgmist). **Esimene otsus võidab.** Kui loend saab otsa ilma otsuseta, kiri lubatakse.

Vaatame `smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination` kolme olukorra kaudu:

| Olukord | `permit_mynetworks` | `permit_sasl_authenticated` | `reject_unauth_destination` | Tulemus |
| --- | --- | --- | --- | --- |
| Gmail toob kirja `mari@perenimi.local`-ile | ei ole meie võrk → edasi | pole sisse loginud → edasi | saaja **on** meie domeenis → ei keela | ✅ lubatud |
| Võõras saadab `keegi@gmail.com`-ile | edasi | edasi | saaja pole meie domeenis → **keelab** | ❌ `Relay access denied` |
| Jaan (sisse loginud) saadab `keegi@gmail.com`-ile | edasi | **lubab** | – | ✅ lubatud |

```bash
sudo postconf -e \
  'smtpd_sasl_type = dovecot' \
  'smtpd_sasl_path = private/auth' \
  'smtpd_sasl_auth_enable = no' \
  'smtpd_helo_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname' \
  'smtpd_sender_restrictions = reject_non_fqdn_sender, reject_unknown_sender_domain' \
  'smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination' \
  'smtpd_recipient_restrictions = reject_non_fqdn_recipient, permit_mynetworks, reject_unauth_destination, reject_unknown_recipient_domain' \
  'smtpd_sender_login_maps = regexp:/etc/postfix/login_maps.regexp'
```

| Seade | Mida teeb |
| --- | --- |
| `smtpd_sasl_auth_enable = no` | pordil 25 autentimist **ei pakuta**; lülitame selle sisse ainult 587/465 jaoks |
| `smtpd_helo_restrictions` | võõras server peab end tutvustama korrektse FQDN-iga; **autenditud** kliente see ei puuduta (Windows saadab HELO-s nime nagu `DESKTOP-AB12`) |
| `reject_unknown_sender_domain` | saatja domeen peab DNS-is olemas olema |
| `reject_unauth_destination` | **relee keeld**: võõrast domeeni tohivad sihiks panna ainult `mynetworks` ja sisseloginud kasutajad |
| `smtpd_sender_login_maps` | milline sisseloginud kasutaja tohib millist saatja aadressi kasutada |

Saatja-kasutaja vastavus – kasutaja `mari` (või `mari@perenimi.local`) tohib saata ainult aadressilt `mari@perenimi.local`:

```bash
sudo nano /etc/postfix/login_maps.regexp
```

```text
# Saatja aadress                  -> kes tohib seda kasutada (SASL kasutajanimi)
/^([^@]+)@perenimi\.local$/       ${1}, ${1}@perenimi.local
```

```bash
postmap -q "mari@perenimi.local" regexp:/etc/postfix/login_maps.regexp     # mari, mari@perenimi.local
```

**Kuidas regulaaravaldis töötab:** `^([^@]+)@perenimi\.local$` tabab iga aadressi meie domeenis; sulgudes osa (`[^@]+` = „üks või rohkem märki, mis pole @“) jäetakse meelde ja see on `${1}`. Aadressi `mari@perenimi.local` puhul on `${1}` = `mari`, seega tohivad seda aadressi kasutada sisselogijad `mari` ja `mari@perenimi.local`. Kui Jaan logib sisse ja kirjutab saatjaks `mari@perenimi.local`, pole `jaan` vastuses ja Postfix keeldub (`reject_sender_login_mismatch` pordil 587, 10.6).

**Vahekontroll:**

```bash
sudo postfix check
postconf smtpd_relay_restrictions smtpd_sasl_type smtpd_sasl_path
```

### 10.6 Postfix: master.cf – pordid 587 ja 465

**Miks eraldi teenused?** Port 25 peab olema avatud kõigile teistele serveritele ja seal ei saa parooli nõuda. Kliendid (Roundcube, Thunderbird) peavad aga saatma alati parooliga ja krüpteeritult. Seepärast teeb Postfix kaks **eraldi `smtpd` teenust** samade seadetega, kuid erinevate reeglitega: `master.cf` failis on igal teenusel oma rida ja `-o` ridadega kirjutatakse `main.cf` seaded selle teenuse jaoks üle.

Failis `/etc/postfix/master.cf` on read `#submission` ja `#submissions` välja kommenteeritud. Lisa faili **lõppu**:

```bash
sudo nano /etc/postfix/master.cf
```

```text
# --- Kirjade saatmine meiliklientidelt (port 587, STARTTLS + autentimine) ---
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_tls_auth_only=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_restrictions=reject_sender_login_mismatch,reject_non_fqdn_sender
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=reject_non_fqdn_recipient,permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING

# --- Sama, kuid TLS kohe algusest (port 465, "implicit TLS") ---
submissions inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submissions
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_restrictions=reject_sender_login_mismatch,reject_non_fqdn_sender
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_recipient_restrictions=reject_non_fqdn_recipient,permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
```

> **master.cf süntaks:** `-o` read peavad algama **tühikuga** (jätkurida). Real ei tohi olla kommentaari ega tühikut `=` ümber. Tühi rida plokkide vahel on lubatud.

Veerud: teenus, tüüp, privaatne, kasutaja-õigused, **chroot (`y`)**, ärkamisaeg, protsesse, käsk. `chroot = y` tähendab, et `smtpd` näeb ainult kausta `/var/spool/postfix` – seepärast on Dovecoti soklid kaustas `/var/spool/postfix/private/` ja nende tee on kirjas suhteliselt (`private/auth`).

**Mida iga `-o` rida submission-teenuses teeb:**

| Rida | Tähendus |
| --- | --- |
| `syslog_name=postfix/submission` | logis on selle teenuse read eristatavad (`postfix/submission/smtpd`) |
| `smtpd_tls_security_level=encrypt` | TLS on **kohustuslik** – ilma STARTTLS-ita ei saa isegi `MAIL FROM`-i anda (`530 Must issue a STARTTLS command first`) |
| `smtpd_sasl_auth_enable=yes` | siin pakutakse sisselogimist (pordil 25 mitte) |
| `smtpd_client_restrictions=permit_sasl_authenticated,reject` | **kes pole sisse loginud, see ei saa midagi** – pole vahet, kuhu ta saata tahab |
| `smtpd_sender_restrictions=reject_sender_login_mismatch,…` | saatja aadress peab kuuluma sisselogijale (`smtpd_sender_login_maps`) |
| `smtpd_relay_restrictions` / `smtpd_recipient_restrictions` | sisseloginud kasutaja tohib saata ükskõik kuhu |
| `milter_macro_daemon_name=ORIGINATING` | annab milteritele (OpenDKIM, rämpspostifiltrid) teada, et kiri tuleb meie enda kasutajalt, mitte väljastpoolt (peatükk 11) |

`submissions` (465) on sama, kuid `smtpd_tls_wrappermode=yes` tähendab, et TLS algab **kohe** ühenduse loomisel (implicit TLS), mitte STARTTLS-käsuga.

**Vahekontroll** (pärast `sudo systemctl restart postfix`):

```bash
sudo ss -tlnp | grep -E ':(25|465|587) '        # kõik kolm porti, protsess master
```

```bash
sudo postfix check            # tühi väljund = OK
```

### 10.7 Dovecot

Dovecot teeb laboris kolme tööd: **(1)** hoiab postkaste ja annab neid IMAP-iga klientidele, **(2)** võtab Postfixilt kirju vastu ja kirjutab need postkasti (LMTP), **(3)** kontrollib paroole – nii enda kui ka Postfixi jaoks (SASL).

**Kust Dovecot kasutajad leiab?** Dovecotis on kaks eri küsimust:

- **passdb** – „kas parool on õige?“
- **userdb** – „kus on selle kasutaja postkast ja millise Linuxi kasutaja õigustes sinna kirjutada?“

Ubuntu vaikeseadistuses (`conf.d/auth-system.conf.ext`) on passdb = **PAM** (Linuxi tavaline paroolikontroll, sama mis SSH-l) ja userdb = **passwd** (`/etc/passwd` – kodukaust ja UID). Seepärast piisab meil Linuxi kasutaja loomisest: `mari` saab automaatselt postkasti `/home/mari/Maildir`. Osas III vahetame need andmebaasi vastu.

**Kuidas seadistus on üles ehitatud?** Põhifail `/etc/dovecot/dovecot.conf` loeb sisse kõik failid `conf.d/*.conf` ja lõpuks `local.conf`. Hilisem väärtus kirjutab varasema üle. `service`-plokid (`service lmtp { … }`) ei asenda vaikeplokke, vaid **täiendavad** neid – nii saame lisada Postfixi jaoks soklid ilma vaikefaile muutmata.

Ubuntu Dovecoti seadistus on jagatud ~20 failiks kaustas `/etc/dovecot/conf.d/`. Nende ükshaaval muutmise asemel paneme **kõik oma seaded ühte faili** `/etc/dovecot/local.conf` – põhifail `dovecot.conf` loeb selle viimasena ja selle väärtused kehtivad.

**Ubuntu:**

```bash
sudo nano /etc/dovecot/local.conf
```

```text
# /etc/dovecot/local.conf – labori meiliserveri seadistus (Dovecot 2.3)
# See fail loetakse dovecot.conf lõpus ja kirjutab vaikeväärtused üle.

protocols = imap lmtp

# --- Postkastide asukoht: iga kasutaja kodukaustas ~/Maildir ---
mail_location = maildir:~/Maildir
mail_privileged_group = mail

# --- Autentimine ---
disable_plaintext_auth = yes
auth_mechanisms = plain login
auth_username_format = %Ln

# --- TLS ---
ssl = required
ssl_cert = </etc/ssl/certs/mail.perenimi.local.crt
ssl_key  = </etc/ssl/private/mail.perenimi.local.key
ssl_min_protocol = TLSv1.2
ssl_prefer_server_ciphers = yes

# --- Postfix -> Dovecot: kirjade kohaletoimetamine (LMTP) ---
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}

# --- Postfix küsib Dovecotilt, kas parool on õige (SASL) ---
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}

# --- Krüptimata IMAP (143) välja: kliendid kasutavad ainult IMAPS 993 ---
service imap-login {
  inet_listener imap {
    port = 0
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

# --- Standardkaustad luuakse ja tellitakse automaatselt ---
namespace inbox {
  mailbox Drafts {
    special_use = \Drafts
    auto = subscribe
  }
  mailbox Sent {
    special_use = \Sent
    auto = subscribe
  }
  mailbox Junk {
    special_use = \Junk
    auto = subscribe
  }
  mailbox Trash {
    special_use = \Trash
    auto = subscribe
  }
}
```

| Seade | Selgitus |
| --- | --- |
| `ssl_cert = <…` | **`<` on oluline** – see tähendab „loe väärtus failist“. Ilma selleta proovib Dovecot failinime ennast serdiks lugeda. |
| `disable_plaintext_auth = yes` | parooli ei võeta vastu krüptimata ühenduse kaudu |
| `auth_username_format = %Ln` | `Mari@Perenimi.local` → `mari`: domeen eemaldatakse, väiketähed. Nii leiab Dovecot Linuxi kasutaja nii IMAP-i sisselogimisel kui ka LMTP kohaletoimetamisel. |
| `special_use` | ütleb klientidele, milline kaust on „Saadetud“, „Prügikast“ jne – Roundcube ja Thunderbird kasutavad neid automaatselt |
| `protocols = imap lmtp` | milliseid teenuseid Dovecot pakub; POP3 jätame välja |
| `mail_location = maildir:~/Maildir` | postkast on kasutaja kodukaustas Maildir-vormingus; `~` tuleb userdb-st (`/home/mari`) |
| `mail_privileged_group = mail` | rühm, mille õigustes tohib kirjutada `/var/mail` alla (vanad mbox-postkastid) |
| `auth_mechanisms = plain login` | PLAIN = standard; LOGIN on vajalik vanematele Outlookidele. Mõlemad saadavad parooli – seepärast ainult TLS-iga |
| `ssl = required` | ilma TLS-ita ei saa üldse sisse logida |
| `service lmtp` → `unix_listener …/dovecot-lmtp` | sokkel, kuhu Postfix kirjad toob. `mode 0600`, omanik `postfix` – ainult Postfix saab sinna kirjutada |
| `service auth` → `unix_listener …/auth` | sokkel, kust Postfix küsib paroolikontrolli |
| `service imap-login` → `port = 0` | krüptimata IMAP (143) on kinni; avatud ainult 993 |

**Miks soklid, mitte võrguport?** UNIX-sokkel on fail. Sellele saab panna failiõigused (ainult kasutaja `postfix`) ja seda ei näe võrgust keegi. Võrguport 24 (LMTP) oleks igaühele nähtav.

Kontrolli ja käivita:

```bash
sudo doveconf -n | head -40          # efektiivne seadistus; vead kuvatakse siin
sudo systemctl restart dovecot postfix
sudo ss -tlnp | grep -E ':(25|465|587|993)\b'
ls -l /var/spool/postfix/private/ | grep -E 'auth|dovecot-lmtp'
```

**Vahekontroll:** `doveconf -n` ei näita vigu; pordid 25, 465, 587 ja 993 kuulavad; kaustas `private/` on `auth` (omanik postfix, `srw-rw----`) ja `dovecot-lmtp` (`srw-------`). Kui sokleid pole, vaata `sudo journalctl -u dovecot -n 30`.

### 10.8 Kasutajad ja aliased

**Ubuntu:**

```bash
sudo adduser --shell /usr/sbin/nologin mari
sudo adduser --shell /usr/sbin/nologin jaan
```

`adduser` loob Linuxi kasutaja, tema kodukausta `/home/mari` ja küsib parooli. See parool on ka **meiliparool**. `--shell /usr/sbin/nologin` tähendab, et SSH-ga see kasutaja sisse ei saa – meilikasutajal pole serveris käsurida vaja. Postkasti kausta `Maildir` ei pea looma: Dovecot teeb selle esimese kirja saabumisel ise.

**Aliased** on aadressid, millel pole oma postkasti – kiri suunatakse kellelegi teisele. Fail `/etc/aliases` kehtib ainult `mydestination` domeenidele. Pärast muutmist tuleb käivitada `newaliases`, mis teeb tekstifailist Postfixi kiire andmebaasi (`/etc/aliases.db`).

Iga RFC-kohane meiliserver peab vastu võtma aadressi `postmaster@`. Suuname süsteemi aadressid päris inimesele:

```bash
sudo nano /etc/aliases
```

```text
postmaster:    root
abuse:         root
root:          mari
```

```bash
sudo newaliases
```

Testi Dovecoti autentimist:

`doveadm auth test` küsib parooli ja kontrollib seda **täpselt nagu IMAP ja Postfix**. `doveadm user` näitab, kust Dovecot postkasti otsib. Kui need kaks töötavad, töötab ka sisselogimine.

```bash
sudo doveadm auth test mari              # passdb: mari auth succeeded
sudo doveadm user mari                   # home: /home/mari, mail: maildir:~/Maildir
```

### 10.9 Tulemüür

**Ubuntu:**

```bash
sudo ufw allow 25/tcp
sudo ufw allow 587/tcp
sudo ufw allow 465/tcp
sudo ufw allow 993/tcp
sudo ufw status
```

Port 25 peab olema avatud kõigile (teised serverid toovad kirju), 587/465/993 on klientidele. Porti 143 me ei ava – see on Dovecotis suletud. Porti 24 (LMTP) ega Dovecoti soklit pole vaja avada: Postfix ja Dovecot räägivad samas masinas.

### 10.10 Testimine

Kõik testid tee **Ubuntus**. Logi jälgimiseks ava teine SSH-aken: `sudo tail -f /var/log/mail.log`.

Testid on valitud nii, et iga test tõestab ühte seadistuse osa. **Testid 3, 5 ja 6 peavad ebaõnnestuma** – kui need õnnestuvad, on server ebaturvaline.

| Test | Mida tõestab | Seadistus, mida testitakse |
| --- | --- | --- |
| 1 | kohalik kiri jõuab postkasti | `mydestination`, `mailbox_transport`, Dovecot LMTP |
| 2 | teine server saab meile kirja tuua | port 25, `smtpd_recipient_restrictions` |
| 3 | server **ei ole** avatud relee | `reject_unauth_destination`, `mynetworks` |
| 4 | kasutaja saab parooliga saata | port 587, TLS, SASL (Dovecot auth sokkel) |
| 5 | kasutaja **ei saa** teise nime all saata | `reject_sender_login_mismatch`, `login_maps.regexp` |
| 6 | parooli **ei saa** saata krüptimata | `smtpd_tls_auth_only` |
| 7 | port 465 töötab | `submissions`, `smtpd_tls_wrappermode` |
| 8 | kirju saab lugeda | Dovecot IMAP 993, `ssl = required` |

**Test 1 – kohalik kiri:**

```bash
echo "Esimene kiri" | mail -s "Tere täpitähtedega õäöü" mari@perenimi.local
sudo ls /home/mari/Maildir/new/
```

**Test 2 – port 25 väljastpoolt (nagu teine server):**

```bash
swaks --server 192.168.XXX.20 --helo test.perenimi.local \
      --from jaan@perenimi.local --to mari@perenimi.local
```

Oodatav: `<-  250 2.0.0 Ok: queued as …`

**Test 3 – avatud relee test (PEAB ebaõnnestuma):**

```bash
swaks --server 192.168.XXX.20 --helo test.example.org \
      --from jaan@perenimi.local --to keegi@example.com
```

Oodatav: `<** 554 5.7.1 <keegi@example.com>: Relay access denied`

**Test 4 – saatmine pordilt 587 autentimisega:**

```bash
swaks --server mail.perenimi.local -p 587 -tls \
      --auth LOGIN --auth-user jaan --auth-password 'jaani-parool' \
      --from jaan@perenimi.local --to mari@perenimi.local --h-Subject "Test 587"
```

Oodatav: `235 2.7.0 Authentication successful` ja `250 2.0.0 Ok: queued`.

**Test 5 – võõra nimega saatmine (PEAB ebaõnnestuma):**

```bash
swaks --server mail.perenimi.local -p 587 -tls \
      --auth LOGIN --auth-user jaan --auth-password 'jaani-parool' \
      --from mari@perenimi.local --to mari@perenimi.local
```

Oodatav: `553 5.7.1 <mari@perenimi.local>: Sender address rejected: not owned by user jaan`

**Test 6 – autentimine ilma TLS-ita (PEAB ebaõnnestuma):**

```bash
swaks --server mail.perenimi.local -p 587 --auth LOGIN --auth-user jaan --auth-password 'x' \
      --from jaan@perenimi.local --to mari@perenimi.local
```

Oodatav: `*** Host did not advertise authentication` – enne STARTTLS-i AUTH-i ei pakuta.

**Test 7 – port 465:**

```bash
swaks --server mail.perenimi.local -p 465 -tlsc \
      --auth PLAIN --auth-user mari@perenimi.local --auth-password 'mari-parool' \
      --from mari@perenimi.local --to jaan@perenimi.local
```

**Test 8 – IMAP:**

```bash
curl -s --url "imaps://mail.perenimi.local/INBOX" -u mari -X "SEARCH ALL"
# * SEARCH 1 2 3
sudo doveadm mailbox list -u mari         # INBOX, Drafts, Sent, Junk, Trash
```

### 10.11 Kirja päiste lugemine

```bash
sudo bash -c 'cat /home/mari/Maildir/new/$(ls -t /home/mari/Maildir/new | head -1)'
```

`Received:` päised loetakse **alt üles** – alumine on esimene server, mille kaudu kiri läks. Vaata, kas seal on `with ESMTPSA` (S = TLS, A = autenditud).

### 10.12 Logirea anatoomia

```text
postfix/submission/smtpd[6143]: 64EDDC48D4: client=unknown[192.168.XXX.50], sasl_method=LOGIN, sasl_username=mari
postfix/cleanup[6150]:          64EDDC48D4: message-id=<…>
postfix/qmgr[6133]:             64EDDC48D4: from=<mari@perenimi.local>, size=1282, nrcpt=1 (queue active)
postfix/lmtp[6149]:             64EDDC48D4: to=<jaan@perenimi.local>, relay=mail.perenimi.local[private/dovecot-lmtp], dsn=2.0.0, status=sent
postfix/qmgr[6133]:             64EDDC48D4: removed
```

Järjekorra-ID (`64EDDC48D4`) seob ühe kirja kõik read – otsi `grep 64EDDC48D4 /var/log/mail.log`.

| `status=` | Tähendus |
| --- | --- |
| `sent` | kohale toimetatud / edasi antud |
| `deferred` | ajutine viga, proovitakse uuesti (`mailq`) |
| `bounced` | püsiv viga, saatjale saadeti tagastusteade |

> Varasemad juhendid: [Meiliserver postfix koos dovecot'ga](../Meiliserver%20postfix%20koos%20dovecot'ga%20.md), [E-posti server Postfix ja Dovecot](../Epost_DNS/1.%20E-posti%20server%20Postfix%20ja%20Dovecot.md).

### 10.13 Valmis seadistus tervikuna

Kui kõik testid on läbitud, peaks `postconf -n` näitama (lisaks Ubuntu vaikeridadele nagu `alias_maps`, `compatibility_level`, `readme_directory`) järgmist:

```text
disable_vrfy_command = yes
home_mailbox = Maildir/
inet_interfaces = all
inet_protocols = ipv4
mailbox_transport = lmtp:unix:private/dovecot-lmtp
message_size_limit = 26214400
mydestination = $myhostname, $mydomain, localhost.$mydomain, localhost
mydomain = perenimi.local
myhostname = mail.perenimi.local
mynetworks = 127.0.0.0/8
myorigin = $mydomain
smtp_tls_CApath = /etc/ssl/certs
smtp_tls_security_level = may
smtpd_banner = $myhostname ESMTP
smtpd_helo_required = yes
smtpd_helo_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_invalid_helo_hostname, reject_non_fqdn_helo_hostname
smtpd_recipient_restrictions = reject_non_fqdn_recipient, permit_mynetworks, reject_unauth_destination, reject_unknown_recipient_domain
smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination
smtpd_sasl_auth_enable = no
smtpd_sasl_path = private/auth
smtpd_sasl_type = dovecot
smtpd_sender_login_maps = regexp:/etc/postfix/login_maps.regexp
smtpd_sender_restrictions = reject_non_fqdn_sender, reject_unknown_sender_domain
smtpd_tls_auth_only = yes
smtpd_tls_cert_file = /etc/ssl/certs/mail.perenimi.local.crt
smtpd_tls_key_file = /etc/ssl/private/mail.perenimi.local.key
smtpd_tls_loglevel = 1
smtpd_tls_mandatory_protocols = >=TLSv1.2
smtpd_tls_protocols = >=TLSv1.2
smtpd_tls_security_level = may
smtputf8_enable = no
```

Järgmistes peatükkides lisanduvad OpenDKIM (`smtpd_milters`, peatükk 11) ja relay (`relayhost`, `smtp_sasl_*`, peatükk 13).

**Failid, mida selles peatükis muutsid:**

| Fail | Sisu | Peale muutmist |
| --- | --- | --- |
| `/etc/postfix/main.cf` | Postfixi seaded (`postconf -e`) | `postfix check`, `systemctl reload postfix` |
| `/etc/postfix/master.cf` | pordid 587 ja 465 | `postfix check`, `systemctl restart postfix` |
| `/etc/postfix/login_maps.regexp` | kes tohib millist saatja aadressi kasutada | (regexp-tabelit `postmap` ei vaja) `systemctl reload postfix` |
| `/etc/dovecot/local.conf` | kõik Dovecoti seaded | `doveconf -n`, `systemctl restart dovecot` |
| `/etc/aliases` | süsteemi aliased | `newaliases` |
| `/home/<kasutaja>/Maildir/` | postkastid (loob Dovecot) | – |

Kirja teekond selle seadistusega on interaktiivselt läbi mängitav [e-kirja teekonna simulaatoris](https://valdonolvak.github.io/meili--ja_veebiserverite_haldus/interaktiivne/e-kirja-simulaator.html).
