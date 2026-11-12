## 2. Linuxi serveri alused

Enne teenuste paigaldamist peavad mõlemad Linuxi serverid olema ühtemoodi korras: õige nimi, staatiline IP, nimeserver, SSH ligipääs, `sudo` ja uuendused. See peatükk on Labor 1 teooria.

### 2.1 Mõisted

| Termin | Selgitus | Näide laboris |
| --- | --- | --- |
| Hostinimi | Masina lühinimi. | `debian` |
| FQDN (*Fully Qualified Domain Name*) | Täisnimi koos domeeniga, lõpeb DNS-is punktiga. | `debian.perenimi.local.` |
| Staatiline IP | Käsitsi määratud aadress, mis ei muutu. Serveritel alati staatiline. | `192.168.XXX.10/24` |
| Lüüs (*gateway*) | Ruuter, kuhu saadetakse kõik väljaspoole oma võrku minevad paketid. | `192.168.XXX.1` |
| Nimeserver (*resolver*) | Server, kellelt masin küsib nimede IP-aadresse. | `192.168.XXX.10` (Debian) |
| Otsingudomeen (*search*) | Lisatakse lühinimele automaatselt: `ping mail` → `mail.perenimi.local`. | `perenimi.local` |
| systemd / `systemctl` | Teenuste haldur: käivitab, peatab, lubab automaatkäivituse. | `systemctl status apache2` |
| journald / `journalctl` | Süsteemi logi (binaarne andmebaas). | `journalctl -u named -f` |
| rsyslog | Kirjutab logid tekstifailidesse kausta `/var/log/`. | `tail -f /var/log/syslog` |
| Pakihaldur `apt` | Paigaldab ja uuendab tarkvara. | `apt install bind9` |
| `sudo` | Käivitab ühe käsu administraatori (root) õigustes. | `sudo nano /etc/hosts` |
| SSH | Krüpteeritud kaughaldus (port 22). | `ssh opilane@192.168.XXX.10` |
| Tulemüür `ufw` | Lihtne liides Linuxi paketifiltrile (nftables/iptables). | `ufw allow 80/tcp` |

### 2.2 sudo õigus (Debian)

Kui Debiani paigaldusel anti **root-kasutajale parool**, siis `sudo` paketti ei paigaldata ja tavakasutaja ei saa administraatori käske käivitada. Lahendus:

**Debian:**

```bash
su -                        # muutu rootiks (küsib root-kasutaja parooli)
apt install sudo -y
usermod -aG sudo opilane    # asenda "opilane" oma kasutajanimega
exit
```

Logi välja ja uuesti sisse (rühmaliikmesus loetakse sisselogimisel). Kontroll: `sudo whoami` → `root`.

Ubuntul on paigaldusel loodud kasutaja juba `sudo` rühmas.

> Põhjalikum juhend: [Kasutaja sudo gruppi lisamine](../Veebiserver/1b.%20Kasutaja%20sudo%20gruppi%20lisamine.md).

### 2.3 Võrguliidese nimi

Proxmoxi VirtIO võrgukaart on Linuxis tavaliselt nimega `ens18`. Kontrolli:

```bash
ip -br link        # -br = lühike väljund
ip -br addr
```

Kui sinu liides on teise nimega (nt `ens19`, `enp6s18`), asenda allpool `ens18` oma nimega.

### 2.4 Staatiline IP Debian 13-s (ifupdown)

Debian 13 serveripaigaldus haldab võrku failiga `/etc/network/interfaces`.

**Debian:**

```bash
sudo nano /etc/network/interfaces
```

```text
# Loopback
auto lo
iface lo inet loopback

# Labori võrk
auto ens18
iface ens18 inet static
    address 192.168.XXX.10/24
    gateway 192.168.XXX.1
```

Nimeserver kirjuta otse faili `/etc/resolv.conf`:

```bash
sudo nano /etc/resolv.conf
```

```text
# Debian on ise nimeserver (BIND9, peatükk 3)
nameserver 127.0.0.1
search perenimi.local
```

