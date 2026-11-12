## 13. Laboritööd

Laborid on järjestikused: iga järgmine eeldab eelmise tulemust. Iga labori lõpus on **kontrollpunkt** (mis peab töötama, enne kui edasi lähed) ja **küsimused**, millele vasta lühidalt laboripäevikus. Tee enne iga laborit Proxmoxis kõigist Linuxi masinatest hetktõmmis.

| Labor | Teema | Masinad | Peatükk | Aeg (ak h) |
| --- | --- | --- | --- | --- |
| 1 | Linuxi masinate ettevalmistus | kõik | 2 | 3 |
| 2 | Nimeserver BIND9 | Debian2, Windows | 3 | 3 |
| 3 | Apache2 ja virtuaalhostid | Debian1 | 4 | 3 |
| 4 | WordPress samas masinas | Debian1 | 5 | 3 |
| 5 | WordPress kaugandmebaasiga | Debian1, Debian2 | 6 | 3 |
| 6 | Labori CA ja HTTPS | Debian2, Debian1, Windows | 7 | 3 |
| 7 | Postfix ja Dovecot | Ubuntu | 8–9 | 5 |
| 8 | DKIM, SPF, DMARC ja fail2ban | Ubuntu, Debian2 | 10 | 4 |
| 9 | Veebimeil Roundcube | Ubuntu, Windows | 11 | 3 |
| 10 | Väljaminev post relay kaudu | Ubuntu | 12 | 2 |
| 11 | Tõrkeotsingu harjutus | kõik | 14 | 3 |

---

### Labor 1. Linuxi masinate ettevalmistus

**Eesmärk:** kõigil kolmel Linuxi masinal on õige nimi, staatiline IP, toimiv nimelahendus, SSH, `sudo`, uuendused ja tulemüür.

**Sammud:**

1. Pane kirja oma silla number XXX ja perenimi. Täida laboripäevikus tabel 1.1 oma väärtustega.
2. Debian1 ja Debian2: kontrolli `sudo whoami`; vajadusel lisa kasutaja `sudo` rühma (2.2).
3. Leia igas masinas võrguliidese nimi (`ip -br link`).
4. Seadista staatiline IP: Debian1 `.10`, Debian2 `.20` (`/etc/network/interfaces`, 2.4), Ubuntu `.30` (netplan, 2.5).
5. Ajutine nimeserver kõigis kolmes: kooli DNS või `1.1.1.1` (BIND9 tuleb laboris 2).
6. Hostinimed: `debian1`, `debian2`, `mail` + `/etc/hosts` (2.6).
7. `sudo apt update && sudo apt full-upgrade -y` ja põhitööriistad (2.7).
8. SSH: logi Windowsi kliendist PowerShelliga sisse kõigisse kolme masinasse.
9. `ufw`: luba OpenSSH ja lülita sisse kõigis kolmes (2.10).
10. Windowsi kliendile staatiline IP `10.0.XXX.100`, lüüs `10.0.XXX.1`.

**Kontrollpunkt:**

```bash
hostname -f                 # debian1.perenimi.local / debian2.perenimi.local / mail.perenimi.local
ip -br addr                 # õige IP
ping -c 2 10.0.XXX.1        # lüüs vastab
ping -c 2 debian.org        # internet ja DNS töötavad
sudo ufw status             # Status: active, 22/tcp ALLOW
```

**Küsimused:**

1. Mis vahe on hostinimel ja FQDN-il? Miks meiliserveril on FQDN eriti oluline?
2. Miks ei tohi serveril olla DHCP-ga saadud aadress?
3. Miks tuleb `ufw allow OpenSSH` teha **enne** `ufw enable`?
4. Kus asub Debian 13-s ja kus Ubuntu 24.04-s võrguseadistus? Miks need erinevad?

---

### Labor 2. Nimeserver BIND9

**Eesmärk:** Debian2 on domeeni `perenimi.local` autoriteetne nimeserver ja kogu labori rekursiivne nimelahendaja.

