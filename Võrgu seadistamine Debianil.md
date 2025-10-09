Debian 13 kasutab **systemd-networkd** või **NetworkManager** olenevalt installist. Serverikeskkonnas on tavaliselt **systemd-networkd** vaikimisi. Siin on samm-sammuline juhend, kuidas seadistada staatiline IP-aadress, gateway ja DNS Debian 13 serveris kasutades **systemd-networkd**.

---

## 🛠️ 1. Kontrolli, et systemd-networkd on aktiivne

```bash
systemctl status systemd-networkd
```

Kui see pole aktiivne:

```bash
sudo systemctl enable systemd-networkd --now
sudo systemctl enable systemd-resolved --now
```

Loo sümboolne link resolv.conf'ile:

```bash
sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```

---

## 🌐 2. Leia oma võrguliidese nimi

```bash
ip link
```

Näiteks võib nimi olla `enp0s3`, `eth0`, `ens33` jne. Oletame, et see on `enp0s3`.

---

## 📄 3. Loo võrgukonfiguratsiooni fail

```bash
sudo nano /etc/systemd/network/10-static.network
```

Sisesta:

```ini
[Match]
Name=enp0s3

[Network]
Address=10.0.200.100/24
Gateway=10.0.200.1
DNS=1.1.1.1
```

Salvesta ja sulge.

---

## 🔄 4. Taaskäivita võrguteenused

```bash
sudo systemctl restart systemd-networkd
sudo systemctl restart systemd-resolved
```

---

## ✅ 5. Kontrolli seadistust

```bash
ip a
ip r
cat /etc/resolv.conf
```

---

## 🧪 Alternatiiv: Kui kasutad NetworkManager'it

```bash
nmcli con show
nmcli con mod "Wired connection 1" ipv4.addresses 10.0.200.100/24
nmcli con mod "Wired connection 1" ipv4.gateway 10.0.200.1
nmcli con mod "Wired connection 1" ipv4.dns 1.1.1.1
nmcli con mod "Wired connection 1" ipv4.method manual
nmcli con up "Wired connection 1"
```

---

Kui soovid, võin pakkuda ka Bash-skripti, mis teeb selle automaatselt. Kas soovid skriptiversiooni?
