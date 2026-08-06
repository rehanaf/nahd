# I'd Animate — Daftar Fitur & Tool

Aplikasi editor animasi 2D (vector) berbasis Flutter. Terdiri dari dua area utama:
**Menu Utama** (manajemen proyek) dan **Editor** (mode Figure + mode Animation).

---

## 1. Menu Utama

### Manajemen Proyek
- **Dua jenis proyek**: *Animation* (animasi) dan *Figure* (gambar statis).
- **Buat proyek** baru (tap tombol `+`) — otomatis langsung dibuka di editor.
- **Buka proyek** dari grid kartu dengan preview gambar (thumbnail live).
- **Rename / Copy / Delete** proyek via menu kartu (`⋮`).
- **Import** proyek dari file `.zip` (format id-animate-nodes).
- **Export** proyek ke file `.zip`.
- Auto-save ke penyimpanan lokal (SharedPreferences) dengan debounce.

### Group Proyek (Folder)
- **Buat / rename / delete group** untuk mengelompokkan proyek.
- **Predefined groups** (dari scene bawaan) + **user groups**.
- Lihat isi group (grid proyek) dan pindah proyek ke dalam group saat dibuat.

### Pengaturan & Profil
- **Profil**: edit nama profil (inisial muncul di avatar).
- **Tema**: Light / Dark / Device.
- **Clear All Data**: reset semua proyek & pengaturan, lalu re-import scene bawaan.
- **Sorting** kartu: berdasarkan Type, Name, atau Last Modified.
- **Scene preset**: proyek contoh yang di-import otomatis (PredefinedProjects).

---

## 2. Editor — Mode Figure

### Tools (Sidebar Kiri)
| Tool | Ikon | Fungsi |
|---|---|---|
| **Select** | `near_me` | Memilih segmen/titik |
| **Point** | `open_with` | Menggerakkan titik (drag) |
| **Modify** | `center_focus_strong` | Memodifikasi bentuk/struktur |
| **Curve** | `timeline` | Kurva / membengkokkan segmen |
| **Rotate** | `rotate_right` | Memutar titik/segmen |
| **Stretch** | `compress` | Meregangkan / memanjangkan |
| **Rotate All** | `rotate_left` | Memutar seluruh figure |
| **Asset** | `crop_rotate` | Mengelola asset gambar |
| **Anchor** | `anchor` | Titik bergerak, gambar diam (inverse) |
| **Line** | `edit` | Membuat segmen garis baru |
| **Circle** | `panorama_fish_eye` | Membuat segmen lingkaran |
| **Join / Unjoin** | `join_inner` | Gabung titik (drag ke titik lain) / pisah titik bersama |

### Segmen
- **4 tipe segmen**: `line`, `circle`, `image`, `none` (link tak terlihat).
- **Join** (auto): drag titik bebas ke titik lain → menyatu; root figure yang
  di-drag hilang (hanya root target yang tersisa).
- **Unjoin**: drag titik bersama menjauh → titik copy baru jadi root sendiri.
- **Delete segmen**: tengah gambar terbelah, masing-masing bagian otomatis
  dapat root (via `repairRoots`).
- **Root per figure**: tiap komponen terhubung punya minimal satu root;
  bisa lebih dari satu per figure (sub-figure).

### Inspector Segment (Panel Kanan)
- **Header**: nama tipe segmen, toggle visible, delete segmen.
- **Segment Type**: pilih line / circle / image / none.
- **Transform**: Panjang (length), Sudut (angle).
- **Appearance**: warna, line width (default **16px**), line cap (round /
  square / butt), curved + curvature, filled + fill color (circle).
- **Image** (type image): pilih gambar, remove, width/height (auto / angka),
  offset X/Y, rotate.
- **Layer**: pilih **group** tujuan + Z-index (layer).
- **Cycle Fill**: per segmen yang berbagi titik (cycle), lengkap dengan
  reorder layer dan toggle fill + warna.
- **Points**: koordinat Point 1 & Point 2.