**Sammud:**

1. Paigalda BIND9 (3.3).
2. Seadista `named.conf.options`: ACL `labor`, rekursioon ainult laborile, edastajad (3.4).
3. Kirjelda tsoonid `named.conf.local`-is (3.5).
4. Loo edasisuunatud tsoonifail kõigi kirjetega 3.6 järgi.
5. Loo pöördtsoonifail (3.7).
6. Kontrolli `named-checkconf` ja `named-checkzone`, taaskäivita `named` (3.8).
7. Muuda **kõigi** Linuxi masinate nimeserveriks `10.0.XXX.20` (Debian2-s `127.0.0.1`).
8. Luba tulemüüris port 53 TCP ja UDP labori võrgust (3.10).
9. Windowsi klient ja Windows Server: DNS `10.0.XXX.20` (2.11).
10. **Vahemälu katse:** küsi Windowsis `nslookup www.perenimi.local`. Muuda tsoonis `www` IP-ks `10.0.XXX.99`, **ära suurenda seerianumbrit**, tee `sudo rndc reload perenimi.local`. Vaata `sudo journalctl -u named -n 5` – mis hoiatus on? Mida vastab `dig @127.0.0.1 www.perenimi.local` Debian2-s ja mida brauser/`ping www.perenimi.local` Windowsis? Tee Windowsis `ipconfig /displaydns`, siis `ipconfig /flushdns` ja proovi uuesti. Taasta IP ja suurenda seerianumbrit.

**Kontrollpunkt:**

```bash
dig +short mail.perenimi.local            # 10.0.XXX.30
dig +short wp.perenimi.local              # debian1.perenimi.local. 10.0.XXX.10
dig +short perenimi.local MX              # 10 mail.perenimi.local.
dig +short -x 10.0.XXX.30                 # mail.perenimi.local.
dig +short debian.org                     # IP (edastajad töötavad)
```

```powershell
nslookup blogi.perenimi.local             # Windowsis: Address 10.0.XXX.10, Aliases: blogi.perenimi.local
```

**Küsimused:**

1. Mis vahe on autoriteetsel ja rekursiivsel nimeserveril? Kumb on Debian2 nime `debian.org` puhul?
2. Miks `allow-recursion` peab olema piiratud?
3. Miks `mail` on A-kirje, aga `wp` võib olla CNAME?
4. Mis juhtus sammus 10 ja miks nägid Debian2 ja Windows erinevaid vastuseid? Kes kasutab seerianumbrit ja kes TTL-i?
5. Mis on punkti tähendus tsoonifailis `mail.perenimi.local.` lõpus? Mis juhtub, kui see ununeb?

---

### Labor 3. Apache2 ja virtuaalhostid

**Eesmärk:** Debian1 teenindab kolme saiti ühelt IP-lt ja tundmatutele nimedele vastab eraldi vaikehost.

**Sammud:**

1. Paigalda Apache2 ja ava tulemüüris 80 ja 443 (4.2).
2. Loo kolm saidikausta ja testlehed (4.4).
3. Loo vaikehost `000-vaike.conf` (4.5).
4. Loo kolm vhosti (4.6).
5. Keela `000-default`, luba oma saidid ja moodulid `rewrite`, `headers` (4.7).
6. Kontrolli `apache2ctl -S` väljundit: milline on *default server*?
7. Testi `curl -H "Host: …"` käskudega (4.8).
8. Windowsis ava kõik kolm saiti nime järgi ja `http://10.0.XXX.10` IP järgi.
9. Peida serveri versioon (4.9).
10. Jälgi `tail -f` access-logi ja ava sait Windowsis.

**Kontrollpunkt:** iga sait näitab oma pealkirja; IP-ga avades näed „Tundmatu sait“; `curl -sI http://127.0.0.1/ | grep Server` → `Server: Apache`.

**Küsimused:**