Debian on ise labori nimeserver. **Kuni BIND9 pole veel paigaldatud** (peatükk 3), kirjuta ajutiselt `nameserver 1.1.1.1` (või õpetaja antud DNS), muidu `apt` ei leia pakihoidlat. Pärast BIND9 paigaldust muuda see `127.0.0.1`-ks.

> **Miks Debianil ei saa olla DHCP-ga aadress?** Debian ise jagab DHCP-d (peatükk 4) ja on kõigi teiste nimeserver – tema aadress peab olema alati sama.

Rakenda ja kontrolli:

```bash
sudo systemctl restart networking
ip -br addr show ens18
ip route                     # default via 192.168.XXX.1
ping -c 2 192.168.XXX.1
```

> Kui Debian on paigaldatud koos NetworkManageriga või kasutad systemd-networkd-d, vaata repo varasemat juhendit [Võrgu seadistamine Debianil](../V%C3%B5rgu%20seadistamine%20Debianil.md).

### 2.5 Staatiline IP Ubuntu 24.04-s (netplan)

Ubuntu kasutab **netplani**. Vaata, mis fail kaustas on: `ls /etc/netplan/`. Asenda selle sisu (või loo `/etc/netplan/50-labor.yaml` ja eemalda teised):

**Ubuntu:**

```bash
sudo nano /etc/netplan/50-labor.yaml
```

```yaml
network:
  version: 2
  ethernets:
    ens18:
      dhcp4: false
      addresses:
        - 192.168.XXX.20/24
      routes:
        - to: default
          via: 192.168.XXX.1
      nameservers:
        addresses: [192.168.XXX.10]
        search: [perenimi.local]
```

```bash
sudo chmod 600 /etc/netplan/*.yaml   # netplan hoiatab, kui fail on teistele loetav
sudo netplan try                     # rakendab 120 s; kinnita Enteriga
resolvectl status ens18              # DNS Servers: 192.168.XXX.10, DNS Domain: perenimi.local
```

> **Oluline – `.local` ja systemd-resolved.** Ubuntu nimelahendaja `systemd-resolved` käsitleb `.local` lõpuga nimesid vaikimisi **mDNS-i** (Bonjour/Avahi) nimedena. Rida `search: [perenimi.local]` teeb `perenimi.local` selle liidese **marsruutimisdomeeniks** ja siis lähevad `*.perenimi.local` päringud BIND9-le. Kontroll: `resolvectl query mail.perenimi.local`. Kui vastus on „No appropriate name servers…“, lisa käsitsi: `sudo resolvectl domain ens18 perenimi.local '~local'`.

Kui Ubuntu VM on loodud *cloud-init* tõmmisest, võib cloud-init võrguseadistuse taaskäivitusel üle kirjutada. Keela see: `echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`.

### 2.6 Hostinimi ja /etc/hosts

**Debian:**

```bash
sudo hostnamectl set-hostname debian
sudo nano /etc/hosts
```

```text
127.0.0.1       localhost
192.168.XXX.10     debian.perenimi.local debian
```

**Ubuntu** – meiliserveri hostinimi on `mail`:

```bash
sudo hostnamectl set-hostname mail
```

```text
127.0.0.1       localhost
192.168.XXX.20     mail.perenimi.local mail
```

Kontroll: `hostname` → lühinimi, `hostname -f` → FQDN. Debianis on failis vaikimisi rida `127.0.1.1 vana-nimi` – kustuta see, muidu `hostname -f` annab vale nime.

> **Miks see oluline on?** Postfix kasutab FQDN-i oma tervitusreal (`220 mail.perenimi.local ESMTP`) ja HELO-s. Vale FQDN = teised serverid lükkavad kirjad tagasi.

### 2.7 Uuendused ja põhitööriistad

