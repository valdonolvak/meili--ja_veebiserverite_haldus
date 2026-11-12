## 2. Linuxi serveri alused

Enne teenuste paigaldamist peavad kõik kolm Linuxi masinat olema ühtemoodi korras: õige nimi, staatiline IP, nimeserver, SSH ligipääs, `sudo` ja uuendused. See peatükk on Labor 1 teooria.

### 2.1 Mõisted

| Termin | Selgitus | Näide laboris |
| --- | --- | --- |
| Hostinimi | Masina lühinimi. | `debian1` |
| FQDN (*Fully Qualified Domain Name*) | Täisnimi koos domeeniga, lõpeb DNS-is punktiga. | `debian1.perenimi.local.` |
| Staatiline IP | Käsitsi määratud aadress, mis ei muutu. Serveritel alati staatiline. | `10.0.XXX.10/24` |
| Lüüs (*gateway*) | Ruuter, kuhu saadetakse kõik väljaspoole oma võrku minevad paketid. | `10.0.XXX.1` |
| Nimeserver (*resolver*) | Server, kellelt masin küsib nimede IP-aadresse. | `10.0.XXX.20` |
| Otsingudomeen (*search*) | Lisatakse lühinimele automaatselt: `ping mail` → `mail.perenimi.local`. | `perenimi.local` |
| systemd / `systemctl` | Teenuste haldur: käivitab, peatab, lubab automaatkäivituse. | `systemctl status apache2` |
| journald / `journalctl` | Süsteemi logi. | `journalctl -u named -f` |
| Pakihaldur `apt` | Paigaldab ja uuendab tarkvara. | `apt install bind9` |
| `sudo` | Käivitab ühe käsu administraatori (root) õigustes. | `sudo nano /etc/hosts` |
| SSH | Krüpteeritud kaughaldus (port 22). | `ssh opilane@10.0.XXX.10` |
| Tulemüür `ufw` | Lihtne liides Linuxi paketifiltrile (nftables/iptables). | `ufw allow 80/tcp` |

### 2.2 sudo õigus (Debian)

Kui Debiani paigaldusel anti **root-kasutajale parool**, siis `sudo` paketti ei paigaldata ja tavakasutaja ei saa administraatori käske käivitada. Lahendus (tee mõlemas Debianis):

**Debian1 ja Debian2:**

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

**Debian1** (Debian2 puhul aadress `.20`):

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
    address 10.0.XXX.10/24
    gateway 10.0.XXX.1
```

Nimeserver kirjuta otse faili `/etc/resolv.conf`:

```bash
sudo nano /etc/resolv.conf
```

```text
# Debian1 ja Ubuntu: nimeserver on Debian2
nameserver 10.0.XXX.20
search perenimi.local
```

Debian2 on ise nimeserver – **Debian2** failis on `nameserver 127.0.0.1`. Kuni BIND9 pole veel paigaldatud (peatükk 3), kasuta ajutiselt kooli/õpetaja DNS-i või `1.1.1.1`, muidu `apt` ei leia pakihoidlat.

Rakenda ja kontrolli:

```bash
sudo systemctl restart networking
ip -br addr show ens18
ip route                     # default via 10.0.XXX.1
ping -c 2 10.0.XXX.1
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
        - 10.0.XXX.30/24
      routes:
        - to: default
          via: 10.0.XXX.1
      nameservers:
        addresses: [10.0.XXX.20]
        search: [perenimi.local]