1. Kuidas valib Apache, millist saiti näidata, kui kõik saidid on samal IP-l ja pordil?
2. Mis juhtuks ilma `000-vaike.conf` failita, kui avad saidi IP-aadressiga?
3. Mis vahe on `systemctl reload` ja `restart` vahel? Millal on vaja `restart`-i?
4. Miks `Options -Indexes`?
5. Mis on `sites-available` ja `sites-enabled` erinevus? Mida teeb `a2ensite` tegelikult failisüsteemis (`ls -l /etc/apache2/sites-enabled/`)?

---

### Labor 4. WordPress samas masinas

**Eesmärk:** `wp.perenimi.local` on töötav WordPress, mille andmebaas on samas masinas ja kättesaamatu võrgust.

**Sammud:**

1. Paigalda MariaDB ja PHP (5.2), kontrolli PHP tööd `info.php`-ga ja kustuta see.
2. `mariadb-secure-installation` (5.3).
3. Loo andmebaas `wp_db` ja kasutaja `wp_kasutaja@localhost` (5.4).
4. Laadi alla WordPress ja kopeeri saidi kausta (5.5).
5. Seadista `wp-config.php` koos unikaalsete turvavõtmetega (5.6).
6. Määra failiõigused (5.7).
7. Paigalda WordPress brauseris, lülita sisse püsiviited „Postituse nimi“ (5.8).
8. Tee üks postitus ja leia see andmebaasist käsurealt.

**Kontrollpunkt:**

```bash
sudo mariadb -e "SELECT post_title FROM wp_db.wp_posts WHERE post_status='publish';"
sudo ss -tlnp | grep 3306                       # 127.0.0.1:3306
ls -l /var/www/wp.perenimi.local/wp-config.php  # -rw-r----- www-data www-data
```

**Küsimused:**

1. Joonista (või kirjelda) LAMP-päringu teekond brauserist andmebaasini ja tagasi.
2. Miks on andmebaasi kasutaja `'wp_kasutaja'@'localhost'`, mitte `root`?
3. Mis juhtub, kui `AllowOverride` on `None` ja lülitad sisse püsiviited?
4. Milleks on `wp-config.php` turvavõtmed? Mis juhtub, kui neid muudad?
5. Miks `chmod 640` `wp-config.php` failile?

---

### Labor 5. WordPress kaugandmebaasiga

**Eesmärk:** `blogi.perenimi.local` töötab Debian1-s, andmebaas on Debian2-s ja sellele pääseb ligi ainult Debian1.

**Sammud:**

1. Paigalda Debian2-le MariaDB ja turva see (6.2).
2. Lukk 1: `bind-address` (6.3).
3. Lukk 2: andmebaas `blogi_db`, kasutaja `blogi_kasutaja@10.0.XXX.10` (6.4).
4. Lukk 3: tulemüür (6.5).
5. Testi ühendust Debian1-st käsurealt (6.6). **Proovi sama Ubuntust** – peab ebaõnnestuma. Kirjuta veateade päevikusse.
6. Paigalda WordPress saidile `blogi.perenimi.local` (6.7).
7. Kontrolli, et postitused on Debian2 andmebaasis (6.8).
8. **Rikkekatse:** sulge Debian2-s tulemüüris port 3306 (`sudo ufw delete allow from 10.0.XXX.10 to any port 3306 proto tcp`). Mis näitab brauser? Mis on Apache error-logis? Taasta reegel.

**Kontrollpunkt:** `mariadb -h 10.0.XXX.20 -u blogi_kasutaja -p -e "SELECT CURRENT_USER();"` Debian1-st töötab; Ubuntust annab vea; brauseris töötab `http://blogi.perenimi.local`.

**Küsimused:**

1. Millised kolm „lukku“ pidid olema lahti? Mis veateate annab iga kinnine lukk?
2. Miks mitte luua kasutajat `'blogi_kasutaja'@'%'`?
3. Mis eelised ja puudused on andmebaasi eraldi serveris hoidmisel?
4. Liigub praegu andmebaasi parool võrgus krüptitult? Kuidas seda kontrollida (`tcpdump`) ja parandada?

