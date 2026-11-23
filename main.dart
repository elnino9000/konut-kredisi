import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const KrediApp());

const kArka = Color(0xFF0A0E1F);
const kYuzey = Color(0xFF151A33);
const kYuzey2 = Color(0xFF1E2550);
const kKenar = Color(0xFF2A3160);
const kYesil = Color(0xFF2EE6A6);
const kMavi = Color(0xFF3D8BFF);
const kKehribar = Color(0xFFFFB84D);
const kKirmizi = Color(0xFFFF5C6C);
const kSoluk = Color(0xFF8E96C7);
const kGradyan = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF0FA97A), Color(0xFF3D6BFF)],
);
const kGradyanKotu = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFE0455A), Color(0xFF8E2DE2)],
);
const kVadeler = [12, 24, 36, 48, 60, 72, 84, 96, 108, 120];
const kEvdsAdres = 'https://evds3.tcmb.gov.tr/igmevdsms-dis/';
const kTahsisOrani = 0.005; // kredi tahsis ücreti üst sınırı: binde 5
const kKdv = 0.20;

ThemeData _tema() {
  final cs = ColorScheme.fromSeed(seedColor: kMavi, brightness: Brightness.dark);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: kArka,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white),
    ),
    cardTheme: CardThemeData(
      color: kYuzey,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: const BorderSide(color: kKenar),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kYuzey2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: kMavi, width: 1.5),
      ),
      labelStyle: const TextStyle(color: kSoluk),
      helperStyle: const TextStyle(color: kSoluk),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: kYuzey,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kYuzey2,
      selectedColor: kMavi.withOpacity(0.35),
      side: const BorderSide(color: kKenar),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? kMavi.withOpacity(0.35) : kYuzey2),
        side: const WidgetStatePropertyAll(BorderSide(color: kKenar)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((st) =>
          st.contains(WidgetState.selected) ? kYesil : kKenar),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: const DividerThemeData(color: kKenar),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: kMavi,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: kYuzey2,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

class KrediApp extends StatelessWidget {
  const KrediApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Konut Kredi Hesaplama',
      debugShowCheckedModeBanner: false,
      theme: _tema(),
      darkTheme: _tema(),
      themeMode: ThemeMode.dark,
      home: const AnaSayfa(),
    );
  }
}

// ---------- Yardımcı hesaplar ----------