### Layer Groups (Panel Layers)
- Daftar **group/folder layer** yang menampung segmen.
- **Drag** segmen untuk reorder dalam group atau pindah antar group.
- **Drag** header group untuk reorder urutan group (default group ikut bisa
  dipindah, tapi tidak bisa dihapus).
- Toggle **visible** & **lock** per group, per segmen (eye icon).
- **Rename** (double-tap / icon edit) & **delete** group non-default.
- Tambah group baru (`+`).
- **View-only** di mode Animation (tidak bisa diedit/direorder).
- Icon segmen berwarna sesuai warna segmen, dan berbeda per tipe
  (line / circle / image / none).

### Undo / Redo
- History 50 langkah (undo/redo) untuk semua operasi edit.
- Juga berlaku untuk operasi group & layer.

---

## 3. Editor — Mode Animation

### Keyframe & Timeline
- **Play / Pause**, **prev / next frame**, counter `frame / totalFrames`.
- **FPS** dapat diatur (1–60), memengaruhi durasi & total frame.
- **Perekaman pose**: gerakkan titik pada waktu tertentu → keyframe dibuat
  (`recordPose` / `recordPosesForIndices`).
- **Point mode static/dynamic**: kunci titik agar tidak ikut beranimasi
  (icon lock).
- **Auto easing**: interpolasi otomatis antar keyframe (toggle).

### Frames Screen (Grid Frame)
- **Copy Frame / Paste Frame** (pose seluruh titik sebagai keyframe baru).
- **Delete Frame** (hapus keyframe di waktu tertentu).
- **Thumbnail** tiap frame (pose diinterpolasi).

### Onion Skin
- **Prev Onion** dan **Next Onion** (ghost frame sebelumnya/sesudahnya).

### Visibility
- **Visibility per figure/root**: set visible/invisible pada waktu tertentu
  (keyframe visibility per sub-figure).

### Settings (Panel)
- **FPS**, **Canvas Width/Height**, **Onion Skin**, **Auto Easing**.
- Reset figure (`delete`) — di mode animation titik kosong.

---

## 4. Import / Ekspor

### Import SVG
- **Import SVG** (vektor): tiap `<g>`/layer menjadi satu sub-figure/root;
  outline disampling jadi segmen `line`, warna fill/stroke disalin.
- **Import SVG as Image**: tiap layer di-render jadi PNG → satu segmen
  `image` per layer (rigid asset).
- Mendukung transform (translate/scale/rotate/matrix/skew), gradient
  (diambil warna stop pertama), warna named & rgb().
- **Group layer otomatis dibuat** dari hasil import (`ensureSegmentsInDefaultGroup`),
  termasuk saat "Add Figure" dari proyek lain (`_mergeGroupsFrom`).

### Add Figure (dari proyek lain)
- Mengimpor figure dari proyek lain ke canvas aktif.
- **Semua root** dari sumber didaftarkan (bukan hanya satu), lengkap dengan
  visibility di mode animation, dan group layer ikut disalin.

### Export/Import Proyek
- **Export .zip** dan **Import .zip** proyek (kompatibel JSON
  id-animate-nodes: `animation.json` + manifest).

---

## 5. Arsitektur Inti (untuk referensi)

- `Figure`: points, segments, groups (layer), rootIndices, visibility,
  cycleFills, animations.
- `Segment`: id unik (`seg_...`), type, point1/2Index, warna, layer, curved,
  filled, image.
- `LayerGroup`: id (`layer_...`), name, segmentIds, visible, locked; ada
  **default group** (`layer_default`, "Default") yang selalu ada.
- `FigureAnimation`: tracks (per point) berisi keyframes; applyToFigure.
- `EditorController`: state pusat (tool, seleksi, history, playback, animasi).
- `repairRoots()`: menjamin tiap komponen terhubung punya minimal satu root.

### Format Data
- Figure & animation disimpan sebagai JSON string (toJson/fromJson),
  backward-compatible: JSON lama tanpa `groups` otomatis diberi default group.
- Proyek disimpan via `ProjectStorage` (SharedPreferences) + export .zip.