---

### Labor 6. Labori CA ja HTTPS

**Eesmärk:** kõik veebisaidid töötavad HTTPS-iga ja Windowsi brauser usaldab neid ilma hoiatuseta.

**Sammud:**

1. Loo Debian2-s labori CA (7.2).
2. Väljasta sert Debian1-le (SAN: www, wp, blogi, perenimi.local, debian1) ja Ubuntule (SAN: mail, ubuntu) (7.3).
3. Kopeeri failid `scp`-ga (7.4).
4. Debian1: paigalda sert, tee HTTPS vhostid HTTP → HTTPS suunamisega kõigile kolmele saidile (7.5).
5. Muuda WordPressi aadressid `https://`-ks (7.6).
6. Ubuntu: paigalda sert ja CA (7.8).
7. Windowsi klient: impordi `ca.crt` *Trusted Root* hoidlasse (7.7).
8. Ava kõik saidid Windowsis, vaata serti (luku ikoon → *Connection is secure → Certificate is valid*): kes on väljastaja, millised nimed on SAN-is, millal kehtivus lõpeb?
9. **Katse:** ava `https://10.0.XXX.10`. Milline hoiatus ja miks?

**Kontrollpunkt:** `http://wp.perenimi.local` suunab `https://`-le ja leht avaneb lukuga; `openssl s_client … | grep "Verify return code"` → `0 (ok)`.

**Küsimused:**

1. Miks brauser usaldab nüüd serti, mida eile ei usaldanud? Mis muutus?
2. Miks peab `ca.key` olema kõige paremini kaitstud fail?
3. Mis vahe on CN-il ja SAN-il? Kumba brauser kontrollib?
4. Mida teeb `Strict-Transport-Security` päis?
5. Miks tootmises tehakse privaatvõti sihtserveris ja CA-le saadetakse ainult CSR?

---

### Labor 7. Postfix ja Dovecot

**Eesmärk:** Ubuntu on meiliserver: võtab vastu kirju `@perenimi.local` aadressidele, lubab sisseloginud kasutajatel saata TLS-iga ja annab postkastid IMAPS-iga.

**Sammud:**

1. Kontrolli eeldusi: `hostname -f`, `dig MX`, `dig -x 10.0.XXX.30`, serdid olemas.
2. Paigalda Postfix (*Internet Site*, `perenimi.local`) ja Dovecot (9.2).
3. Postfixi põhiseaded, TLS, autentimine ja piirangud `postconf -e` käskudega (9.3–9.5).
4. `login_maps.regexp` (9.5).
5. `master.cf`: submission ja submissions (9.6). `sudo postfix check`.
6. Dovecot `local.conf` (9.7). `sudo doveconf -n`.
7. Kasutajad `mari` ja `jaan`, aliased (9.8). `doveadm auth test`.
8. Tulemüür (9.9).
9. Tee kõik 8 testi peatükist 9.10 ja kopeeri iga testi oluline vastusrida laboripäevikusse.
10. Leia logist ühe kirja kõik read järjekorra-ID järgi (9.12).

**Kontrollpunkt:**

| Test | Oodatav |
| --- | --- |
| port 25 kohalik kiri | `250 2.0.0 Ok: queued` |
| avatud relee | `554 5.7.1 … Relay access denied` |
| 587 + AUTH | `235 2.7.0 Authentication successful` |
| võõras saatja | `553 5.7.1 … not owned by user jaan` |
| AUTH ilma TLS-ita | AUTH-i ei pakuta |
| IMAPS | `* SEARCH 1 2 …` |

**Küsimused:**

1. Mis vahe on portidel 25, 587 ja 465?
2. Miks pordil 25 ei pakuta autentimist?
3. Mis on avatud relee ja miks see on ohtlik? Milline seade selle keelab?
4. Kuidas Postfix kontrollib kasutaja parooli, kui tal endal paroolifaili pole?
5. Mis on LMTP ja milleks seda vaja on?
6. Mis vahe on ümbriku `MAIL FROM`-il ja `From:` päisel? Too näide, kus need erinevad.
7. Miks on Dovecoti soklid kaustas `/var/spool/postfix/private/`?