String tlSade(double v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

String tl(double v) => '${tlSade(v)} TL';

String yuzde(double v, [int basamak = 2]) =>
    '%${v.toStringAsFixed(basamak).replaceAll('.', ',')}';

String oranYaz(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

double paraOku(String s) {
  // "2600000.50" gibi tek noktalı ve noktadan sonra 1-2 hane varsa ondalık say.
  final m = RegExp(r'^\s*\d+\.(\d{1,2})\s*$').firstMatch(s);
  if (m != null) return double.tryParse(s.trim()) ?? 0;
  final t = s
      .replaceAll('.', '')
      .replaceAll(' ', '')
      .replaceAll('TL', '')
      .replaceAll(',', '.');
  return double.tryParse(t) ?? 0;
}

double oranOku(String s) =>
    double.tryParse(s.replaceAll(',', '.').replaceAll('%', '').trim()) ?? 0;

double taksitHesapla(double anapara, double aylikOran, int ay) {
  if (anapara <= 0 || ay <= 0) return 0;
  if (aylikOran == 0) return anapara / ay;
  return anapara * aylikOran / (1 - pow(1 + aylikOran, -ay));
}

/// Eline geçen net para ile taksitlerin eşitlendiği aylık oran (masraflar dahil gerçek maliyet).
double aylikGercekMaliyet(double netAlinan, double taksit, int ay) {
  if (netAlinan <= 0 || taksit <= 0) return 0;
  double alt = 0;
  double ust = 1;
  for (int j = 0; j < 100; j++) {
    final orta = (alt + ust) / 2;
    final bugun = taksit * (1 - pow(1 + orta, -ay)) / orta;
    if (bugun > netAlinan) {
      alt = orta;
    } else {
      ust = orta;
    }
  }
  return (alt + ust) / 2;
}

double yillikBilesik(double aylik) => pow(1 + aylik, 12).toDouble() - 1;

/// BDDK 29.01.2026 kararı: konut değeri ve enerji sınıfına göre
/// azami kredi / değer oranı. sinif: 0 = A-B, 1 = C, 2 = D ve altı.
///
/// evVar: başvuran, eşi veya 18 yaş altı çocuğu adına en az bir konut varsa
/// oran %75 daraltılır (BDDK 24.08.2023, 10656 sayılı karar): 0,25 ile çarpılır.
double maxKrediOrani(double deger, int sinif, [bool evVar = false]) {
  const bantlar = [
    [5000000.0, 0.9, 0.8, 0.7],
    [7000000.0, 0.8, 0.7, 0.6],
    [10000000.0, 0.7, 0.6, 0.5],
    [20000000.0, 0.5, 0.4, 0.3],
  ];
  for (final b in bantlar) {
    if (deger <= b[0]) return b[1 + sinif] * (evVar ? 0.25 : 1.0);
  }
  return const [0.4, 0.3, 0.2][sinif] * (evVar ? 0.25 : 1.0);
}

/// Eldeki parayla (peşinat + tüm masraflar) alınabilecek en pahalı ev.
double enYuksekFiyat(double para, int sinif, double sabitMasraf,
    double tapuOrani, double emlakOrani, bool evVar) {
  const sinirlar = [5000000.0, 7000000.0, 10000000.0, 20000000.0, double.infinity];
  double sonuc = 0;
  double alt = 0;
  for (final ust in sinirlar) {
    final o = maxKrediOrani(alt + 1, sinif, evVar);
    final f = (para - sabitMasraf) /
        ((1 - o) + tapuOrani + emlakOrani + kTahsisOrani * o);
    if (f <= alt) break;
    if (f <= ust) {
      sonuc = f;
      break;
    }
    sonuc = ust;
    alt = ust;
  }
  return max(0.0, sonuc);
}

class Teklif {
  Teklif(this.ad, this.oran);
  final String ad;
  final double oran;
}

// ---------- Merkez Bankası (EVDS) ----------

class EvdsSonuc {
  EvdsSonuc(this.deger, this.tarih);
  final double deger;
  final String tarih;
}

String _evdsTarih(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

Future<EvdsSonuc?> evdsSonDeger(
    String adres, String key, String seri, int gun, int? formul) async {
  final bit = DateTime.now();
  final bas = bit.subtract(Duration(days: gun));
  var url =
      '${adres}series=$seri&startDate=${_evdsTarih(bas)}&endDate=${_evdsTarih(bit)}&type=json';
  if (formul != null) url += '&formulas=$formul';
  final yanit = await http
      .get(Uri.parse(url), headers: {'key': key})
      .timeout(const Duration(seconds: 20));
  if (yanit.statusCode != 200) {
    throw Exception('sunucu ${yanit.statusCode} kodu döndü ($seri)');
  }
  final veri = jsonDecode(utf8.decode(yanit.bodyBytes));
  final items = (veri is Map) ? veri['items'] : null;
  if (items is! List) throw Exception('beklenmeyen yanıt ($seri)');
  final alanBasi = seri.replaceAll('.', '_');
  for (final item in items.reversed) {
    if (item is! Map) continue;
    for (final e in item.entries) {
      final k = e.key.toString();
      if (!k.startsWith(alanBasi)) continue;
      final v = double.tryParse(e.value?.toString().replaceAll(',', '.') ?? '');
      if (v != null) return EvdsSonuc(v, item['Tarih']?.toString() ?? '');
    }
  }
  return null;
}

// ---------- Ana sayfa ----------

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  final Map<String, TextEditingController> c = {
    'para': TextEditingController(text: '400.000'),
    'fiyat': TextEditingController(text: '2.600.000'),
    'faiz': TextEditingController(text: '2,90'),
    'enflasyon': TextEditingController(text: '29,77'),
    'ekspertiz': TextEditingController(text: '31.500'),
    'doner': TextEditingController(text: '2.534'),
    'banka': TextEditingController(text: '8.350'),
    'sigorta': TextEditingController(text: '0'),
    'kira': TextEditingController(text: '21.000'),
    'kiraArtis': TextEditingController(text: '29,77'),
  };
  int sinif = 0;
  bool evVar = true;
  bool tapuTamami = true;
  bool emlakci = true;
  bool emlakTamami = false;
  double senaryo = 0;
  int kiraVade = 36;
  String faizKaynagi = 'Varsayılan örnek değer. Güncel veri için aşağıdan Merkez Bankası’ndan çekin';
  String enfNotu = 'Varsayılan örnek değer. Güncel veri için aşağıdan Merkez Bankası’ndan çekin';
  List<Teklif> teklifler = [
    Teklif('Kuveyt Türk', 2.87),
    Teklif('Vakıf Katılım', 2.94),
  ];
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final p = await SharedPreferences.getInstance();
    prefs = p;
    for (final e in c.entries) {
      final v = p.getString('girdi_${e.key}');
      if (v != null) e.value.text = v;
    }
    final kayitli = p.getStringList('teklifler');
    if (!mounted) return;
    setState(() {
      sinif = p.getInt('sinif') ?? 0;
      evVar = p.getBool('evVar') ?? true;
      tapuTamami = p.getBool('tapuTamami') ?? true;
      emlakci = p.getBool('emlakci') ?? true;
      emlakTamami = p.getBool('emlakTamami') ?? false;
      faizKaynagi = p.getString('faizKaynagi') ?? faizKaynagi;
      enfNotu = p.getString('enfNotu') ?? enfNotu;
      if (kayitli != null) {
        teklifler = [
          for (final s in kayitli)
            if (s.contains('|'))
              Teklif(s.split('|').first, double.tryParse(s.split('|').last) ?? 0),
        ];
      }
    });
  }

  void _kaydet() {
    final p = prefs;
    if (p == null) return;
    for (final e in c.entries) {
      p.setString('girdi_${e.key}', e.value.text);
    }
    p.setInt('sinif', sinif);
    p.setBool('evVar', evVar);
    p.setBool('tapuTamami', tapuTamami);
    p.setBool('emlakci', emlakci);
    p.setBool('emlakTamami', emlakTamami);
    p.setString('faizKaynagi', faizKaynagi);
    p.setString('enfNotu', enfNotu);
    p.setStringList(
        'teklifler', [for (final t in teklifler) '${t.ad}|${t.oran}']);
  }

  void _degisti() {
    setState(() {});
    _kaydet();
    _yenile.value++;
  }

  // ----- Temel değerler -----

  double get para => paraOku(c['para']!.text);
  double get fiyat => paraOku(c['fiyat']!.text);
  double get aylikFaiz => (oranOku(c['faiz']!.text) + senaryo) / 100;
  double get yillikEnf => oranOku(c['enflasyon']!.text);
  double get aylikEnf => pow(1 + yillikEnf / 100, 1 / 12).toDouble() - 1;

  double get tapuOrani => tapuTamami ? 0.04 : 0.02;
  double get emlakOrani =>
      emlakci ? (emlakTamami ? 0.04 : 0.02) * (1 + kKdv) : 0.0;
  double get tapu => fiyat * tapuOrani;
  double get emlak => fiyat * emlakOrani;
  double get ekspertiz => paraOku(c['ekspertiz']!.text);
  double get doner => paraOku(c['doner']!.text);
  double get banka => paraOku(c['banka']!.text);
  double get sigorta => paraOku(c['sigorta']!.text);
  double get kira => paraOku(c['kira']!.text);
  double get kiraArtis => oranOku(c['kiraArtis']!.text) / 100;

  /// m. ayda alınan kira: her 12 ayda bir artış oranı kadar artar.
  double kiraAy(int m) => kira * pow(1 + kiraArtis, (m - 1) ~/ 12);

  /// Ev fiyatına bağlı olmayan sabit masraflar.
  double get sabitMasraf => doner + ekspertiz + banka + sigorta;

  /// Eldeki para önce masraflara gider, kalanı peşinat olur, eksik kısım kredidir.
  double get kredi {
    final k = (fiyat - (para - tapu - emlak - sabitMasraf)) / (1 - kTahsisOrani);
    return max(0.0, min(k, fiyat));
  }

  double get tahsis => kredi * kTahsisOrani;
  double get toplamMasraf => tapu + emlak + sabitMasraf + tahsis;
  double get pesinat => para - toplamMasraf;

  /// Krediye bağlı (banka tarafı) masraflar: gerçek maliyet hesabına girer.
  double get krediMasrafi => tahsis + ekspertiz + banka + sigorta;

  // ----- Merkez Bankası verisi -----

  Future<void> _ayarlar() async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final anahtar = TextEditingController(text: p.getString('evdsKey') ?? '');
    final adres =
        TextEditingController(text: p.getString('evdsAdres') ?? kEvdsAdres);
    final faizSeri =
        TextEditingController(text: p.getString('faizSeri') ?? 'TP.KTF12');
    final enfSeri =
        TextEditingController(text: p.getString('enfSeri') ?? 'TP.FG.J0');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merkez Bankası bağlantısı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'evds3.tcmb.gov.tr adresinde ücretsiz hesap açın. Profilim sayfasındaki API anahtarını kopyalayıp aşağıya yapıştırın.'),
              const SizedBox(height: 8),
              TextField(
                controller: anahtar,
                decoration: const InputDecoration(labelText: 'API anahtarı'),
              ),
              TextField(
                controller: adres,
                decoration: const InputDecoration(labelText: 'Servis adresi'),
              ),
              TextField(
                controller: faizSeri,
                decoration: const InputDecoration(
                    labelText: 'Konut kredisi faizi seri kodu'),
              ),
              TextField(
                controller: enfSeri,
                decoration:
                    const InputDecoration(labelText: 'TÜFE seri kodu'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              p.setString('evdsKey', anahtar.text.trim());
              p.setString('evdsAdres', adres.text.trim());
              p.setString('faizSeri', faizSeri.text.trim());
              p.setString('enfSeri', enfSeri.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _veriCek() async {
    final messenger = ScaffoldMessenger.of(context);
    final p = prefs ?? await SharedPreferences.getInstance();
    final key = p.getString('evdsKey') ?? '';
    if (key.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Önce Merkez Bankası API anahtarınızı girin.')));
      await _ayarlar();
      return;
    }
    final adres = p.getString('evdsAdres') ?? kEvdsAdres;
    final faizSeri = p.getString('faizSeri') ?? 'TP.KTF12';
    final enfSeri = p.getString('enfSeri') ?? 'TP.FG.J0';
    messenger.showSnackBar(
        const SnackBar(content: Text('Merkez Bankası verisi alınıyor...')));
    final hatalar = <String>[];
    var basarili = false;

    try {
      final faiz = await evdsSonDeger(adres, key, faizSeri, 90, null);
      if (faiz != null) {
        c['faiz']!.text = oranYaz(faiz.deger / 12);
        faizKaynagi =
            'Merkez Bankası konut kredisi ortalaması: yıllık ${yuzde(faiz.deger)} (${faiz.tarih})';
        basarili = true;
      } else {
        hatalar.add('faiz serisinde veri yok');
      }
    } catch (e) {
      hatalar.add('faiz: $e');
    }

    try {
      final yillik = await evdsSonDeger(adres, key, enfSeri, 150, 3);
      final aylik = await evdsSonDeger(adres, key, enfSeri, 150, 1);
      if (yillik != null) {
        c['enflasyon']!.text = oranYaz(yillik.deger);
        c['kiraArtis']!.text = oranYaz(yillik.deger);
        enfNotu = 'Merkez Bankası (TÜİK verisi): yıllık ${yuzde(yillik.deger)}'
            '${aylik != null ? ', aylık ${yuzde(aylik.deger)}' : ''} (${yillik.tarih})';
        basarili = true;
      } else {
        hatalar.add('TÜFE serisinde veri yok');
      }
    } catch (e) {
      hatalar.add('enflasyon: $e');
    }

    if (basarili) _degisti();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: Duration(seconds: hatalar.isEmpty ? 4 : 10),
      content: Text(hatalar.isEmpty
          ? 'Faiz ve enflasyon güncellendi.'
          : 'Bazı veriler alınamadı: ${hatalar.join(' / ')}. Değerleri elle girebilirsiniz.'),
    ));
  }

  // ----- Banka teklifleri -----

  Future<void> _teklifEkle() async {
    final ad = TextEditingController();
    final oran = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Banka teklifi ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ad,
              decoration: const InputDecoration(labelText: 'Banka adı'),
            ),
            TextField(
              controller: oran,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Aylık faiz (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final o = oranOku(oran.text);
              if (ad.text.trim().isNotEmpty && o > 0) {
                teklifler.add(Teklif(ad.text.trim(), o));
                _degisti();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _teklifKullan(Teklif t) {
    c['faiz']!.text = oranYaz(t.oran);
    faizKaynagi = '${t.ad} teklifi';
    _degisti();
  }

  // ----- Arayüz parçaları -----

  Widget _baslik(String metin) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 8, left: 4),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              gradient: kGradyan,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            metin.toUpperCase(),
            style: const TextStyle(
              fontSize: 13,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: kSoluk,
            ),
          ),
        ],
      ),
    );
  }

  Widget _alan(String anahtar, String etiket, {String? ipucu}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c[anahtar],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: etiket,
          helperText: ipucu,
          helperMaxLines: 2,
        ),
        onChanged: (_) {
          if (anahtar == 'faiz') faizKaynagi = 'Elle girdiniz';
          if (anahtar == 'enflasyon') enfNotu = 'Elle girdiniz';
          _degisti();
        },
      ),
    );
  }

  Widget _satir(String sol, String sag, {bool kalin = false, Color? renk}) {
    final st = TextStyle(
        fontWeight: kalin ? FontWeight.w700 : FontWeight.w400, color: renk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(sol, style: st)),
          Text(sag, style: st),
        ],
      ),
    );
  }

  Widget _kucukNot(String metin) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(metin,
            style: const TextStyle(fontSize: 12, color: kSoluk, height: 1.35)),
      );

  Widget _masrafKarti() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Masraf dökümü',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _satir('Tapu harcı (${tapuTamami ? '%4' : '%2'})', tl(tapu)),
            _satir('Tapu döner sermaye', tl(doner)),
            if (emlakci)
              _satir(
                  'Emlakçı komisyonu (${emlakTamami ? '%4' : '%2'} + KDV)',
                  tl(emlak)),
            _satir('Ekspertiz (bilirkişi raporu)', tl(ekspertiz)),
            _satir('Kredi tahsis ücreti (binde 5)', tl(tahsis)),
            _satir('İpotek ve diğer banka masrafları', tl(banka)),
            _satir('Sigortalar (ilk yıl)', tl(sigorta)),
            const Divider(),
            _satir('Toplam masraf', tl(toplamMasraf), kalin: true),
            _satir('Bankaya giden kısmı', tl(krediMasrafi)),
            _kucukNot(
                'Konut kredisinde BSMV ve KKDF alınmaz. Kesin banka ücretleri sözleşme öncesi bilgi formunda yazar.'),
          ],
        ),
      ),
    );
  }

  Widget _teklifKarti() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Banka teklifleri',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  ),
                  TextButton.icon(
                    onPressed: _teklifEkle,
                    icon: const Icon(Icons.add),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'Kullanmak için dokunun, silmek için basılı tutun. Bankadan aldığınız kesin teklifi buraya ekleyin.',
                  style: const TextStyle(fontSize: 12, color: kSoluk)),
            ),
            for (final t in teklifler)
              ListTile(
                title: Text(t.ad),
                subtitle: Text(
                    'Aylık ${yuzde(t.oran)}, 120 ayda taksit ${tl(taksitHesapla(kredi, t.oran / 100, 120))}'),
                trailing: oranOku(c['faiz']!.text) == t.oran
                    ? const Icon(Icons.check, color: kYesil)
                    : null,
                onTap: () => _teklifKullan(t),
                onLongPress: () {
                  teklifler.remove(t);
                  _degisti();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _hucre(String t, {bool kalin = false, Color? renk, bool sola = false, double boy = 13}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
      child: Text(t,
          textAlign: sola ? TextAlign.left : TextAlign.right,
          style: TextStyle(
              fontSize: boy,
              fontWeight: kalin ? FontWeight.w700 : FontWeight.w500,
              color: renk ?? Colors.white)),
    );
  }

  Widget _tablo(List<String> basliklar, List<TableRow> satirlar,
      {List<double>? genislik}) {
    final w = genislik ?? List.filled(basliklar.length, 1.0);
    return Table(
      columnWidths: {
        for (int i = 0; i < w.length; i++) i: FlexColumnWidth(w[i]),
      },
      children: [
        TableRow(
          decoration: BoxDecoration(
            color: kYuzey2,
            borderRadius: BorderRadius.circular(12),
          ),
          children: [
            for (int i = 0; i < basliklar.length; i++)
              _hucre(basliklar[i],
                  kalin: true, renk: kSoluk, sola: i == 0, boy: 12),
          ],
        ),
        ...satirlar,
      ],
    );
  }

  Widget _mini(String etiket, String deger, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: renk.withOpacity(0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: renk.withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(etiket,
                style: const TextStyle(fontSize: 11.5, color: kSoluk)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(deger,
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: renk)),
            ),
          ],
        ),
      ),
    );
  }

  String _isaretli(double v) => '${v >= 0 ? '+' : '-'}${tlSade(v.abs())}';

  // ----- Sade ekran -----

  final ValueNotifier<int> _yenile = ValueNotifier<int>(0);

  Widget _zemin(Widget cocuk) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A2050), kArka],
          stops: [0.0, 0.4],
        ),
      ),
      child: cocuk,
    );
  }

  EdgeInsets _bosluk() => EdgeInsets.fromLTRB(
      16, MediaQuery.of(context).padding.top + kToolbarHeight + 4, 16, 40);

  void _sayfa(String baslik, List<Widget> Function() icerik) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(title: Text(baslik)),
        body: _zemin(
          ValueListenableBuilder<int>(
            valueListenable: _yenile,
            builder: (c2, _, __) => ListView(
              padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.of(c2).padding.top + kToolbarHeight + 4,
                  16,
                  40),
              children: icerik(),
            ),
          ),
        ),
      ),
    ));
  }

  int? _basabas(double t, int ay) {
    for (int m = 1; m <= ay; m++) {
      if (kiraAy(m) >= t) return m;
    }
    return null;
  }

  Widget _ana() {
    final oran = maxKrediOrani(fiyat, sinif, evVar);
    final maxKredi = fiyat * oran;
    final paraYetmiyor = pesinat < 0;
    final krediFazla = kredi > maxKredi + 0.5;
    final uygun = !paraYetmiyor && !krediFazla;
    final t = taksitHesapla(kredi, aylikFaiz, kiraVade);
    final fark = kira - t;
    final basabas = _basabas(t, kiraVade);
    const beyaz = Colors.white;

    String mesaj;
    if (paraYetmiyor) {
      mesaj = 'Paranız masrafları karşılamıyor. Ev fiyatını düşürün veya para ekleyin.';
    } else if (krediFazla) {
      final enYuksek =
          enYuksekFiyat(para, sinif, sabitMasraf, tapuOrani, emlakOrani, evVar);
      mesaj =
          'Bu evde en fazla ${tl(maxKredi)} (${yuzde(oran * 100, 1)}) kredi çıkar. En az ${tl((kredi - maxKredi) * (1 - kTahsisOrani))} daha nakit gerekir. Eldeki parayla en fazla ${tl(enYuksek)} değerinde ev alınabilir.';
    } else if (fark >= 0) {
      mesaj = 'Kira taksidi karşılıyor. Her ay ${tl(fark)} cebinizde kalır.';
    } else if (basabas != null) {
      mesaj =
          'İlk ay cebinizden ${tl(-fark)} çıkar. Kira zamlarıyla $basabas. ayda taksidi geçer.';
    } else {
      mesaj = 'Her ay cebinizden ${tl(-fark)} çıkar. Bu vadede kira taksidi geçmez.';
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: uygun ? kGradyan : kGradyanKotu,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: (uygun ? kYesil : kKirmizi).withOpacity(0.25),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AYLIK TAKSİT  •  $kiraVade AY',
              style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withOpacity(0.85))),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(tl(t),
                style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: beyaz,
                    height: 1.1)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _ozetKutu('Kredi', tl(kredi))),
              const SizedBox(width: 10),
              Expanded(child: _ozetKutu('Kira', tl(kira))),
            ],
          ),
          const SizedBox(height: 14),
          Text(mesaj,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: beyaz,
                  height: 1.35)),
        ],
      ),
    );
  }

  Widget _ozetKutu(String e, String d) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e,
              style: TextStyle(
                  fontSize: 12, color: Colors.white.withOpacity(0.8))),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(d,
                style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _vadeSecici() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final v in kVadeler)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$v ay'),
                selected: kiraVade == v,
                onSelected: (_) {
                  kiraVade = v;
                  _degisti();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _yilTablosu() {
    final ay = kiraVade;
    final t = taksitHesapla(kredi, aylikFaiz, ay);
    final yil = (ay / 12).ceil();
    final satirlar = <TableRow>[];
    for (int y = 0; y < yil; y++) {
      final k = kiraAy(12 * y + 1);
      satirlar.add(TableRow(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: kKenar.withOpacity(0.6))),
        ),
        children: [
          _hucre('${y + 1}. yıl', sola: true, kalin: true),
          _hucre(tlSade(k)),
          _hucre(tlSade(t)),
          _hucre(_isaretli(k - t),
              kalin: true, renk: k - t >= 0 ? kYesil : kKirmizi),
        ],
      ));
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yıl yıl aylık durum',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
                'Kira her yıl ${yuzde(kiraArtis * 100, 1)} artar, taksit sabit kalır (TL).',
                style: const TextStyle(fontSize: 12, color: kSoluk)),
            const SizedBox(height: 10),
            _tablo(['Yıl', 'Kira', 'Taksit', 'Fark'], satirlar,
                genislik: [1.1, 1.3, 1.3, 1.3]),
          ],
        ),
      ),
    );
  }

  Widget _menu(IconData ikon, String baslik, String alt, VoidCallback f) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: kMavi.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(ikon, color: const Color(0xFF9CC2FF), size: 22),
      ),
      title: Text(baslik,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      subtitle:
          Text(alt, style: const TextStyle(fontSize: 12.5, color: kSoluk)),
      trailing: const Icon(Icons.chevron_right, color: kSoluk),
      onTap: f,
    );
  }

  List<Widget> _masrafSayfasi() => [
        _masrafKarti(),
      ];

  List<Widget> _vadeSayfasi() {
    final satirlar = <TableRow>[];
    for (final v in kVadeler) {
      final tv = taksitHesapla(kredi, aylikFaiz, v);
      final gm = yillikBilesik(aylikGercekMaliyet(kredi - krediMasrafi, tv, v));
      final f = kira - tv;
      satirlar.add(TableRow(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: kKenar.withOpacity(0.6))),
        ),
        children: [
          _hucre('$v ay', sola: true, kalin: true),
          _hucre(tlSade(tv)),
          _hucre(_isaretli(f), kalin: true, renk: f >= 0 ? kYesil : kKirmizi),
          _hucre(tlSade(tv * v)),
          _hucre(yuzde(gm * 100, 0)),
        ],
      ));
    }
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Vadeleri karşılaştır',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text(
                  'Fark: ilk ay kira eksi taksit. Yıllık maliyet: banka masrafları dahil yıllık faiz.',
                  style: TextStyle(fontSize: 12, color: kSoluk)),
              const SizedBox(height: 10),
              _tablo(['Vade', 'Taksit', 'Fark', 'Toplam', 'Yıllık'], satirlar,
                  genislik: [1, 1.3, 1.3, 1.5, 1]),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _ayarSayfasi() {
    final yillikNominal = yillikBilesik(aylikFaiz) * 100;
    return [
      _baslik('Faiz'),
      _kucukNot(
          'Kaynak: $faizKaynagi. Bu oran yıllık bileşik ${yuzde(yillikNominal, 1)} demektir.'),
      const SizedBox(height: 10),
      _teklifKarti(),
      const SizedBox(height: 10),
      const Text('Faiz değişirse ne olur?', style: TextStyle(color: kSoluk)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final d in const [-0.5, -0.25, 0.0, 0.25, 0.5])
            ChoiceChip(
              label: Text(d == 0
                  ? 'Seçili faiz'
                  : '${d > 0 ? '+' : ''}${d.toString().replaceAll('.', ',')} puan'),
              selected: senaryo == d,
              onSelected: (_) {
                senaryo = d;
                _degisti();
              },
            ),
        ],
      ),
      _baslik('Enflasyon ve kira artışı'),
      _alan('enflasyon', 'Yıllık enflasyon (%)'),
      _kucukNot(enfNotu),
      _alan('kiraArtis', 'Yıllık kira artışı (%)',
          ipucu: 'Merkez Bankası’ndan çekince yıllık enflasyon yazılır. Yasal sınır önceki 12 ayın TÜFE ortalamasıdır, gerekirse elle düzeltin'),
      _baslik('Ev'),
      const Text('Enerji kimlik belgesindeki sınıf',
          style: TextStyle(color: kSoluk)),
      const SizedBox(height: 6),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('A–B')),
          ButtonSegment(value: 1, label: Text('C')),
          ButtonSegment(value: 2, label: Text('D ve altı')),
        ],
        selected: {sinif},
        onSelectionChanged: (x) {
          sinif = x.first;
          _degisti();
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: evVar,
        title: const Text('Kredi çekecek kişinin, eşinin veya 18 yaş altı çocuğunun adına kayıtlı konut var'),
        subtitle: const Text('Varsa kredi oranı %75 daralır (BDDK 2023). İlk ev alıyorsanız kapatın.'),
        onChanged: (v) {
          evVar = v;
          _degisti();
        },
      ),
      _baslik('Masraflar'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: tapuTamami,
        title: const Text('Tapu harcının tamamını ben ödüyorum'),
        subtitle: const Text('Açıksa %4, kapalıysa yasal payınız %2'),
        onChanged: (v) {
          tapuTamami = v;
          _degisti();
        },
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: emlakci,
        title: const Text('Emlakçı aracılığıyla alıyorum'),
        subtitle: const Text('Yasal üst sınır: satış bedelinin %2’si + KDV'),
        onChanged: (v) {
          emlakci = v;
          _degisti();
        },
      ),
      if (emlakci)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: emlakTamami,
          title: const Text('Komisyonun tamamını ben ödüyorum'),
          subtitle: const Text('Yazılı anlaşmayla %4 + KDV alıcıya kalabilir'),
          onChanged: (v) {
            emlakTamami = v;
            _degisti();
          },
        ),
      _alan('ekspertiz', 'Ekspertiz / bilirkişi raporu (TL)'),
      _alan('doner', 'Tapu döner sermaye (TL)'),
      _alan('banka', 'İpotek ve diğer banka masrafları (TL)',
          ipucu: 'Örnek (Ziraat): ipotek 3.600 + paket 3.500 + Ailem Ziraat 1.250'),
      _alan('sigorta', 'Sigortalar, ilk yıl (TL)',
          ipucu: 'DASK + hayat + konut sigortası. Örnek (Ziraat, 4 milyon TL kredi): 3.200 + 32.000 + 5.600'),
      _baslik('Güncel veri'),
      FilledButton.icon(
        onPressed: _veriCek,
        icon: const Icon(Icons.cloud_download_outlined),
        label: const Text('Merkez Bankası’ndan faiz ve enflasyonu çek'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _ayarlar,
        icon: const Icon(Icons.key_outlined),
        label: const Text('Bağlantı ayarları (API anahtarı)'),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Konut Kredi Hesaplama',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Ayarlar',
            onPressed: () => _sayfa('Ayarlar', _ayarSayfasi),
          ),
        ],
      ),
      body: _zemin(
        ListView(
          padding: _bosluk(),
          children: [
            _alan('para', 'Elinizdeki para (TL)'),
            _alan('fiyat', 'Ev fiyatı (TL)'),
            Row(
              children: [
                Expanded(child: _alan('kira', 'Aylık kira (TL)')),
                const SizedBox(width: 10),
                Expanded(child: _alan('faiz', 'Aylık faiz (%)')),
              ],
            ),
            const SizedBox(height: 6),
            _vadeSecici(),
            const SizedBox(height: 16),
            _ana(),
            const SizedBox(height: 16),
            _yilTablosu(),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  _menu(Icons.receipt_long_outlined, 'Masraflar',
                      'Tapu, ekspertiz, tahsis ücreti',
                      () => _sayfa('Masraflar', _masrafSayfasi)),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _menu(Icons.compare_arrows, 'Vadeleri karşılaştır',
                      '12 aydan 120 aya taksit ve maliyet',
                      () => _sayfa('Vadeler', _vadeSayfasi)),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _menu(Icons.table_chart_outlined, 'Ay ay ödeme planı',
                      'Seçili vade: $kiraVade ay', () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => OdemePlani(
                          kredi: kredi,
                          aylikFaiz: aylikFaiz,
                          aylikEnf: aylikEnf,
                          ay: kiraVade,
                          kira: kira,
                          kiraArtis: kiraArtis),
                    ));
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bilgi amaçlı hesaplamadır. Kesin rakamlar için bankanın ödeme planını esas alın. Kira geliri üzerindeki vergi, boş kalma ve aidat hesaba katılmamıştır.',
              style: TextStyle(fontSize: 11.5, color: kSoluk, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Ay ay ödeme planı ----------

class OdemePlani extends StatelessWidget {
  const OdemePlani({
    super.key,
    required this.kredi,
    required this.aylikFaiz,
    required this.aylikEnf,
    required this.ay,
    required this.kira,
    required this.kiraArtis,
  });

  final double kredi;
  final double aylikFaiz;
  final double aylikEnf;
  final int ay;
  final double kira;
  final double kiraArtis;

  @override
  Widget build(BuildContext context) {
    final t = taksitHesapla(kredi, aylikFaiz, ay);
    final satirlar = <List<double>>[];
    double kalan = kredi;
    for (int k = 1; k <= ay; k++) {
      final faiz = kalan * aylikFaiz;
      final anapara = t - faiz;
      kalan = max(0.0, kalan - anapara);
      satirlar.add(
          [k.toDouble(), faiz, anapara, kalan, kira * pow(1 + kiraArtis, (k - 1) ~/ 12), kira * pow(1 + kiraArtis, (k - 1) ~/ 12) - t]);
    }
    const kucuk = TextStyle(fontSize: 11.5);
    final baslikStil =
        kucuk.copyWith(fontWeight: FontWeight.w700, color: kSoluk);

    Widget hucre(String s, int flex, TextStyle st, {bool sola = false}) =>
        Expanded(
          flex: flex,
          child: Text(s,
              style: st, textAlign: sola ? TextAlign.left : TextAlign.right),
        );

    return Scaffold(
      appBar: AppBar(title: Text('$ay ay ödeme planı')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aylık taksit ${tl(t)}',
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: kYesil)),
                const SizedBox(height: 4),
                Text('Kredi ${tl(kredi)}, toplam ödeme ${tl(t * ay)}'),
                const SizedBox(height: 8),
                Text(
                  'Erken kapama: "Kalan borç" tutarına ek olarak, kalan vade 36 aydan uzunsa en fazla %2, kısaysa en fazla %1 erken ödeme tazminatı alınabilir. "Kira" o ayki kiradır (yıllık artışla), "Fark" kira eksi taksittir: yeşil ise kira taksidi karşılıyor.',
                  style: const TextStyle(fontSize: 12, color: kSoluk),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                hucre('Ay', 2, baslikStil, sola: true),
                hucre('Faiz', 3, baslikStil),
                hucre('Anapara', 3, baslikStil),
                hucre('Kalan', 4, baslikStil),
                hucre('Kira', 4, baslikStil),
                hucre('Fark', 4, baslikStil),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: satirlar.length,
              itemBuilder: (_, idx) {
                final s = satirlar[idx];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(
                    children: [
                      hucre('${s[0].toInt()}', 2, kucuk, sola: true),
                      hucre(tlSade(s[1]), 3, kucuk),
                      hucre(tlSade(s[2]), 3, kucuk),
                      hucre(tlSade(s[3]), 4, kucuk),
                      hucre(tlSade(s[4]), 4, kucuk),
                      hucre(tlSade(s[5]), 4, kucuk.copyWith(color: s[5] >= 0 ? kYesil : kKirmizi)),
                    ],
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Tutarlar TL', style: kucuk),
          ),
        ],
      ),
    );
  }
}