```

```bash
sudo chmod 600 /etc/netplan/*.yaml   # netplan hoiatab, kui fail on teistele loetav
sudo netplan try                     # rakendab 120 s; kinnita Enteriga
resolvectl status ens18              # DNS Servers: 10.0.XXX.20, DNS Domain: perenimi.local
```

> **Oluline – `.local` ja systemd-resolved.** Ubuntu nimelahendaja `systemd-resolved` käsitleb `.local` lõpuga nimesid vaikimisi **mDNS-i** (Bonjour/Avahi) nimedena. Rida `search: [perenimi.local]` teeb `perenimi.local` selle liidese **marsruutimisdomeeniks** ja siis lähevad `*.perenimi.local` päringud BIND9-le. Kontroll: `resolvectl query mail.perenimi.local`. Kui vastus on „No appropriate name servers…“, lisa käsitsi: `sudo resolvectl domain ens18 perenimi.local '~local'`.

Kui Ubuntu VM on loodud *cloud-init* tõmmisest, võib cloud-init võrguseadistuse taaskäivitusel üle kirjutada. Keela see: `echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`.

### 2.6 Hostinimi ja /etc/hosts

**Debian1:**

```bash
sudo hostnamectl set-hostname debian1
sudo nano /etc/hosts
```

```text
127.0.0.1       localhost
10.0.XXX.10     debian1.perenimi.local debian1
```

Samamoodi **Debian2** (`debian2`, `.20`) ja **Ubuntu** – meiliserveri hostinimi on `mail`:

```bash
sudo hostnamectl set-hostname mail
```

```text
127.0.0.1       localhost
10.0.XXX.30     mail.perenimi.local mail
```

Kontroll: `hostname` → lühinimi, `hostname -f` → FQDN. Debianis on failis vaikimisi rida `127.0.1.1 vana-nimi` – kustuta see, muidu `hostname -f` annab vale nime.

> **Miks see oluline on?** Postfix kasutab FQDN-i oma tervitusreal (`220 mail.perenimi.local ESMTP`) ja HELO-s. Vale FQDN = teised serverid lükkavad kirjad tagasi.

### 2.7 Uuendused ja põhitööriistad

**Kõik kolm Linuxi masinat:**

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt install -y curl wget nano unzip ca-certificates bind9-dnsutils net-tools ufw
```

`bind9-dnsutils` annab käsud `dig`, `nslookup`, `host`; `net-tools` vana `netstat`-i (uus vaste on `ss`).

### 2.8 SSH

Debian paigaldab OpenSSH serveri, kui paigaldusel valiti „SSH server“. Kontrolli ja vajadusel paigalda:

```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```

Windowsi kliendis on OpenSSH klient olemas (PowerShell või cmd):

```powershell
ssh opilane@10.0.XXX.10
```

Linuxist teise Linuxi failide kopeerimiseks kasutame `scp`-d (vaja peatükis 7):

```bash
scp fail.txt opilane@10.0.XXX.30:/home/opilane/
```

Turvalisuse jaoks soovitatav (valikuline laboris): võtmepõhine sisselogimine (`ssh-keygen`, `ssh-copy-id`) ja failis `/etc/ssh/sshd_config` `PermitRootLogin no`.

### 2.9 Teenused ja logid

| Tegevus | Käsk |
| --- | --- |
| Teenuse olek | `systemctl status apache2` |
| Käivita / peata / taaskäivita | `sudo systemctl start\|stop\|restart apache2` |
| Laadi seadistus uuesti ilma ühendusi katkestamata | `sudo systemctl reload apache2` |
| Automaatkäivitus sisse ja kohe käima | `sudo systemctl enable --now apache2` |
| Teenuse logi | `sudo journalctl -u apache2 -n 50` |
| Logi reaalajas | `sudo journalctl -u postfix -f` |
| Millised pordid kuulavad | `sudo ss -tlnp` (t = TCP, l = kuulavad, n = numbrid, p = protsess) |

**Debian 13 ei kirjuta vaikimisi faile `/var/log/syslog` ja `/var/log/mail.log`** – logid on ainult journalis (`journalctl`). Ubuntu 24.04-l on rsyslog olemas ja meiliserveri logi on failis `/var/log/mail.log` – seda kasutab ka fail2ban (peatükk 10).

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
| Debian1 | 22, 80, 443 |
| Debian2 | 22, 53/tcp+udp (ainult labori võrgust), 3306 (ainult Debian1-st) |
| Ubuntu | 22, 25, 80, 443, 465, 587, 993 |

### 2.11 Windowsi kliendi DNS

Windowsi klient peab kasutama nimeserverina **Debian2-te**, muidu ei leia ta nimesid `*.perenimi.local`.

**Variant A – GUI:** *Settings → Network & internet → Ethernet → DNS server assignment → Edit → Manual → IPv4 On* → *Preferred DNS* `10.0.XXX.20` → *Save*.

**Variant B – PowerShell (administraatorina):**

```powershell
Get-NetAdapter                                     # vaata liidese nime, nt "Ethernet"
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 10.0.XXX.20
Set-DnsClient -InterfaceAlias "Ethernet" -ConnectionSpecificSuffix "perenimi.local"
Clear-DnsClientCache
```

Piisab ühest variandist. Sama tee ka Windows Serveris.

> Kui Windows Server on samal ajal **Active Directory domeenikontroller** domeeniga `perenimi.local` (Windowsi serveri halduse kursusest), siis on samas võrgus kaks nimeserverit, mis mõlemad väidavad end olevat `perenimi.local` omanik. Selles kursuses on `perenimi.local` omanik **BIND9**. Kasuta Windows Serverit siin lihtsalt teise kliendina või kasuta AD-le teist nime.