---

### Labor 8. DKIM, SPF, DMARC ja fail2ban

**Eesmärk:** väljaminevad kirjad on DKIM-iga allkirjastatud, domeenil on SPF, DKIM ja DMARC kirjed ning paroolide äraarvamine on blokeeritud.

**Sammud:**

1. Paigalda OpenDKIM ja genereeri võti selektoriga `s1` (10.2).
2. Tabelid ja `opendkim.conf` – **ära unusta `Nameservers` rida** (10.3–10.4).
3. Ühenda Postfixiga (10.5).
4. Lisa Debian2 tsooni SPF, DMARC ja DKIM kirjed; suurenda seerianumbrit (10.6).
5. `opendkim-testkey` → `key OK` (10.7).
6. Saada kiri ja kontrolli allkirja `opendkim-testmsg`-ga (10.7).
7. **Katse:** muuda Maildiris salvestatud kirja sisu ühe tähe võrra (`sudo nano`) ja kontrolli allkirja uuesti. Mis juhtus?
8. Paigalda fail2ban (10.8). Kontrolli `fail2ban-regex`-iga.
9. Saada Debian1-st 6 korda vale parooliga (`swaks … --auth-password vale`), kontrolli `fail2ban-client status postfix-sasl`, vabasta IP.
10. Täida turvakontrolli tabel 10.10.

**Kontrollpunkt:** `opendkim-testkey` → `key OK`; kirja päises `DKIM-Signature: … d=perenimi.local; s=s1`; `dig +short TXT _dmarc.perenimi.local` vastab; Debian1 IP oli fail2ban-i nimekirjas.

**Küsimused:**

1. Mida kontrollib SPF, mida DKIM ja mida DMARC? Miks on vaja kõiki kolme?
2. Seleta lahti `v=spf1 mx -all`. Mis vahe on `-all` ja `~all` vahel?
3. Miks DKIM-allkiri läks sammus 7 katki? Mida see tõestab?
4. Mis on DMARC „alignment“? Too näide kirjast, mis läbib SPF-i, kuid ei läbi DMARC-it.
5. Miks oli vaja OpenDKIM-ile eraldi `Nameservers` rida?
6. Miks on `p=none` → `p=quarantine` → `p=reject` järjekord mõistlik uue domeeni puhul?

---

### Labor 9. Veebimeil Roundcube

**Eesmärk:** Windowsi kliendis avaneb `https://mail.perenimi.local`, kasutaja logib sisse, loeb ja saadab kirju.

**Sammud:**

1. Paigalda Apache2 ja Roundcube SQLite andmebaasiga (11.2).
2. Seadista `imap_host`, `smtp_host` ja lisaseaded (11.3).
3. Apache vhost `mail.perenimi.local` HTTP → HTTPS suunamisega (11.4).
4. Manuste suurus (11.5).
5. Test käsurealt (11.6).
6. Windowsis: logi sisse kui `mari`, saada kiri `jaan`-ile, logi sisse kui `jaan`, vasta (11.7).
7. Leia kirja lähtekoodist DKIM-allkiri ja `ESMTPSA`.
8. Lülita sisse fail2ban `roundcube-auth` ja testi (11.9).
9. Valikuline: seadista Thunderbird (11.8).
10. **Katse:** muuda Roundcube'is ajutiselt `imap_host` väärtuseks `localhost:143`. Mis juhtub sisselogimisel? Mis on `errors.log`-is? Taasta.

**Kontrollpunkt:** Windowsis on lukuga `https://mail.perenimi.local`; `mari` ja `jaan` saavad teineteisele kirjutada; kaustas „Saadetud“ on koopia.

**Küsimused:**