**Debian ja Ubuntu:**

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y curl wget nano unzip ca-certificates bind9-dnsutils net-tools ufw
```

`bind9-dnsutils` annab käsud `dig`, `nslookup`, `host`; `net-tools` vana `netstat`-i (uus vaste on `ss`).

### 2.8 SSH ja võtmepõhine sisselogimine Windowsist

Servereid hallatakse **kaugelt**. Proxmoxi konsool sobib paigalduseks ja hädaolukorraks, aga igapäevatöö käib SSH-ga (*Secure Shell*, port 22): Windowsi PowerShellist saab käske kopeerida ja kleepida, avada mitu akent korraga ning kopeerida faile `scp`-ga.

> **Millal Windowsist ühenduda?** Windowsi klient saab IP-aadressi Debiani DHCP-serverilt (peatükk 4, labor 3). Enne seda on tal aadress `169.254.x.x` ja serveritesse ta ei ulatu. Tee jaotis 2.8.1 kohe, jaotised 2.8.2–2.8.6 aga pärast laborit 3. Kui tahad SSH-d kohe kasutada, pane Windowsile ajutiselt käsitsi aadress `192.168.XXX.200/24` ja hiljem taasta DHCP (2.11).

#### 2.8.1 SSH-server mõlemas Linuxis

Debian paigaldab OpenSSH serveri, kui paigaldusel valiti „SSH server“. Ubuntu Serveri paigaldaja küsib sama („Install OpenSSH server“). Kontrolli ja vajadusel paigalda.

**Debian ja Ubuntu:**

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
sudo ss -tlnp | grep :22          # LISTEN 0.0.0.0:22 … sshd
```

#### 2.8.2 Esimene ühendus parooliga

Windows 11-s on OpenSSH klient vaikimisi olemas. Kontroll PowerShellis: `ssh -V` → `OpenSSH_for_Windows_9.x`. Kui käsku pole, lisa see: *Settings → System → Optional features → Add a feature → OpenSSH Client* või administraatori PowerShellis:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0
```

Ühendu (PowerShell või cmd):

```powershell
ssh opilane@192.168.XXX.10
```

Esimesel korral küsib SSH:

```text
The authenticity of host '192.168.XXX.10 (192.168.XXX.10)' can't be established.
ED25519 key fingerprint is SHA256:q3V9…kX0.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

See on **serveri** tuvastamine: iga SSH-server tekitab paigaldamisel oma võtmepaari (*host key*) ja klient jätab selle sõrmejälje meelde faili `C:\Users\<kasutaja>\.ssh\known_hosts`. Järgmistel kordadel kontrollib klient, et tegemist on sama serveriga. Põhimõte on sama mis TLS-serdil (peatükk 8), ainult ilma CA-ta: esimesel korral usaldad sõrmejälge ise.

Korrektne on sõrmejälg enne `yes` vastamist üle kontrollida. Vaata seda serveri konsoolis (Proxmox):

```bash
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub     # 256 SHA256:q3V9…kX0 root@debian (ED25519)
```

Kui sõrmejäljed ühtivad, vasta `yes` ja sisesta parool. Tee sama Ubuntuga: `ssh opilane@192.168.XXX.20`.

> **`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`** – serveri võti on teine kui meelde jäetud. Laboris tähendab see peaaegu alati, et masin paigaldati uuesti või tõmmisest taastati. Päris elus võib see tähendada ka ründajat ühenduse vahel. Kui oled kindel, et server paigaldati uuesti, kustuta vana kirje: `ssh-keygen -R 192.168.XXX.10`.

#### 2.8.3 Võtmepaari loomine Windowsis

Parooliga sisselogimine töötab, aga sellel on kaks puudust: parooli tuleb iga kord trükkida ja internetis olevat SSH-serverit proovivad robotid ööpäev läbi paroole ära arvata. **Võtmepõhine sisselogimine** kasutab sama ideed nagu TLS (peatükk 8.3):

- **privaatvõti** jääb Windowsi arvutisse ega liigu kunagi võrku;
- **avalik võti** kopeeritakse serveri faili `~/.ssh/authorized_keys`;
- sisselogimisel saadab server juhusliku väljakutse, klient allkirjastab selle privaatvõtmega ja server kontrollib allkirja avaliku võtmega. Parooli võrgus ei liigu.

Loo võtmepaar **Windowsis** (PowerShell, tavakasutajana):

```powershell
ssh-keygen -t ed25519 -C "opilane@win11"
```

