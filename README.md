<div align="center">

# 🌱 Dylano — GrowBlox Suite

## ✨ Fitur

| Fitur | Deskripsi |
|-------|-----------|
| 🧺 **Auto Collect** | Sapu item yang jatuh di sekitar, lengkap dengan pathfinding otomatis |
| ⛏️ **Auto Break** | Hold-to-break block dalam radius yang bisa diatur |
| 🟫 **Auto Dirtfarm** | Cari block dirt, jalan ke sana, break, lalu collect drop-nya (port dari script Growtopia) |
| 👊 **Long Punch** | Pukulan dengan jangkauan lebih jauh |
| 🔍 **GrowScan** | Scanner item di sekitar, hasilnya muncul di console |
| 💤 **Anti-AFK** | Cegah kick karena idle |
| ⚡ **WorkSpeed** | Satu slider untuk mempercepat semua aksi (0.5× – 10×) |

Semua fitur bisa dinyalakan lewat menu in-game. Menunya bisa di-drag dan di-minimize.

---

## 🚀 Cara Pakai

1. Buka Roblox, masuk ke game **GrowBlox**.
2. Buka executor kamu dan **attach** ke game.
3. Jalankan loader ini:

```lua
local url = "https://raw.githubusercontent.com/ThisLanoo/growblox/main/GrowBlox_v2_3_Dylano.lua"
local src = game:HttpGet(url)
print("[Dylano] ukuran script:", #src)
local f, err = loadstring(src)
if not f then
    warn("[Dylano] syntax error: " .. tostring(err))
else
    f()
end
```

4. Menu hijau **Dylano GrowBlox** akan muncul di sisi kiri layar. Tinggal geser toggle sesuai kebutuhan.

> 💡 Tekan **F9** untuk membuka console dan melihat log `[Dylano]`.

---

## ⚙️ Konfigurasi

Semua pengaturan ada di tabel `CFG` di bagian paling atas script.

| Pengaturan | Fungsi |
|------------|--------|
| `Break.BreakRemote` | Nama RemoteEvent untuk break block |
| `Punch.Remote` | Nama RemoteEvent untuk punch |
| `Dirtfarm.DirtTag` | Tag block dirt di GrowBlox |
| `Dirtfarm.DirtPatterns` | Pola nama block yang dianggap dirt |
| `Dirtfarm.ScanRadius` | Radius scan dirt dari posisi karakter |
| `Dirtfarm.BorderSkip` | Jumlah tile di tepi world yang dilewati |
| `WorkSpeed.Multiplier` | Pengali kecepatan semua aksi |

Kalau salah satu fitur tidak bereaksi, kemungkinan besar nama remote atau tag block di game berbeda dari default. Sesuaikan nilainya di `CFG`.

---

## 🧩 Menu In-Game

```
┌────────────────────────────┐
│ ▌Dylano  GrowBlox   v2.3 — │
├────────────────────────────┤
│ AUTO FARM                  │
│  ▸ Auto Collect       [ ]  │
│  ▸ Auto Break         [ ]  │
│  ▸ Auto Clear World   [ ]  │
│ DIRTFARM                   │
│  ▸ Auto Dirtfarm      [ ]  │
│  ▸ Auto Collect Dirt  [x]  │
│  ▸ Scan radius dirt  ───●  │
│ COMBAT / UTILITY / SPEED   │
└────────────────────────────┘
```

---

## 🛠️ Troubleshooting

| Masalah | Solusi |
|---------|--------|
| UI tidak muncul | Cek console (F9), lihat apakah ada pesan error `[Dylano]` |
| Fitur nyala tapi tidak ada efek | Cocokkan nama remote dan tag block di `CFG` dengan yang dipakai game |
| Script lama masih jalan | GitHub raw punya cache, tunggu beberapa menit lalu jalankan ulang |
| Slider tidak bisa digeser di HP | Slider dan drag window dibuat untuk input mouse |

---

## 📜 Changelog

**v2.3**
- ➕ Auto Dirtfarm (port dari script Growtopia oleh PowerKuy/Deexzy)
- 🎨 Rebrand UI menjadi **Dylano**
- 🔧 Menggabungkan semua fix dari v2.2

---

## ⚠️ Disclaimer

Script ini dibuat untuk tujuan belajar dan eksperimen. Penggunaan script eksekusi pihak ketiga melanggar Terms of Service Roblox dan bisa membuat akun kena ban. Pakai dengan risiko sendiri, dan sebaiknya gunakan akun alt.

---

<div align="center">

Dibuat dengan 💚 oleh **ThisLanoo**

</div>