1. Milliste protokollidega räägib Roundcube Dovecoti ja Postfixiga? Mis portidel?
2. Miks Postfixi logis on klient Ubuntu ise, mitte Windows?
3. Miks ei tööta paketi vaikeseadistus `localhost:143`?
4. Kuidas Roundcube teab, millise parooliga Postfixi sisse logida?
5. Miks on `config`, `temp` ja `logs` kaustad `Require all denied`?

---

### Labor 10. Väljaminev post relay kaudu

**Eesmärk:** Roundcube'ist saadetud kiri jõuab päris internetis olevasse postkasti.

**Sammud:**

1. Võta õpetajalt relay andmed (server, port, kasutaja, parool) või loo laboriks Gmaili konto ja rakenduse parool (12.3).
2. Paigalda `libsasl2-modules` (12.4).
3. `sasl_passwd` ja `postmap` (12.5).
4. `generic` aadresside ümberkirjutus (12.6).
5. Postfixi relay-seaded (12.7).
6. Saada Roundcube'ist kiri oma isiklikule aadressile; jälgi logi (12.8).
7. Ava saabunud kirja päised: kes on `From:`? Milline DKIM ja SPF tulemus?
8. Saada kiri ka `jaan@perenimi.local`-ile ja kontrolli, et see **ei** läinud relay kaudu.

**Kontrollpunkt:** logis `relay=<relay>:587 … status=sent`; kiri on isiklikus postkastis; kohalik kiri on `relay=…[private/dovecot-lmtp]`.

**Küsimused:**

1. Miks ei saa laborist otse `gmail.com` MX-serverile saata?
2. Miks on `smtp_tls_security_level = encrypt`, aga sissetuleval pordil 25 `may`?
3. Mida teeb `smtp_generic_maps` ja miks see on vajalik?
4. Kuhu jõuab vastus, kui adressaat vajutab „Vasta“? Miks?
5. Mida oleks vaja, et `perenimi`-l oleks päris internetis töötav meiliserver?

---

### Labor 11. Tõrkeotsingu harjutus

**Eesmärk:** leida ja parandada vigu süsteemselt: sümptom → kiht → logi → põhjus → parandus.

Töötage paarides: üks teeb kaaslase süsteemi (või õpetaja teeb) **ühe rikke korraga**, teine leiab ja parandab selle. Iga rikke kohta kirjuta päevikusse: sümptom, millise käsuga/logiga põhjuse leidsid, parandus.

| # | Rike (tegija teeb) | Masin |
| --- | --- | --- |
| 1 | tsoonifailis `mail` kirje IP muudetud, seerianumber suurendatud | Debian2 |
| 2 | tsoonifailis süntaksiviga, `named` taaskäivitatud | Debian2 |
| 3 | `wp.perenimi.local.conf` vhostis `AllowOverride None` | Debian1 |
| 4 | `wp-config.php` `DB_PASSWORD` vale | Debian1 |
| 5 | Debian2 tulemüürist eemaldatud port 3306 reegel | Debian2 |
| 6 | `systemctl stop dovecot` | Ubuntu |
| 7 | `local.conf`-is `ssl_cert` real puudub `<` | Ubuntu |
| 8 | `main.cf`-is `mynetworks = 10.0.XXX.0/24` (avatud relee laborile!) | Ubuntu |
| 9 | `systemctl stop opendkim` | Ubuntu |
| 10 | Roundcube'is `smtp_host = 'tls://localhost:587'` | Ubuntu |
| 11 | Windowsi kliendis DNS muudetud `8.8.8.8`-ks | Windows |
| 12 | Windowsist eemaldatud labori CA | Windows |

Kasuta peatüki 14 kontrollnimekirja ja tabeleid. Rikke 8 puhul: kuidas seda **testiga** avastada, kui teenused justkui töötavad?

**Küsimused:**

1. Millised rikked olid kasutajale nähtavad kohe ja millised alles hiljem või üldse mitte?
2. Milline logifail aitas kõige rohkem?
3. Miks on rike 8 kõige ohtlikum, kuigi kõik „töötab“?