```text
Generating public/private ed25519 key pair.
Enter file in which to save the key (C:\Users\opilane/.ssh/id_ed25519):      ← Enter
Enter passphrase (empty for no passphrase):                                   ← salafraas
Enter same passphrase again:
Your identification has been saved in C:\Users\opilane/.ssh/id_ed25519
Your public key has been saved in C:\Users\opilane/.ssh/id_ed25519.pub
```

| Valik / fail | Selgitus |
| --- | --- |
| `-t ed25519` | Võtme tüüp. Ed25519 on kaasaegne, lühike ja kiire. Vanemate seadmete jaoks kasutatakse `-t rsa -b 4096`. |
| `-C "opilane@win11"` | Kommentaar. See jääb avaliku võtme lõppu ja aitab serveri `authorized_keys` failis aru saada, kelle võti see on. |
| Salafraas (*passphrase*) | Krüpteerib privaatvõtme failis. Kui keegi faili varastab, ei saa ta seda ilma salafraasita kasutada. Laboris võib jätta tühjaks, päris töös mitte. |
| `id_ed25519` | **Privaatvõti.** Ära kopeeri seda kuhugi ega saada kellelegi. |
| `id_ed25519.pub` | **Avalik võti**, üks tekstirida. Selle võib anda igale serverile, kuhu tahad sisse logida. |

Vaata avalikku võtit:

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub
# ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI…  opilane@win11
```

#### 2.8.4 Avaliku võtme kopeerimine serveritesse

Linuxis on selleks käsk `ssh-copy-id`, Windowsis seda pole. Sama asja teeb üks PowerShelli rida: loeb avaliku võtme ja lisab selle SSH kaudu serveris faili `~/.ssh/authorized_keys` lõppu. Viimast korda küsitakse parooli.

**Windows (PowerShell) – Debian:**

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh opilane@192.168.XXX.10 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

**Windows (PowerShell) – Ubuntu:**

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh opilane@192.168.XXX.20 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Mida jutumärkides olev käsk serveris teeb:

| Osa | Selgitus |
| --- | --- |
| `mkdir -p ~/.ssh` | Loob kausta, kui seda veel pole. |
| `chmod 700 ~/.ssh` | Kausta pääseb ainult omanik. **SSH-server ignoreerib võtmeid, kui kaust või fail on teistele kirjutatav** – see kaitseb olukorra eest, kus keegi teine lisab sinu kontole oma võtme. |
| `cat >> ~/.ssh/authorized_keys` | Lisab torust (`\|`) tuleva avaliku võtme faili **lõppu**. `>>` ei kirjuta olemasolevaid võtmeid üle. |
| `chmod 600 …` | Faili loeb ja kirjutab ainult omanik. |

Proovi uuesti:

```powershell
ssh opilane@192.168.XXX.10
ssh opilane@192.168.XXX.20
```

Parooli ei küsita (kui panid salafraasi, küsitakse salafraasi). Serveris näed oma võtit:

```bash
cat ~/.ssh/authorized_keys
```

Kui parooli küsitakse ikka, vaata ühenduse logi: `ssh -v opilane@192.168.XXX.10`. Read `Offering public key: …id_ed25519` ja `Server accepts key` näitavad, kas võti pakuti ja võeti vastu. Serveri poolel on põhjus näha failis `/var/log/auth.log` (vt 2.9.2), tavaliselt `Authentication refused: bad ownership or modes for directory /home/opilane/.ssh`.

#### 2.8.5 Lühinimed: fail ~/.ssh/config Windowsis

IP-aadresside ja kasutajanime trükkimise asemel tee Windowsis seadistusfail:

```powershell
New-Item -ItemType File -Force $env:USERPROFILE\.ssh\config
notepad $env:USERPROFILE\.ssh\config
```

```text
Host debian
    HostName 192.168.XXX.10
    User opilane

Host ubuntu
    HostName 192.168.XXX.20
    User opilane
