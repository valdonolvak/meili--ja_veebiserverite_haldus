# Meili- ja veebiserverite haldus Linuxis — õppematerjal ja laboritööd

Õppematerjal veebi-, nime- ja meiliserverite haldusest Linuxis: mõisted, selgitused, joonised, interaktiivsed harjutused ja 11 laboritööd. Labor töötab **Proxmox VE** keskkonnas:

| Masin | OS | IP | Roll |
| --- | --- | --- | --- |
| Debian1 | Debian 13 | 10.0.XXX.10 | Apache2, PHP, WordPress (`www`, `wp`, `blogi`) |
| Debian2 | Debian 13 | 10.0.XXX.20 | BIND9 (`perenimi.local`), MariaDB, labori CA |
| Ubuntu | Ubuntu 24.04 LTS | 10.0.XXX.30 | Postfix, Dovecot, OpenDKIM, Roundcube (`mail.perenimi.local`) |
| Windows klient | Windows 11 | 10.0.XXX.100 | brauser, testimine |
| Windows Server | Windows Server 2022 | 10.0.XXX.40 | teine klient |

**XXX = Proxmoxi silla number** (`vmbrXXX`), võrk `10.0.XXX.0/24`.

**Domeeninimi = õppija perekonnanimi.** Kus materjalis on `perenimi`, kirjuta oma perekonnanimi väiketähtedega ja ilma täpitähtedeta (nt Tõnisson → `tonisson.local`).

**Lõpptulemus:** Windowsi kliendis avaneb `https://mail.perenimi.local`, kasutaja logib sisse, saadab ja loeb kirju nii oma domeenis kui ka päris internetti (relay kaudu); kõik ühendused on TLS-iga, kirjad on DKIM-allkirjaga ning domeenil on SPF ja DMARC.

![Labori võrk](peatykid/joonised/01-topoloogia.png)

## Interaktiivsed harjutused

| Simulaator | Teema |
| --- | --- |
| [DNS-i simulaator](https://valdonolvak.github.io/meili--ja_veebiserverite_haldus/interaktiivne/dns-simulaator.html) | Kes vastab: tsoonifail, vahemälu või edastaja; kirjetüübid; rikked (seerianumber, puuduv punkt, ACL) |
| [Apache virtuaalhosti simulaator](https://valdonolvak.github.io/meili--ja_veebiserverite_haldus/interaktiivne/apache-vhost-simulaator.html) | Millise saidi Apache valib (`Host:` päis, `ServerName`, vaikehost, HTTP→HTTPS, SNI) |
| [E-kirja teekonna simulaator](https://valdonolvak.github.io/meili--ja_veebiserverite_haldus/interaktiivne/e-kirja-simulaator.html) | SMTP vestlus samm-sammult, Postfixi piirangud, DKIM/SPF/DMARC; lülita sisse rikkeid ja vaata, kus ahel katkeb |

## Sisukord

- [1. Sissejuhatus ja laborikeskkond](peatykid/01-sissejuhatus-ja-laborikeskkond.md)
- [2. Linuxi serveri alused: võrk, SSH, sudo, teenused, logid, tulemüür](peatykid/02-linuxi-serveri-alused.md)

### Veebiserver

- [3. DNS ja BIND9 (Debian2)](peatykid/03-dns-bind9.md)
- [4. Apache2 ja virtuaalhostid (Debian1)](peatykid/04-apache2-ja-virtuaalhostid.md)
- [5. WordPress samas masinas – LAMP (Debian1)](peatykid/05-wordpress-samas-masinas.md)
- [6. WordPress kaugandmebaasiga (Debian1 + Debian2)](peatykid/06-wordpress-kaugandmebaasiga.md)
- [7. Labori CA ja HTTPS](peatykid/07-labori-ca-ja-https.md)

### Meiliserver

- [8. E-posti alused: rollid, protokollid, DNS-kirjed](peatykid/08-e-posti-alused.md)
- [9. Postfix ja Dovecot (Ubuntu)](peatykid/09-postfix-ja-dovecot.md)
- [10. Meiliserveri turvalisus: DKIM, SPF, DMARC, fail2ban](peatykid/10-meiliserveri-turvalisus.md)
- [11. Veebimeil Roundcube](peatykid/11-roundcube-veebimeil.md)
- [12. Väljaminev post internetti relay kaudu](peatykid/12-valjaminev-post-relay.md)

### Praktika

- [13. Laboritööd 1–11](peatykid/13-laboritood.md)
- [14. Tõrkeotsing, käskude spikker ja enesekontroll](peatykid/14-torkeotsing-ja-spikker.md)
- [15. Allikad](peatykid/15-allikad.md)

## Testitud

Meiliserveri seadistus (peatükid 7.8, 9–12) on läbi testitud Ubuntu 24.04-l (Postfix 3.8.6, Dovecot 2.3.21, OpenDKIM 2.11, Roundcube 1.6.6, fail2ban 1.0.2): kohalik kohaletoimetamine, relee keeld, 587/465 autentimine, võltssaatja keeld, DKIM allkiri ja selle kontroll, IMAPS, Roundcube'i sisselogimine ja saatmine brauserist ning relay-saatmine koos aadressi ümberkirjutusega. BIND9 tsoonifailid on kontrollitud `named-checkzone`-iga.

> **Dovecot:** meiliserver on Ubuntu 24.04 peal, sest Debian 13 sisaldab Dovecot 2.4-t, mille seadistuse süntaks on teistsugune. Peatüki 9 Dovecoti seadistust ei saa Debian 13-s kasutada.

## Repo ülesehitus

```text
README.md                 sisukord (see fail)
peatykid/                 iga peatükk eraldi .md failina
peatykid/joonised/        skeemid PNG-failidena
interaktiivne/            simulaatorid (HTML, avanevad GitHub Pagesi kaudu)
```

### Varasemad juhendid (repo juurkaustas)

Uus materjal kasutab neid osaliselt ja viitab neile peatükkide lõpus. Täielik seoste tabel on peatükis [15. Allikad](peatykid/15-allikad.md).

- `Veebiserver/` – Apache ja WordPressi paigaldus, sudo, iseseisev töö (WordPress teisele serverile) ja kontrollskriptid
- `Epost_DNS/` – Postfix, Dovecot, SPF/DKIM/DMARC, BIND9, DDNS
- `Postfix-Dovecot/` – meiliserver virtuaalkasutajatega (MySQL)
- `Turvalisus/` – HTTPS, ründed veebiserveritele
- `test/` – kontrollskriptid
