**Bind9 nimeserveri seadistamiseks domeenile `minudomeen.local` Debian 13 serveris tuleb paigaldada Bind9, luua tsoonifailid ja konfigureerida vastavad seaded. Allpool on samm-sammuline juhend.**

---

## 🧱 1. Paigalda Bind9

```bash
sudo apt update
sudo apt install bind9 bind9utils bind9-doc
```

Kontrolli, et teenus töötab:

```bash
sudo systemctl status bind9
```

---

## 🌐 2. Konfigureeri DNS serveri üldseaded

Muuda fail:  
```bash
sudo nano /etc/bind/named.conf.options
```

Lisa või muuda `options` plokki:

```conf
options {
    directory "/var/cache/bind";

    listen-on { any; };
    allow-query { any; };

    forwarders {
        1.1.1.1;
    };

    dnssec-validation auto;
    auth-nxdomain no;
    listen-on-v6 { any; };
};
```

---

## 📁 3. Lisa tsoon domeenile `minudomeen.local`

Muuda fail:  
```bash
sudo nano /etc/bind/named.conf.local
```

Lisa:

```conf
zone "minudomeen.local" {
    type master;
    file "/etc/bind/zones/db.minudomeen.local";
};
```

Loo tsoonifailide kaust:

```bash
sudo mkdir -p /etc/bind/zones
```

---

## 📝 4. Loo tsoonifail domeenile

```bash
sudo nano /etc/bind/zones/db.minudomeen.local
```

Näidis:

```dns
$TTL    604800
@       IN      SOA     ns1.minudomeen.local. admin.minudomeen.local. (
                        2025101001 ; Serial
                        604800     ; Refresh
                        86400      ; Retry
                        2419200    ; Expire
                        604800 )   ; Negative Cache TTL
;
@       IN      NS      ns1.minudomeen.local.
ns1     IN      A       10.0.200.100
www     IN      A       10.0.200.100
```

---

## 🔍 5. Kontrolli konfiguratsiooni

```bash
sudo named-checkconf
sudo named-checkzone minudomeen.local /etc/bind/zones/db.minudomeen.local
```

---

## 🔄 6. Taaskäivita Bind9

```bash
sudo systemctl restart bind9
```

---

## 🧪 7. Testi domeeni lahendamist

Lisa oma kliendi / serveri `/etc/resolv.conf` faili:

```
nameserver 10.0.200.100
```

Testi:

```bash
dig @10.0.200.100 minudomeen.local
dig @10.0.200.100 www.minudomeen.local
```

---

## ✅ Kokkuvõte

- Bind9 töötab IP-aadressil **10.0.200.100**
- Domeen **minudomeen.local** lahendatakse kohalikult
- Nimeserveri nimi: **ns1.minudomeen.local**
- DNS-päringud suunatakse edasi **1.1.1.1** kui kohalikku kirjet pole

Kui soovid ka *reverse zone* või *slave serveri* seadistust, võin selle lisada. Kas soovid ka tagurpidi IP lahendust (`PTR` kirje)?