```

Nüüd piisab käskudest `ssh debian` ja `ssh ubuntu`. Samad nimed töötavad ka `scp`-ga: `scp ubuntu:/etc/postfix/main.cf .` Kui DNS töötab (peatükk 3), võid `HostName` real kasutada nimesid `debian.perenimi.local` ja `mail.perenimi.local`.

> **Salafraas ilma iga kord trükkimata:** Windowsis on teenus `ssh-agent`, mis hoiab lahtikrüpteeritud võtit mälus kuni väljalogimiseni. Administraatori PowerShellis: `Get-Service ssh-agent | Set-Service -StartupType Automatic; Start-Service ssh-agent`. Siis tavakasutajana: `ssh-add` (küsib salafraasi üks kord).

#### 2.8.6 Paroolisisselogimise keelamine

Kui võtmega sisselogimine töötab **mõlemasse** serverisse, võib parooli SSH jaoks keelata. Siis ei aita ründajale ka õigesti ära arvatud parool. Seadistus läheb eraldi faili kausta `sshd_config.d`, nii et põhifail jääb puutumata ja uuendused seda üle ei kirjuta.

**Debian ja Ubuntu:**

```bash
sudo nano /etc/ssh/sshd_config.d/10-labor.conf
```

```text
PasswordAuthentication no
PermitRootLogin no
```

```bash
sudo sshd -t                                  # süntaksi kontroll, vigade puudumisel väljund puudub
sudo sshd -T | grep -E "^passwordauthentication|^permitrootlogin"
sudo systemctl restart ssh
```

- `PasswordAuthentication no` – parooliga SSH-i kaudu sisse ei saa. Konsoolis (Proxmox) töötab parool edasi.
- `PermitRootLogin no` – root ei saa SSH-ga otse sisse. Logitakse sisse oma kasutajaga ja kasutatakse `sudo`-d, nii jääb logisse jälg, kes mida tegi.
- Faili nimi algab numbriga **10**, sest sshd kasutab iga valiku puhul **esimest leitud väärtust** ja loeb faile tähestikulises järjekorras. Ubuntus võib paigaldaja olla loonud faili `50-cloud-init.conf` reaga `PasswordAuthentication yes`. Kui meie fail oleks nimega `60-…`, jääks see rida peale. `sshd -T` näitab tegelikult kehtivat väärtust.

> ⚠️ **Ära sulge olemasolevat SSH-akent enne, kui oled uues aknas edukalt sisse loginud.** Kui midagi läks valesti, saad vanas aknas vea parandada. Hädaolukorras aitab Proxmoxi konsool.

Kontroll Windowsist: `ssh -o PubkeyAuthentication=no opilane@192.168.XXX.10` → `Permission denied (publickey).` See tähendab, et parooliga enam sisse ei saa.

#### 2.8.7 Failide kopeerimine Linuxite vahel

Peatükis 8 kopeerime serdid Debianist Ubuntule `scp`-ga:

```bash
scp fail.txt opilane@192.168.XXX.20:/home/opilane/
```

Kui keelasid paroolisisselogimise (2.8.6), vajab ka **Debian** Ubuntu jaoks võtit. Peatükis 8 käivitatakse `scp` **root**'ina (CA failid on kaustas `/root/labori-ca`), seega teeme võtme root'ile. Võti lubab Debiani root'il logida Ubuntusse sisse kasutajana `opilane`, mitte root'ina.

**Debian:**

```bash
sudo -i
ssh-keygen -t ed25519 -C "root@debian"        # Enter, Enter, Enter
ssh-copy-id opilane@192.168.XXX.20
exit
```

Peatükis 11 kopeerib Ubuntu DKIM-kirje Debiani kasutajana `opilane`. Seega tee samamoodi võti ka Ubuntu kasutajale.

**Ubuntu (kasutajana `opilane`):**

```bash
ssh-keygen -t ed25519 -C "opilane@mail"       # Enter, Enter, Enter
ssh-copy-id opilane@192.168.XXX.10
```

`ssh-copy-id` teeb sama, mida Windowsis tegi pikk PowerShelli rida. NB! Ka `ssh-copy-id` vajab ühe korra parooli, nii et tee see **enne** paroolisisselogimise keelamist. Kui keelasid juba, lisa avaliku võtme (`id_ed25519.pub`) sisu teise serveri faili `/home/opilane/.ssh/authorized_keys` lõppu Windowsi SSH-akna kaudu (`nano`).

### 2.9 Teenused ja logid

#### 2.9.1 systemctl ja journalctl

| Tegevus | Käsk |
| --- | --- |
| Teenuse olek | `systemctl status apache2` |
| Käivita / peata / taaskäivita | `sudo systemctl start\|stop\|restart apache2` |
| Laadi seadistus uuesti ilma ühendusi katkestamata | `sudo systemctl reload apache2` |
| Automaatkäivitus sisse ja kohe käima | `sudo systemctl enable --now apache2` |
| Teenuse logi | `sudo journalctl -u apache2 -n 50` |
| Logi reaalajas | `sudo journalctl -u postfix -f` |
| Logi alates kellaajast | `sudo journalctl -u ssh --since "10 min ago"` |
| Ainult vead | `sudo journalctl -p err -b` (`-b` = alates viimasest käivitusest) |
| Millised pordid kuulavad | `sudo ss -tlnp` (t = TCP, l = kuulavad, n = numbrid, p = protsess) |

Kõik teenused saadavad oma logiread **systemd-journaldile**. See hoiab neid binaarses andmebaasis, mida loetakse käsuga `journalctl`. Journal on mugav ühe teenuse logi vaatamiseks, aga tavaliste tööriistadega (`tail`, `grep`, `less`) seda otse lugeda ei saa ning paljud programmid (nt fail2ban, logianalüsaatorid, vanemad juhendid) eeldavad klassikalisi tekstifaile kaustas `/var/log/`.

#### 2.9.2 rsyslog: klassikalised logifailid

**rsyslog** võtab journaldilt logiread vastu ja kirjutab need **tekstifailidesse**, sorteerides need allika (*facility*) järgi. Ubuntu 24.04-l on rsyslog vaikimisi olemas. **Debian 13 ei paigalda rsyslogi vaikimisi** ja seepärast pole seal faile `/var/log/syslog`, `/var/log/auth.log` ega `/var/log/mail.log`.

**Debian:**

```bash
sudo apt install -y rsyslog
sudo systemctl enable --now rsyslog
ls -l /var/log/*.log /var/log/syslog
```

Ubuntus kontrolli, et teenus töötab: `systemctl status rsyslog`.

Millisesse faili mis läheb, on kirjas failis `/etc/rsyslog.conf` (Ubuntus `/etc/rsyslog.d/50-default.conf`). Iga rida on kujul **allikas.tase  sihtfail**:

```text
*.*;auth,authpriv.none      -/var/log/syslog
auth,authpriv.*             /var/log/auth.log
cron.*                      -/var/log/cron.log
kern.*                      -/var/log/kern.log
mail.*                      -/var/log/mail.log
user.*                      -/var/log/user.log
```

| Fail | Mis seal on | Selles kursuses |
| --- | --- | --- |
| `/var/log/syslog` | kõik peale autentimise – üldine „kõik ühes kohas“ logi | BIND9, Kea DHCP, Apache'i käivitumine, MariaDB |
| `/var/log/auth.log` | sisselogimised, `sudo` kasutamine, SSH | 2.8 võtmete kontroll, fail2ban SSH kaitse |
| `/var/log/mail.log` | Postfix, Dovecot, OpenDKIM | peatükid 10–13, fail2ban meiliserveri kaitse |
| `/var/log/kern.log` | tuuma teated, ufw blokeeritud paketid (`[UFW BLOCK]`) | tulemüüri tõrkeotsing (2.10) |

- `*.*` – kõik allikad, kõik tasemed. `auth,authpriv.none` – välja arvatud autentimine. Paroolide ja kasutajanimedega seotud read on eraldi failis `auth.log`, mida loeb ainult grupp `adm`.
- `-` failinime ees tähendab, et rsyslog ei sünkrooni faili kettale iga rea järel. See on kiirem; voolukatkestuse korral võivad viimased read kaduma minna.
- Apache kirjutab oma päringulogid ise kausta `/var/log/apache2/` ja MariaDB kausta `/var/log/mysql/`. Need ei sõltu rsyslogist.

Logifailide lugemine:

```bash
sudo tail -f /var/log/syslog                         # reaalajas, Ctrl+C lõpetab
sudo tail -n 30 /var/log/auth.log                    # viimased 30 rida
sudo grep sshd /var/log/auth.log | tail              # ainult SSH read
sudo grep -i "error\|fail" /var/log/syslog | tail    # vead
sudo less +F /var/log/mail.log                       # sirvimine; Ctrl+C, siis q
```

Proovi kohe: ava Debianis `sudo tail -f /var/log/auth.log` ja logi Windowsist sisse `ssh debian`. Ilmub rida:

```text
2026-11-12T22:58:01.123456+02:00 debian sshd-session[2412]: Accepted publickey for opilane from 192.168.XXX.57 port 50122 ssh2: ED25519 SHA256:Hx7…
```

Rea osad on aeg (Debian 13 ja Ubuntu 24.04 kasutavad täpset ISO 8601 vormingut koos ajavööndiga), hostinimi, programm ja protsessi number nurksulgudes ning teade. `Accepted publickey` näitab, et sisselogimine käis võtmega. Parooliga oleks see `Accepted password`. Vale parooli korral on rida `Failed password for …` – just neid ridu otsib hiljem fail2ban (peatükk 11).

Teine kiire test: `logger "Tere logist"` saadab teate süsteemilogisse ja `sudo tail -n1 /var/log/syslog` näitab seda.

**Logide rotatsioon.** Et failid ketast täis ei kirjutaks, vahetab **logrotate** need regulaarselt (vaikimisi kord nädalas): `syslog` → `syslog.1` → `syslog.2.gz` … Vanimad failid kustutatakse. Mitu faili alles hoitakse ja kui tihti vahetatakse, on kirjas failis `/etc/logrotate.d/rsyslog`. Vanu pakitud faile saab lugeda käsuga `zless` või `zgrep`, nt `sudo zgrep sshd /var/log/auth.log.2.gz`.

> **journalctl või /var/log?** Mõlemad näitavad sama infot, sest rsyslog saab read journaldist. `journalctl -u teenus` on mugavam, kui tead, millist teenust otsid. Tekstifailid on mugavamad, kui otsid sündmust mitme teenuse ulatuses (`grep`), kopeerid logi kellelegi või kui tööriist (fail2ban) eeldab faili. Selles kursuses kasutame mõlemat.

### 2.10 Tulemüür ufw

`ufw` blokeerib kõik sissetulevad ühendused peale lubatute. **Luba SSH alati enne sisselülitamist**, muidu lõikad iseenda välja.

```bash
sudo ufw allow OpenSSH        # või: sudo ufw allow 22/tcp
sudo ufw enable
sudo ufw status numbered
```

Iga masina lõplikud reeglid lisame vastava teenuse peatükis:

| Masin | Lubatud sissetulevad pordid |
| --- | --- |
| Debian | 22, 53/tcp+udp ja 67/udp (labori võrgust), 80, 443 |
| Ubuntu | 22, 25, 80, 443, 465, 587, 993, 3306 (ainult Debianist) |

### 2.11 Windowsi klient

Windowsi klient saab IP-aadressi, lüüsi, nimeserveri ja domeeni **automaatselt Debiani DHCP-serverilt** (peatükk 4). Kliendis ei seadista midagi käsitsi – võrgukaart peab olema vaikeseadetes (*Obtain an IP address automatically*, *Obtain DNS server address automatically*).

Kontroll (PowerShell või cmd):

```powershell
ipconfig /all
```

| Rida | Oodatav väärtus |
| --- | --- |
| DHCP Enabled | Yes |
| IPv4 Address | 192.168.XXX.50 … 192.168.XXX.99 |
| Default Gateway | 192.168.XXX.1 |
| DHCP Server | 192.168.XXX.10 |
| DNS Servers | 192.168.XXX.10 |
| Connection-specific DNS Suffix | perenimi.local |

Kui IPv4 aadress algab **169.254.** (APIPA), ei vastanud ükski DHCP-server – vaata peatükki 4.11.

> Kui oled kliendile varem käsitsi aadressi või DNS-i pannud, taasta automaatne seadistus: *Settings → Network & internet → Ethernet → IP assignment → Edit → Automatic (DHCP)* ja sama *DNS server assignment* juures. Siis `ipconfig /renew`.
